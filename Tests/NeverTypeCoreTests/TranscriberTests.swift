import Foundation
import Testing
@testable import NeverTypeCore

@Suite("Model location and validation")
struct ModelStoreTests {

    @Test("the ggml magic is validated by bytes, not by text")
    func validatesByMagicBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // The magic 0x67676d6c written little-endian: the bytes come out "lmgg".
        // Looking for the text "ggml" rejects every valid model — a mistake
        // already made in this project, and this test exists so it does not come back.
        //
        // The rule is exercised without touching the disk so as not to write
        // 400 MB per run of the suite.
        let ok = Data([0x6c, 0x6d, 0x67, 0x67])
        #expect(ModelStore.isValid(magic: ok, size: ModelStore.minimumBytes))
        #expect(!ModelStore.isValid(magic: ok, size: ModelStore.minimumBytes - 1),
                "the right magic with a truncated download's size cannot pass")
        #expect(!ModelStore.isValid(magic: Data("ggml".utf8), size: ModelStore.minimumBytes),
                "\"ggml\" as text is not the magic")

        // What a filtering proxy returns when it blocks the download.
        let html = dir.appendingPathComponent("blocked.bin")
        try Data("<html><body>403</body></html>".utf8).write(to: html)
        #expect(!ModelStore.isValid(html))

        let empty = dir.appendingPathComponent("empty.bin")
        try Data().write(to: empty)
        #expect(!ModelStore.isValid(empty))

        #expect(!ModelStore.isValid(dir.appendingPathComponent("does-not-exist.bin")))
    }

    /// A truncated model starts with the right magic, whisper.cpp accepts it as an
    /// "empty model", and the first inference kills the process with a C++
    /// exception no Swift `try` intercepts. The Part 3 audit reproduced it:
    /// 100 KB of the real model in the production path → exit 134, with no
    /// warning on screen.
    @Test("a truncated model with a valid magic is rejected")
    func truncatedModelRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truncated-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // Correct magic, size of an interrupted download.
        var bytes = Data([0x6c, 0x6d, 0x67, 0x67])
        bytes.append(Data(repeating: 0, count: 100 * 1024))
        try bytes.write(to: url)

        #expect(!ModelStore.isValid(url), "a valid magic cannot be enough")
        #expect(throws: TranscriberError.self) { _ = try Transcriber(modelURL: url) }
    }

    /// The positive case of the disk validator. Until here `isValid(_:)` only had
    /// its negatives exercised (HTML, empty, truncated, absent): a validator that
    /// refused everything would pass the suite. Sparse file: `truncate` extends
    /// the logical size without writing the bytes, so the test costs KB, not the
    /// floor's 400 MB — and the logical size is what `isValid` reads.
    @Test("on disk, the size floor separates a whole model from a truncated download")
    func diskFloorSeparatesWholeFromTruncated() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-floor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func sparseModel(named name: String, bytes: Int) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data([0x6c, 0x6d, 0x67, 0x67]).write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(bytes))
            return url
        }

        let whole = try sparseModel(named: "whole.bin", bytes: ModelStore.minimumBytes)
        let truncated = try sparseModel(named: "truncated.bin", bytes: ModelStore.minimumBytes - 1)

        let wholeAttributes = try FileManager.default.attributesOfItem(atPath: whole.path)
        let wholeSize = try #require(wholeAttributes[.size] as? Int)
        #expect(wholeSize == ModelStore.minimumBytes,
                "the sparse file needs to report the logical size, got \(wholeSize)")
        #expect(ModelStore.isValid(whole), "right magic and size at the floor is a whole model")
        #expect(!ModelStore.isValid(truncated), "one byte below the floor is a truncated download")
    }

    @Test("the model is looked for in Application Support, outside the repository")
    func modelLivesOutsideTheRepo() {
        let path = ModelStore.modelURL.path
        #expect(path.contains("Application Support/NeverType/models"))
        #expect(path.hasSuffix("ggml-large-v3-turbo-q5_0.bin"))
    }

    @Test("a missing model fails with an instruction, not a raw error")
    func missingModelExplainsItself() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).bin")
        #expect(throws: TranscriberError.self) {
            _ = try Transcriber(modelURL: absent)
        }
        let message = String(describing: TranscriberError.modelMissing(absent))
        #expect(message.contains("fetch-model.sh"), "the error needs to say what to do")
    }

    @Test("an invalid file is rejected before trying to load")
    func invalidModelRejectedEarly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-\(UUID().uuidString).bin")
        try Data("<html>403</html>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: TranscriberError.self) {
            _ = try Transcriber(modelURL: url)
        }
    }
}


