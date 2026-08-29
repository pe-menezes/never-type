import AVFoundation
import os

/// The format Whisper consumes: 16 kHz, mono.
public enum AudioSpec {
    public static let sampleRate: Double = 16_000
    public static let channels: AVAudioChannelCount = 1

    /// In-memory processing format: float32, which is what AVAudioConverter produces.
    public static var processing: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: sampleRate,
                      channels: channels,
                      interleaved: false)!
    }

    /// On-disk format: 16-bit little-endian PCM. AVAudioFile converts from
    /// float32 to integer when writing.
    public static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }
}

// The cases hold text, not AVFoundation objects: `Error` implies `Sendable` in
// Swift 6, and AVAudioFormat is not. The text is all the message uses.
public enum AudioError: Error, CustomStringConvertible {
    case converterUnavailable(from: String)
    case bufferAllocationFailed
    case conversionFailed(String)

    public var description: String {
        switch self {
        case .converterUnavailable(let f):
            return "could not convert from \(f) to 16 kHz mono"
        case .bufferAllocationFailed:
            return "failed to allocate audio buffer"
        case .conversionFailed(let e):
            return "audio conversion failed: \(e)"
        }
    }
}

extension AVAudioFormat {
    /// Short description for error messages: "48000 Hz / 2 channel(s)".
    var shortDescription: String {
        "\(Int(sampleRate)) Hz / \(channelCount) channel(s)"
    }
}

/// Converts audio from the hardware format to 16 kHz mono.
///
/// A separate unit from the recorder on purpose: it is the part that can be
/// tested without a microphone, and it is where the easy-to-make mistake lives.
public final class Resampler {
    public let inputFormat: AVAudioFormat
    public let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    public init(inputFormat: AVAudioFormat) throws {
        let output = AudioSpec.processing
        guard let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw AudioError.converterUnavailable(from: inputFormat.shortDescription)
        }
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.converter = converter
    }

    /// Converts one buffer, returning everything the converter produced.
    ///
    /// Returns a list because a single `convert` call does not exhaust the
    /// converter: it fills up to the output buffer's capacity and keeps the
    /// rest. Going up from 8 kHz to 16 kHz that overflowed and the excess was
    /// silently lost.
    public func convert(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
        // The buffer sits in a lock, not in a `var` captured by the block.
        //
        // Since the macOS 26.0 SDK, `AVAudioConverterInputBlock` reaches Swift as
        // `@Sendable`, and a `@Sendable` block cannot capture a `var` nor an
        // `AVAudioPCMBuffer`, which is not `Sendable`. The previous version — with
        // `var supplied` and `input` captured directly — compiled on the toolchain
        // the project was born on (version not recorded) and gives three errors on
        // SDK 26.2 with Swift 6.2.3, without a line having changed. See
        // docs/pitfalls.md.
        //
        // `OSAllocatedUnfairLock` is `Sendable` and holds non-Sendable state via
        // `uncheckedState`: the hop stays compiler-checked, with no `@unchecked
        // Sendable` asserted by me. The block's contract does not change — it
        // hands over the buffer once and answers `.noDataNow` on later calls.
        //
        // What Apple documents: the `convert(to:error:withInputFrom:)` parameter
        // is non-escaping, so the block only runs while the call is in progress.
        // What it does not document: on which thread. The lock costs nanoseconds
        // per call and makes the answer irrelevant.
        let pending = OSAllocatedUnfairLock<AVAudioPCMBuffer?>(uncheckedState: input)
        return try pump { _, status in
            let buffer = pending.withLockUnchecked { slot -> AVAudioPCMBuffer? in
                let taken = slot
                slot = nil
                return taken
            }
            guard let buffer else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
    }

    /// Empties the filter at the end of the recording.
    ///
    /// The converter holds samples inside the resampling filter between calls.
    /// During recording that does not matter: the residue comes out on the next
    /// call. At the end, it matters — without emptying, the last piece of speech
    /// is discarded, and that is where the end of the sentence usually is.
    ///
    /// After draining the converter is no longer usable; the instance dies with the recording.
    public func drain() throws -> [AVAudioPCMBuffer] {
        try pump { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    /// Calls the converter until it stops producing.
    private func pump(_ block: @escaping AVAudioConverterInputBlock) throws -> [AVAudioPCMBuffer] {
        var produced: [AVAudioPCMBuffer] = []
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192) else {
                throw AudioError.bufferAllocationFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError, withInputFrom: block)
            if let conversionError {
                throw AudioError.conversionFailed(conversionError.localizedDescription)
            }
            if out.frameLength > 0 { produced.append(out) }
            // .haveData with a full buffer means there is still output held back.
            guard status == .haveData, out.frameLength > 0 else { break }
        }
        return produced
    }
}

extension AVAudioPCMBuffer {
    /// Independent copy of the contents.
    ///
    /// The buffer handed to the tap is reused by AVAudioEngine as soon as the
    /// callback returns. Taking it to another queue without copying is reading
    /// memory that has already been overwritten.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatFloat32,
              let source = floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let destination = copy.floatChannelData else { return nil }
        copy.frameLength = frameLength
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(frameLength))
        }
        return copy
    }
}

