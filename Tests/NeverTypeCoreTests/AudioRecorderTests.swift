import AVFoundation
import Testing
@testable import NeverTypeCore

// XCTest lives inside Xcode, which this machine does not have — Part 2 decided
// to build without it. swift-testing ships with the Swift 6 toolchain itself and
// runs under `swift test` all the same.
@Suite("Audio conversion")
struct AudioConversionTests {

    /// Generates a synthetic tone in the requested format, without touching the hardware.
    private func tone(format: AVAudioFormat, seconds: Double, hz: Double = 440) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try #require(buffer.floatChannelData)
        for ch in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) {
                let t = Double(frame) / format.sampleRate
                channels[ch][frame] = Float(sin(2 * .pi * hz * t) * 0.5)
            }
        }
        return buffer
    }

    private func frames(_ buffers: [AVAudioPCMBuffer]) -> Int {
        buffers.reduce(0) { $0 + Int($1.frameLength) }
    }

    private func hardware(_ rate: Double, _ channels: AVAudioChannelCount) throws -> AVAudioFormat {
        try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: rate,
                                   channels: channels,
                                   interleaved: false))
    }

    /// The real case: the hardware delivers 48 kHz stereo, Whisper wants 16 kHz mono.
    @Test("48 kHz stereo becomes 16 kHz mono")
    func convertsFortyEightStereoToSixteenMono() throws {
        let input = try hardware(48_000, 2)
        let resampler = try Resampler(inputFormat: input)

        #expect(resampler.outputFormat.sampleRate == 16_000)
        #expect(resampler.outputFormat.channelCount == 1)

        let output = try resampler.convert(try tone(format: input, seconds: 1.0))
        let first = try #require(output.first)
        #expect(first.format.sampleRate == 16_000)
        #expect(first.format.channelCount == 1)

        // One second in, one second out — counting the drain. Without it the
        // filter holds the end of the speech, which in a dictation is the last word.
        let total = frames(output) + frames(try resampler.drain())
        #expect(abs(total - 16_000) <= 40, "1 s should become ~16000 frames, got \(total)")
    }

    /// If the hardware already delivers 16 kHz mono, the conversion is identity:
    /// it cannot lose or invent a sample.
    @Test("16 kHz mono passes through intact")
    func passesThroughWhenHardwareAlreadyMatches() throws {
        let input = try hardware(16_000, 1)
        let resampler = try Resampler(inputFormat: input)
        let output = try resampler.convert(try tone(format: input, seconds: 0.5))
        #expect(frames(output) + frames(try resampler.drain()) == 8_000)
    }

    /// A Bluetooth headset enters HFP at 8 kHz when the microphone opens. Part 2
    /// does not fix the quality of that, but the conversion cannot break.
    @Test("8 kHz from a Bluetooth headset goes up to 16 kHz")
    func upsamplesFromBluetoothHandsFreeRate() throws {
        let input = try hardware(8_000, 1)
        let resampler = try Resampler(inputFormat: input)
        let output = try resampler.convert(try tone(format: input, seconds: 1.0))
        #expect(try #require(output.first).format.sampleRate == 16_000)
        let total = frames(output) + frames(try resampler.drain())
        #expect(abs(total - 16_000) <= 40, "got \(total)")
    }

    /// Guard against the bug found while writing these tests: the drain cannot
    /// return empty after a conversion that held samples, or the end of the speech vanishes.
    @Test("the drain returns what the filter held")
    func drainReturnsTheHeldTail() throws {
        let input = try hardware(48_000, 2)
        let resampler = try Resampler(inputFormat: input)
        let body = try resampler.convert(try tone(format: input, seconds: 1.0))
        let tail = try resampler.drain()
        #expect(frames(tail) > 0, "the filter held samples and the drain returned nothing")
        #expect(frames(body) < 16_000, "if nothing was held, this test lost its point")
    }

    /// The contract with whisper-cli. If this changes, Part 3 breaks without warning.
    @Test("on-disk format is what Whisper expects")
    func fileSettingsMatchWhatWhisperExpects() {
        let s = AudioSpec.fileSettings
        #expect(s[AVSampleRateKey] as? Double == 16_000)
        #expect(s[AVNumberOfChannelsKey] as? AVAudioChannelCount == 1)
        #expect(s[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(s[AVLinearPCMIsFloatKey] as? Bool == false)
    }
}

