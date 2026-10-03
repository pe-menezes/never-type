import Foundation
import Testing
@testable import NeverTypeCore

/// The machine around `MediaPause`: which apps are putting out sound, the
/// commands sent, and a clock that only moves when the code waits.
@MainActor
private final class FakeMedia {
    var playing: Set<pid_t> = []
    var sent: [MediaPause.Command] = []
    var accepts = true
    var time = ContinuousClock.now
    /// Runs on every wait, with the time already advanced: where a test makes
    /// the player go quiet, or a new recording start, mid-wait.
    var onSleep: () -> Void = {}

    func pause(settle: Duration = .milliseconds(3500)) -> MediaPause {
        MediaPause(playingApps: { self.playing },
                   send: { command in
                       self.sent.append(command)
                       guard self.accepts else { return false }
                       // What Spotify does, minus the 2.3 s: play brings it
                       // back. The quiet after a pause is up to each test.
                       return true
                   },
                   now: { self.time },
                   sleep: { duration in
                       self.time += duration
                       self.onSleep()
                   },
                   settle: settle,
                   poll: .milliseconds(50))
    }
}

@Suite("Pausing media while dictating")
@MainActor
struct MediaPauseTests {
    @Test("with nothing playing, no command goes out, so play never starts music from silence")
    func nothingPlaying() async {
        let media = FakeMedia()
        let pause = media.pause()
        #expect(pause.recordingStarted() == .nothingPlaying)
        #expect(await pause.recordingEnded() == .nothingToResume)
        #expect(media.sent.isEmpty, "expected no command, got \(media.sent)")
    }

    @Test("music playing is paused at the start and played again once it went quiet")
    func pausesAndResumes() async {
        let media = FakeMedia()
        media.playing = [501]
        let pause = media.pause()
        #expect(pause.recordingStarted() == .paused([501]))
        #expect(media.sent == [.pause])

        media.playing = []
        #expect(await pause.recordingEnded() == .resumed)
        #expect(media.sent == [.pause, .play])
    }

    @Test("a dictation shorter than the player's quiet waits for it, then plays")
    func shortDictationWaitsForTheQuiet() async {
        let media = FakeMedia()
        media.playing = [501]
        let pause = media.pause()
        let started = media.time
        _ = pause.recordingStarted()
        // Spotify, measured: the output stops ~2.3 s after the pause.
        media.onSleep = { if media.time - started >= .milliseconds(2300) { media.playing = [] } }

        #expect(await pause.recordingEnded() == .resumed)
        #expect(media.sent == [.pause, .play])
        #expect(media.time - started < .milliseconds(2400), "played as soon as it went quiet")
    }

    @Test("an app the pause did not reach, a call say, is never sent play")
    func callKeepsPlaying() async {
        let media = FakeMedia()
        media.playing = [777]
        let pause = media.pause()
        _ = pause.recordingStarted()

        #expect(await pause.recordingEnded() == .stillPlaying([777]))
        #expect(media.sent == [.pause], "expected only the pause, got \(media.sent)")
    }

    @Test("music beside a call is played again when the music goes quiet")
    func musicBesideACall() async {
        let media = FakeMedia()
        media.playing = [501, 777]
        let pause = media.pause()
        _ = pause.recordingStarted()
        media.playing = [777]

        #expect(await pause.recordingEnded() == .resumed)
        #expect(media.sent == [.pause, .play])
    }

    @Test("an app that starts playing during the recording is not what the pause waits on")
    func latecomerDoesNotCount() async {
        let media = FakeMedia()
        media.playing = [777]
        let pause = media.pause()
        _ = pause.recordingStarted()
        media.playing = [777, 900]

        #expect(await pause.recordingEnded() == .stillPlaying([777]))
        #expect(media.sent == [.pause])
    }

    @Test("a refused pause leaves nothing to resume")
    func pauseRefused() async {
        let media = FakeMedia()
        media.playing = [501]
        media.accepts = false
        let pause = media.pause()
        #expect(pause.recordingStarted() == .commandFailed)
        media.playing = []
        #expect(await pause.recordingEnded() == .nothingToResume)
        #expect(media.sent == [.pause], "expected no play after a failed pause, got \(media.sent)")
    }

    @Test("a refused play is reported, and the next recording starts clean")
    func playRefused() async {
        let media = FakeMedia()
        media.playing = [501]
        let pause = media.pause()
        _ = pause.recordingStarted()
        media.playing = []
        media.accepts = false
        #expect(await pause.recordingEnded() == .commandFailed)
        #expect(pause.recordingStarted() == .nothingPlaying)
    }

    @Test("a recording started during the wait keeps the music paused, and play goes out once")
    func newRecordingDuringTheWait() async {
        let media = FakeMedia()
        media.playing = [501]
        let pause = media.pause()
        _ = pause.recordingStarted()

        var second: MediaPause.Start?
        media.onSleep = {
            if second == nil { second = pause.recordingStarted() }
        }
        #expect(await pause.recordingEnded() == .superseded)
        #expect(second == .keptPaused)
        #expect(media.sent == [.pause], "the second recording must not pause again, nor the first play")

        media.onSleep = {}
        media.playing = []
        #expect(await pause.recordingEnded() == .resumed)
        #expect(media.sent == [.pause, .play])
    }

    @Test("a new install starts with the pause on")
    func newInstallStartsOn() {
        #expect(MediaPause.firstValue(stored: nil, ranBefore: false) == true)
    }

    @Test("an install that ran before the switch existed keeps the music playing")
    func earlierInstallStaysOff() {
        #expect(MediaPause.firstValue(stored: nil, ranBefore: true) == false)
    }

    @Test("a stored value is never overwritten, whichever it is and whatever the log says")
    func storedValueStays() {
        for stored in [true, false] {
            for ranBefore in [true, false] {
                #expect(MediaPause.firstValue(stored: stored, ranBefore: ranBefore) == nil,
                        "stored \(stored), ran before \(ranBefore): expected nothing to store")
            }
        }
    }

    @Test("the app wires the pause into start, release, every discard and the first launch")
    func appWiring() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/NeverType/main.swift"),
                                encoding: .utf8)
        // Start, release and `discardRecording`: the one function every
        // cancel path already goes through.
        #expect(source.components(separatedBy: "media.recordingStarted()").count - 1 == 1)
        #expect(source.components(separatedBy: "resumeMedia()").count - 1 == 3,
                "expected the definition plus release and discard")
        // The first value comes from what `startLog` saw before it truncated
        // the log. Read anywhere later, every launch looks like an old one.
        #expect(source.components(separatedBy: "MediaPause.firstValue(").count - 1 == 1)
        #expect(source.contains("let ranBefore = startLog()")
                    && source.contains("storeFirstPauseMedia(ranBefore: ranBefore)"),
                "the first value has to come from what startLog saw before truncating the log")
    }
}