/// Writes the WAV: conversion, drain and discard.
///
/// Separated from `AudioRecorder` on purpose. The part that decides whether the
/// file survives or is deleted is exactly the one the DoD says to guarantee, and
/// it does not need a microphone to be exercised. Before, it could only be
/// tested by speaking.
///
/// Not safe for concurrent use: the caller serializes access.
public final class RecordingSink {
    public let destination: URL
    private var file: AVAudioFile?
    private var resampler: Resampler?
    private var discarded = false

    /// The already-converted samples, accumulated in memory.
    ///
    /// Part 3 transcribes from here, not by re-reading the WAV: the file on disk
    /// keeps existing as a debugging artifact, not as a channel between modules.
    /// A 30 s dictation is ~1.9 MB.
    public private(set) var samples: [Float] = []

    public init(destination: URL) { self.destination = destination }

    public var isOpen: Bool { file != nil }

    public func begin(inputFormat: AVAudioFormat) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        resampler = try Resampler(inputFormat: inputFormat)
        file = try AVAudioFile(forWriting: destination, settings: AudioSpec.fileSettings)
        discarded = false
        samples.removeAll(keepingCapacity: true)
    }

    public func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let resampler, let file else { return }
        for chunk in try resampler.convert(buffer) where chunk.frameLength > 0 {
            try file.write(from: chunk)
            collect(chunk)
        }
    }

    private func collect(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    public func discard() { discarded = true }

    /// Deletes the last dictation's WAV, and its samples in memory.
    ///
    /// This is what "Clear History" calls. Until 2026-08-29 the menu deleted only
    /// `historico.json` and left `last.wav` behind — the whole recording, not
    /// the text. Refuses while a file is open: in hands-free mode the menu opens
    /// with a recording in progress, and then the file is the dictation the user
    /// is making; deleting it from under the `AVAudioFile` would lose that
    /// dictation.
    ///
    /// Returns `true` when no file is left — deleted now or already absent.
    @discardableResult
    public func removeDestination() -> Bool {
        guard !isOpen else { return false }
        samples.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: destination)
        return !FileManager.default.fileExists(atPath: destination.path)
    }

    /// Closes and returns the file, or nil if it was discarded. Idempotent.
    @discardableResult
    public func finish() throws -> URL? {
        guard let resampler, let file else { return nil }
        defer { self.resampler = nil; self.file = nil }
        if !discarded {
            for chunk in try resampler.drain() where chunk.frameLength > 0 {
                try file.write(from: chunk)
                collect(chunk)
            }
            return destination
        }
        self.file = nil
        samples.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: destination)
        return nil
    }
}

/// Input level for the recording indicator, from 0 to 1.
///
/// Exists because the overlay drew exactly the same thing — static red dot and
/// "listening…" — with the microphone working, muted, or pointed at the wrong
/// input. The result was an empty transcription with no clue as to why, which is
/// silent degradation and this project treats it as an error.
///
/// Pure on purpose: silence, speech and clipping are exercisable without a microphone.
public enum AudioLevel {
    /// Below this is silence for drawing purposes.
    ///
    /// -50 dBFS, not -60: on a laptop microphone the room noise and the fan sit
    /// around -55 dBFS, and with the lower floor the bar moved on its own in a
    /// silent room — which would destroy precisely the question the meter exists
    /// to answer.
    public static let floorDB: Float = -50

    /// Converts energy into bar height, on the scale the ear measures with.
    ///
    /// Linear does not work: normal speech sits around 0.05 RMS, and a linear bar
    /// would barely leave the floor with someone speaking loudly.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        guard db > floorDB else { return 0 }
        let linear = min(1, (db - floorDB) / -floorDB)
        // Exponent < 1 opens up the bottom of the scale.
        //
        // With dB alone, conversational speech sat at 0.48 and the drawing barely
        // left the middle: the bars varied by a few pixels and the meter looked
        // dead even with someone speaking.
        return pow(linear, 0.65)
    }

    public static func rms(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return rms(base, count: buffer.count)
        }
    }

    /// The pointer version is the one the tap uses: it runs on the real-time
    /// audio thread and cannot allocate an array per buffer.
    static func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        return (sum / Float(count)).squareRoot()
    }
}

/// Records from the microphone and writes a 16 kHz mono WAV.
public final class AudioRecorder {
    public let destination: URL

    // The engine is born and dies with each dictation, instead of living with the
    // app. A stopped but alive AVAudioEngine keeps the input node configured, and
    // macOS keeps counting the app as a microphone user — the orange indicator in
    // the menu bar stays lit the whole time. In an app whose argument is privacy
    // that is unacceptable even if it is only an indicator.
    private var engine: AVAudioEngine?