@Suite("Hotkey trigger")
struct HotkeyTriggerTests {
    /// The trigger needs to be a pure modifier identified by side: the `.command`
    /// mask is set with either of the two ⌘, so only the keyCode plus the device
    /// mask tells the right one from the left.
    @Test("right ⌘ has a distinct keyCode and device mask")
    func rightCommandIsIdentifiedByCodeAndMask() {
        let t = HotkeyMonitor.Trigger.rightCommand
        #expect(t.keyCode == 54)
        #expect(t.deviceMask == 0x0010)
        #expect(t.deviceMask != HotkeyMonitor.Trigger.rightOption.deviceMask)
        #expect(t.keyCode != HotkeyMonitor.Trigger.rightOption.keyCode)
    }

    /// The choice is saved by keyCode, not by label: a label is interface text
    /// and changes; the keyCode is stable across macOS versions.
    @Test("the chosen key survives a round trip through the identifier")
    func triggerRoundTripsThroughID() {
        for option in HotkeyMonitor.Trigger.all {
            #expect(HotkeyMonitor.Trigger.named(option.id)?.keyCode == option.keyCode)
        }
    }

    @Test("unknown or missing identifier returns no trigger")
    func unknownTriggerIsNil() {
        #expect(HotkeyMonitor.Trigger.named(nil) == nil)
        #expect(HotkeyMonitor.Trigger.named("999") == nil, "keyCode we do not offer")
        #expect(HotkeyMonitor.Trigger.named("Right ⌘") == nil, "a label is not an identifier")
    }

    /// Pure modifiers only: anything else would require swallowing the event
    /// with a CGEventTap, which the project refused.
    @Test("all options are pure modifiers and distinct from each other")
    func optionsAreDistinctPureModifiers() {
        let codes = HotkeyMonitor.Trigger.all.map(\.keyCode)
        let masks = HotkeyMonitor.Trigger.all.map(\.deviceMask)
        #expect(Set(codes).count == codes.count, "a repeated keyCode would make two options become one")
        #expect(Set(masks).count == masks.count, "a repeated mask would not tell the side")
    }
}