/// First available fixture, if there is any.
///
/// The fixtures are voice recordings of whoever develops and are not versioned,
/// so in a clean clone there is none. Without this check the whole suite
/// **failed** instead of being skipped — `#require` fails the test, it does not
/// suspend it.
func firstFixture() -> URL? {
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("fixtures")
    let wavs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "wav" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return wavs?.first
}

func transcriptionTestsRunnable() -> Bool {
    FileManager.default.fileExists(atPath: ModelStore.modelURL.path) && firstFixture() != nil
}

/// Real transcription. Needs the model installed **and** at least one recorded
/// fixture — both live outside the repository.
@Suite("Local transcription", .enabled(if: transcriptionTestsRunnable()))
struct TranscriberTests {

    @Test("transcribes a recorded fixture")
    func transcribesRealAudio() throws {
        let fixture = try #require(firstFixture())
        let samples = try readSamples(fixture)
        #expect(samples.count > 16_000, "the fixture needs at least 1 s of audio")

        let transcriber = try Transcriber()
        let text = try transcriber.transcribe(samples)

        // The assertion is about the mechanism, not about specific words: the
        // content depends on what whoever cloned recorded.
        #expect(!text.isEmpty, "the transcription cannot come back empty")
        #expect(text.count < samples.count / 40,
                "text out of proportion to the audio suggests hallucination: \(text.count) chars")
    }

    /// The warm-up exists so the first real transcription is not the slowest.
    /// Here we only make sure it runs and does not break.
    @Test("warm-up neither throws nor invalidates the context")
    func warmUpKeepsContextUsable() throws {
        let transcriber = try Transcriber()
        transcriber.warmUp()
        let text = try transcriber.transcribe([Float](repeating: 0, count: 16_000))
        #expect(text.count < 200, "silence should not become a paragraph: \(text)")
    }

    /// Walks the RIFF chunks until it finds `data`, instead of assuming 44 bytes.
    ///
    /// The ffmpeg fixtures have `data` at exactly 44 bytes, but the WAV the app
    /// itself writes (via `AVAudioFile`) has it at **4096** — there is a JUNK
    /// padding chunk. With the fixed offset, pointing the test at a file from the
    /// app would swallow 4052 bytes of padding as audio and the test would
    /// **pass** reading the wrong input. The old premise was true by accident of
    /// the recording tool, not by property of the format.
    private func readSamples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var offset = 12   // "RIFF" + size + "WAVE"
        var dataRange: Range<Int>?

        func u32(_ at: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) }
        }

        while offset + 8 <= data.count {
            let id = String(decoding: data[(data.startIndex + offset)..<(data.startIndex + offset + 4)], as: UTF8.self)
            let size = u32(offset + 4)
            if id == "data" {
                dataRange = (offset + 8)..<min(offset + 8 + size, data.count)
                break
            }
            offset += 8 + size + (size % 2)   // chunks are padded to an even size
        }

        let range = try #require(dataRange, "'data' chunk not found in \(url.lastPathComponent)")
        let pcm = Array(data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)])
        return stride(from: 0, to: pcm.count - 1, by: 2).map { i in
            Float(Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i + 1]) << 8)) / 32768.0
        }
    }
}
