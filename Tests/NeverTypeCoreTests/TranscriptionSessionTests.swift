import Foundation
import Testing
@testable import NeverTypeCore

@Suite("Transcription session lifetime")
struct TranscriptionSessionTests {
    @Test("a second trigger waits until the pending result is delivered")
    func waitsForDelivery() throws {
        var session = TranscriptionSession()
        let started = session.begin()
        let first = try #require(started)
        let decision = DictationAttempt.decide(
            microphoneAuthorized: true, accessibilityAuthorized: true,
            isTranscribing: session.isTranscribing)
        #expect(decision == .waitForTranscription)
        #expect(!decision.startsRecording)
        let overlapping = session.begin()
        #expect(overlapping == nil, "a second inference cannot replace the first")
        #expect(session.accepts(first), "the progress ring still belongs to the pending inference")

        let finished = session.finish(first)
        #expect(finished)
        #expect(DictationAttempt.decide(
            microphoneAuthorized: true, accessibilityAuthorized: true,
            isTranscribing: session.isTranscribing).startsRecording)
    }

    @Test("late progress and duplicate completion cannot affect the next dictation")
    func ignoresLateCallbacks() throws {
        var session = TranscriptionSession()
        let started = session.begin()
        let first = try #require(started)
        session.finish(first)
        #expect(!session.accepts(first), "the finished ring must not receive late progress")

        let restarted = session.begin()
        let second = try #require(restarted)
        #expect(!session.accepts(first), "old progress cannot fill the new ring")
        let staleCompletion = session.finish(first)
        #expect(!staleCompletion, "old completion cannot end the new inference")
        #expect(session.accepts(second))
        #expect(session.isTranscribing)
        let finished = session.finish(second)
        #expect(finished)
        #expect(!session.isTranscribing)
    }

    @Test("the app guards recording, progress and completion with the session")
    func appUsesSession() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/NeverType/main.swift"),
                                encoding: .utf8)
        #expect(source.contains("isTranscribing: transcriptionSession.isTranscribing"))
        #expect(source.contains("guard let session = transcriptionSession.begin()"))
        #expect(source.contains("guard self.transcriptionSession.accepts(session) else { return }"))
        #expect(source.contains("guard self.transcriptionSession.finish(session) else { return }"))
    }
}