/// The file's life cycle — the part DoD 4 says to guarantee and that, until the
/// Part 2 audit, could only be exercised by speaking into the microphone.
@Suite("Recording file cycle")
struct RecordingSinkTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-test-\(UUID().uuidString)")
            .appendingPathComponent("last.wav")
    }

    private func hardware() throws -> AVAudioFormat {
        try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 48_000, channels: 2, interleaved: false))
    }

    private func buffer(_ format: AVAudioFormat, seconds: Double) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let b = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        b.frameLength = frames
        let ch = try #require(b.floatChannelData)
        for c in 0..<Int(format.channelCount) {
            for f in 0..<Int(frames) { ch[c][f] = Float(sin(Double(f) * 0.01) * 0.3) }
        }
        return b
    }

    @Test("a completed recording leaves the file in Whisper's format")
    func finishKeepsFile() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        let result = try sink.finish()

        #expect(result == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let written = try AVAudioFile(forReading: url)
        #expect(written.fileFormat.sampleRate == 16_000)
        #expect(written.fileFormat.channelCount == 1)
        #expect(written.length > 7_000, "0.5 s should give ~8000 frames, gave \(written.length)")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// DoD check 4: a regular key during the hold cancels **without producing a file**.
    @Test("cancelling deletes the file and returns no URL")
    func discardRemovesFile() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        #expect(FileManager.default.fileExists(atPath: url.path), "the file exists during the recording")

        sink.discard()
        let result = try sink.finish()

        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path), "cancelling has to delete the file")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("finish twice neither breaks nor resurrects the file")
    func finishIsIdempotent() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))
        #expect(try sink.finish() == url)
        #expect(try sink.finish() == nil, "the second call has nothing to close")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("cancelling after closing does not delete what was already saved")
    func discardAfterFinishDoesNotDelete() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))
        _ = try sink.finish()
        sink.discard()
        _ = try sink.finish()
        #expect(FileManager.default.fileExists(atPath: url.path), "an already completed recording cannot be deleted afterwards")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// The dictation's audio stays in memory for Part 3 to transcribe. Cancelling
    /// has to erase that too, not just the file — and no test covered it, so
    /// swapping the order in `finish()` would silently break the cleanup.
    @Test("cancelling clears the samples from memory, not just the file")
    func discardClearsSamples() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        #expect(sink.samples.count > 0, "during the recording the samples exist")

        sink.discard()
        _ = try sink.finish()
        #expect(sink.samples.isEmpty, "cancelling has to discard the audio from memory")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("a completed recording preserves the samples for transcription")
    func finishKeepsSamples() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        _ = try sink.finish()
        // 0.5 s at 16 kHz, drain included.
        #expect(abs(sink.samples.count - 8_000) <= 40, "got \(sink.samples.count)")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("append without begin neither writes nor breaks")
    func appendWithoutBeginIsSafe() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        try sink.append(try buffer(try hardware(), seconds: 0.1))
        #expect(!sink.isOpen)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// "Clear History" deletes the text and also this file: the audio is the
    /// whole recording, and keeping it after the user asked to clear would be
    /// keeping precisely what they asked to delete.
    @Test("clearing deletes the previous dictation's WAV and the samples")
    func removeDestinationDeletesFinishedRecording() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))
        _ = try sink.finish()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!sink.samples.isEmpty)

        #expect(sink.removeDestination())
        #expect(!FileManager.default.fileExists(atPath: url.path), "the WAV has to go")
        #expect(sink.samples.isEmpty, "the samples in memory too")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// In hands-free mode the menu opens with a recording in progress, so
    /// "Clear History" can be clicked mid-dictation. The open file is that dictation's.
    @Test("clearing during the recording does not touch the open file")
    func removeDestinationRefusesWhileRecording() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))

        #expect(!sink.removeDestination(), "with a file open the removal is refused")
        #expect(FileManager.default.fileExists(atPath: url.path), "the recording in progress stays on disk")
        #expect(!sink.samples.isEmpty, "and its samples stay")
        #expect(try sink.finish() == url, "the recording finishes normally after the refusal")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("clearing without a file does not break and answers that nothing is left")
    func removeDestinationWithoutFileIsSafe() {
        let sink = RecordingSink(destination: tempURL())
        #expect(sink.removeDestination())
    }

    /// The recorder forwards the cleanup to the sink through the I/O queue and
    /// forgets the last dictation's samples. The refusal during a recording is
    /// not reachable from here without a microphone — it is covered in
    /// `RecordingSink`, where the real guard (open file) lives.
    @Test("the recorder deletes the previous WAV and forgets the samples")
    func recorderDiscardsLastRecording() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: url)
        let recorder = AudioRecorder(destination: url)

        #expect(recorder.discardLastRecording())
        #expect(!FileManager.default.fileExists(atPath: url.path), "the WAV has to go")
        #expect(recorder.lastSamples.isEmpty)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// The meter exists to answer one question: is sound coming in? So what gets
/// tested is precisely the distinction between silence and sound — not the looks.
@Suite("Microphone input level")
struct AudioLevelTests {

    @Test("absolute silence gives zero")
    func silenceIsZero() {
        #expect(AudioLevel.rms([Float](repeating: 0, count: 1024)) == 0)
        #expect(AudioLevel.normalized(rms: 0) == 0)
    }

    /// The case that motivates the item: a muted microphone delivers near-zero
    /// samples, and that has to show up as silence, not as a trembling bar.
    @Test("noise below the -50 dBFS floor counts as silence")
    func noiseFloorIsSilence() {
        // -60 dBFS: room noise on a laptop microphone.
        let quiet = AudioLevel.normalized(rms: 0.001)
        #expect(quiet == 0, "got \(quiet) — below the floor the bar cannot move")
    }