    /// Serial queue that owns `file`, `resampler` and `discarded`.
    ///
    /// The tap runs on the real-time audio thread and the shutdown runs on main.
    /// Before, both touched the same file and the same converter with no
    /// synchronization — and the compiler did not complain, because
    /// `AVAudioNodeTapBlock` is not marked `Sendable`. Concentrating all mutation
    /// on this queue fixes the race without blocking the audio thread: the tap
    /// only copies and dispatches.
    private let io = DispatchQueue(label: "com.nevertype.audio-io")
    private let sink: RecordingSink

    public private(set) var isRecording = false

    /// Samples of the last completed dictation, in 16 kHz mono. Empty if cancelled.
    public private(set) var lastSamples: [Float] = []

    /// Called when the recording fails midway. Without this, the error died in a
    /// stderr that goes nowhere when the app is opened from Finder: the icon
    /// stayed red and `stop()` returned the URL as if it had worked.
    /// Set once, before the first recording.
    public var onError: (@MainActor @Sendable (String) -> Void)?

    /// Input level during recording, from 0 to 1. Same contract as `onError`:
    /// set once, before the first recording.
    public var onLevel: (@MainActor @Sendable (Float) -> Void)?

    public init(destination: URL) {
        self.destination = destination
        self.sink = RecordingSink(destination: destination)
    }

    public func start() throws {
        guard !isRecording else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // The input format is read now, not at initialization: switching
        // microphones mid-day (Bluetooth headset) changes the inputNode's format,
        // and a cached converter would start converting from the wrong format.
        let engine = AVAudioEngine()
        self.engine = engine
        // If anything below throws, `isRecording` stays false and `stop()` exits
        // through the guard without releasing anything — the engine would stay
        // alive at rest, with the microphone indicator lit, which is exactly what
        // per-dictation creation exists to avoid.
        var started = false
        defer { if !started { self.engine?.reset(); self.engine = nil } }

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        try io.sync { try self.sink.begin(inputFormat: hardwareFormat) }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            // On the audio thread, only copy and leave. Converting and writing
            // happen on the I/O queue.
            guard let self else { return }
            // The level comes from here, before the copy: it is 4096
            // multiplications, and waiting for the I/O queue would lag the
            // indicator behind the voice. `Task { @MainActor in }` and not
            // `assumeIsolated` — the audio thread is definitely not main.
            if let onLevel = self.onLevel, let channel = buffer.floatChannelData?[0] {
                // Four readings per buffer, not one.
                //
                // The tap's buffer has 4096 frames — at ~48 kHz, 85 ms. One level
                // per buffer gave 12 frames per second, and the meter looked
                // frozen even during speech. Slicing here quadruples the rate
                // without touching the buffer size, that is, without touching the
                // path that records the audio.
                let total = Int(buffer.frameLength)
                let slices = 4
                let size = total / slices
                guard size > 0 else { return }
                var levels: [Float] = []
                for i in 0..<slices {
                    levels.append(AudioLevel.normalized(
                        rms: AudioLevel.rms(channel + i * size, count: size)))
                }
                Task { @MainActor in for level in levels { onLevel(level) } }
            }
            guard let copy = buffer.deepCopy() else { return }
            self.io.async { self.append(copy) }
        }

        engine.prepare()
        try engine.start()
        started = true
        isRecording = true
    }

    /// Converts and writes. Always on the I/O queue.
    private func append(_ buffer: AVAudioPCMBuffer) {
        do { try sink.append(buffer) } catch { report("recording interrupted: \(error)") }
    }

    private func report(_ message: String) {
        FileHandle.standardError.write(Data("nevertype: \(message)\n".utf8))
        // `Task { @MainActor in }` instead of assuming isolation: the hop is
        // checked by the compiler, not asserted by me.
        if let onError { Task { @MainActor in onError(message) } }
    }

    /// Stops and returns the file. Returns nil if the recording was cancelled.
    @discardableResult
    public func stop() -> URL? {
        guard isRecording else { return nil }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        // Releasing the instance is what makes macOS actually free the microphone.
        engine = nil
        isRecording = false

        // `sync` works as a barrier: waits for any in-flight append to finish
        // before draining and closing. `removeTap` does not guarantee that no
        // callback is running.
        var result: URL?
        io.sync {
            do { result = try self.sink.finish() }
            catch { self.report("end of recording lost: \(error)") }
            self.lastSamples = self.sink.samples
        }
        return result
    }

    /// Cancels: stops and deletes the file, leaving no trace.
    public func cancel() {
        guard isRecording else { return }
        io.sync { self.sink.discard() }
        stop()
    }

    /// Deletes the last dictation's WAV and forgets its samples.
    ///
    /// Called by "Clear History". Does nothing during a recording: the open file
    /// is the dictation in progress. The guard that counts is the
    /// `RecordingSink`'s (open file), exercised in tests; this one reads the same
    /// fact from the recorder's side, so as not to even enter the I/O queue — and
    /// it is the only part of this path the test cannot reach without a microphone.
    /// Returns `true` when no file is left.
    @discardableResult
    public func discardLastRecording() -> Bool {
        guard !isRecording else { return false }
        var removed = false
        io.sync { removed = self.sink.removeDestination() }
        lastSamples = []
        return removed
    }
}
