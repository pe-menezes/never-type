import CWhisper
import Foundation

/// Where the model lives once installed.
public enum ModelStore {
    public static let fileName = "ggml-large-v3-turbo-q5_0.bin"

    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeverType/models")
    }

    public static var modelURL: URL { directory.appendingPathComponent(fileName) }

    /// Size floor, in bytes: 400 MB for a 547 MB model.
    ///
    /// The magic alone is not enough, and the gap is serious: a truncated file
    /// starts with the right 4 bytes, whisper.cpp accepts it as an "empty model
    /// for testing" and returns a **valid** context — and the first inference
    /// kills the process with `std::out_of_range`, a C++ exception no Swift `try`
    /// intercepts. The app warns about nothing: it simply does not open.
    ///
    /// Proportional to the real artifact, not to a theoretical minimum: until
    /// 2026-08-29 the floor was 50 MB, justified by the smallest candidate on the
    /// bench (181 MB) — but the app only loads `fileName`, which is 547 MB, and
    /// 50 MB approved a download interrupted at any point above that. The same
    /// 400 holds in `install.sh`, `verify-install.sh`, `fetch-model.sh` and, for
    /// this model, in `setup-bench.sh`; changing it here requires changing it there.
    public static let minimumBytes = 400 * 1024 * 1024

    /// The ggml magic is written as a little-endian uint32, so the bytes in the
    /// file come out reversed: `6c6d6767`, which read as text becomes "lmgg",
    /// not "ggml". Checking the text directly rejects every valid model — a
    /// mistake already made in this project.
    public static func isValid(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)) ?? Data()
        return isValid(magic: magic, size: size)
    }

    /// The rule itself, separated from the disk read.
    ///
    /// That way the size floor can be tested without writing 400 MB on every run
    /// of the suite. (The test for the on-disk path uses a sparse file for the
    /// same reason.)
    public static func isValid(magic: Data, size: Int) -> Bool {
        guard size >= minimumBytes else { return false }
        guard magic.count == 4 else { return false }
        return magic.map { String(format: "%02x", $0) }.joined() == "6c6d6767"
    }
}

public enum TranscriberError: Error, CustomStringConvertible {
    case modelMissing(URL)
    case modelInvalid(URL)
    case contextFailed
    case inferenceFailed(Int32)

    public var description: String {
        switch self {
        case .modelMissing(let u):
            return "model not found at \(u.path). Run scripts/fetch-model.sh"
        case .modelInvalid(let u):
            return "the file at \(u.path) is not a complete ggml model (truncated or corrupt). Run scripts/fetch-model.sh"
        case .contextFailed:
            return "could not load the model into memory"
        case .inferenceFailed(let code):
            return "transcription failed (code \(code))"
        }
    }
}

/// Transcribes audio locally, with the model loaded once and kept warm.
///
/// Not safe for concurrent use: the whisper.cpp context must be used serially.
/// The caller serializes — in the app, the `TranscriptionService` actor
/// (main.swift), which makes the compiler guarantee it instead of relying on
/// dispatching through a queue.
public final class Transcriber {
    private let context: OpaquePointer
    public private(set) var backend: String = ""

    public init(modelURL: URL = ModelStore.modelURL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriberError.modelMissing(modelURL)
        }
        guard ModelStore.isValid(modelURL) else {
            throw TranscriberError.modelInvalid(modelURL)
        }

        // `ggml_backend_load_all()` was removed from here.
        //
        // It scans the executable's directory **and the current working
        // directory** looking for `libggml-<name>-*.so` to `dlopen`. With dynamic
        // linking it was necessary; with the static build the three backends
        // already come registered by the ggml registry's constructor — the audit
        // proved it with a probe that does not call it and still lists MTL, BLAS
        // and CPU. Today the hardened runtime blocks the load, but the call only
        // opened surface without delivering anything: one more entitlement line
        // and it would become arbitrary code execution in a process that holds
        // Accessibility.
        //
        // The check below is what guarantees Metal is really active.

        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw TranscriberError.contextFailed
        }
        context = ctx

        // Enumerates the devices ggml actually registered, instead of looking
        // for the word "metal" in a log — which was the false negative caught in
        // the Part 1 audit: a CPU run's log contains dozens of lines with
        // "metal", coming from the device enumeration.
        var devices: [String] = []
        for i in 0..<ggml_backend_dev_count() {
            guard let dev = ggml_backend_dev_get(i) else { continue }
            devices.append(String(cString: ggml_backend_dev_name(dev)))
        }
        self.devices = devices
        self.usesMetal = devices.contains { $0.uppercased().contains("MTL") || $0.uppercased().contains("METAL") }
        backend = devices.joined(separator: ", ")
    }

    /// Devices registered by ggml.
    public private(set) var devices: [String] = []

    /// Whether the warm-up ran successfully. Set by whoever calls `warmUp()`.
    public var warmedUp = false

    /// If false, inference runs on the CPU — about 11x slower, measured. Not a
    /// cosmetic warning: it is the difference between the app being useful or not.
    public private(set) var usesMetal = false

    deinit { whisper_free(context) }

    /// Runs a throwaway inference before the first real dictation.
    ///
    /// **The original justification was wrong and is worth recording.** The
    /// spike measured 968 ms on the first transcription against 664 ms on the
    /// second and I attributed the difference to Metal pipeline compilation. An
    /// A/B from the audit, in cold processes, showed the real gain: ~25 ms
    /// (without warm-up 617–655 ms, with warm-up 619–634 ms). The spike's 304 ms
    /// were something else — the true "first time" cost is
    /// `ggml_metal_library_init`, measured at 6.4 s with the OS shader cache
    /// cold, and it happens inside `init`, not here.
    ///
    /// Kept anyway: it costs ~600 ms of readiness in the background, at launch,
    /// and buys ~25 ms on the first dictation. Cheap, invisible, and the return
    /// value now says whether it worked instead of pretending.
    @discardableResult
    public func warmUp() -> Bool {
        let silence = [Float](repeating: 0, count: 16_000)
        do {
            _ = try transcribe(silence)
            return true
        } catch {
            return false
        }
    }

    /// `prompt` is whisper's `initial_prompt`: terms the model should expect to
    /// hear. A recognition hint, not a guarantee — the guarantee comes from the
    /// replacement, which runs afterwards and does not go through the model.
    public func transcribe(_ samples: [Float], prompt: String? = nil) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.n_threads = 4

        var text = ""
        var failure: Int32 = 0

        // The C pointers need to stay alive during `whisper_full`, which is why
        // the call happens inside the nested `withCString` instead of keeping the
        // pointers in variables.
        func run(_ params: whisper_full_params) {
            let code = whisper_full(context, params, samples, Int32(samples.count))
            guard code == 0 else { failure = code; return }
            for i in 0..<whisper_full_n_segments(context) {
                text += String(cString: whisper_full_get_segment_text(context, i))
            }
        }

        // The language is fixed: the app transcribes Portuguese only.
        "pt".withCString { language in
            params.language = language
            if let prompt, !prompt.isEmpty {
                prompt.withCString { hint in
                    params.initial_prompt = hint
                    run(params)
                }
            } else {
                run(params)
            }
        }
        guard failure == 0 else { throw TranscriberError.inferenceFailed(failure) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