    @Test("normal speech sits mid-scale, not glued to the floor")
    func speechIsVisible() {
        // ~0.05 RMS is speech at conversation volume.
        let level = AudioLevel.normalized(rms: 0.05)
        #expect(level > 0.3 && level < 0.9,
                "got \(level) — a linear scale would leave speech nearly invisible")
    }

    @Test("clipping saturates at 1, does not go past")
    func clippingClamps() {
        #expect(AudioLevel.normalized(rms: 1.0) == 1)
        #expect(AudioLevel.normalized(rms: 4.0) == 1, "above 0 dBFS it stays 1")
    }

    @Test("the RMS follows the signal's energy")
    func rmsFollowsEnergy() {
        let low = AudioLevel.rms([Float](repeating: 0.1, count: 512))
        let high = AudioLevel.rms([Float](repeating: 0.5, count: 512))
        #expect(high > low)
        #expect(abs(low - 0.1) < 0.0001, "constant signal: the RMS is the value itself")
    }

    @Test("empty array does not break")
    func emptyIsSafe() {
        #expect(AudioLevel.rms([]) == 0)
    }
}


/// The hands-free latch. Every path here is one that, without the separate state
/// machine, could only be exercised by pressing keys at exact milliseconds.
@Suite("Hands-free latch")
struct LatchTests {
    private typealias L = HotkeyMonitor.Latch

    @Test("a normal hold is still press and release")
    func normalHold() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(L.tapThreshold + 0.1)) == [.finish])
        #expect(!latch.isLatched)
    }

    /// A modal permission alert keeps pumping events. Unless a refused start
    /// resets the gesture first, its release arms the double-tap window and a
    /// second attempt becomes hands-free without ever starting a recording.
    @Test("a rejected start resets the gesture before its release arrives")
    func rejectedStartResetsGesture() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])

        latch.resolveStart(accepted: false)

        #expect(latch.handle(.up(0.08)) == [])
        #expect(latch.handle(.down(0.12)) == [.start],
                "the next press is a fresh attempt, not a hands-free latch")
    }

    /// A short tap does not conclude right away: it waits to see whether the second one comes.
    @Test("a short tap delays the conclusion and concludes on timeout")
    func shortTapWaitsThenFinishes() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(0.05)) == [.armTimeout(L.tapWindow)],
                "a short tap cannot conclude before the second-tap window")
        #expect(latch.handle(.timeout) == [.finish])
    }

    @Test("double tap locks, and the recording goes on without the key")
    func doubleTapLatches() {
        var latch = L()
        _ = latch.handle(.down(0))
        _ = latch.handle(.up(0.05))
        #expect(latch.handle(.down(0.15)) == [.disarmTimeout, .latch])
        #expect(latch.isLatched)
        // The second tap's `up` cannot finish anything.
        #expect(latch.handle(.up(0.2)) == [])
        #expect(latch.isLatched)
    }

    @Test("locked, one tap finishes and transcribes")
    func tapStopsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.down(5)) == [.finish])
        #expect(!latch.isLatched)
        #expect(latch.handle(.up(5.05)) == [], "the following up is ignored")
    }

    @Test("locked, Esc discards")
    func escapeCancelsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.escape) == [.cancel])
        #expect(!latch.isLatched)
    }

    /// The deliberate difference between the two modes: while holding, a regular
    /// key means "this was a shortcut"; in hands-free, typing is just typing.
    @Test("locked, a regular key does NOT cancel")
    func otherKeyDoesNotCancelLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.otherKey) == [])
        #expect(latch.isLatched, "cancelling a long dictation because of a key kills the mode")
    }

    @Test("holding, a regular key cancels as before")
    func otherKeyCancelsHold() {
        var latch = L()
        _ = latch.handle(.down(0))
        #expect(latch.handle(.otherKey) == [.cancel])
    }

    @Test("a regular key in the second-tap window also cancels")
    func otherKeyCancelsWhileWaiting() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05))
        #expect(latch.handle(.otherKey) == [.disarmTimeout, .cancel])
    }

    @Test("out-of-order event does nothing")
    func strayEventsAreIgnored() {
        var latch = L()
        #expect(latch.handle(.up(0)) == [], "release without having pressed")
        #expect(latch.handle(.timeout) == [], "timeout with no window armed")
        #expect(latch.handle(.otherKey) == [], "regular key with nothing in progress")
    }
}
