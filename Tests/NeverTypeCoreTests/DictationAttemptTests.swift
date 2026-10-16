import Testing
@testable import NeverTypeCore

@Suite("Dictation attempt prerequisites")
struct DictationAttemptTests {
    /// Regression: global modifier monitoring can still deliver the trigger while
    /// Accessibility is off. Starting the recorder in that state spends the whole
    /// dictation and transcription before the final ⌘V silently goes nowhere.
    @Test("missing Accessibility returns a warning decision that cannot start recording")
    func accessibilityMissingBlocksBeforeRecording() {
        let decision = DictationAttempt.decide(
            microphone: .authorized,
            accessibilityAuthorized: false)

        #expect(decision == .showAccessibilityWarning)
        #expect(!decision.startsRecording)
    }

    /// Regression, 2026-10-15: a person installed through an agent, macOS showed
    /// the Accessibility prompt and never the microphone one, and from then on
    /// the trigger did nothing and nothing said why. A microphone nobody has
    /// answered for yet is a question still open, so the trigger asks it again;
    /// the system prompt is the only place it can be answered.
    @Test("a microphone never answered asks again, and does not start recording")
    func undeterminedMicrophoneAsksAgain() {
        let decision = DictationAttempt.decide(
            microphone: .notDetermined,
            accessibilityAuthorized: true)

        #expect(decision == .requestMicrophoneAccess,
                "expected the system prompt again, got \(decision)")
        #expect(!decision.startsRecording)
    }

    /// Denied or restricted, macOS no longer shows its prompt: asking again is a
    /// call that returns at once and changes nothing. The way out is the
    /// Settings page, so the trigger shows the warning that opens it.
    @Test("a denied or restricted microphone shows the warning with the way to Settings",
          arguments: [MicrophoneAccess.denied, .restricted])
    func refusedMicrophoneWarns(access: MicrophoneAccess) {
        let decision = DictationAttempt.decide(
            microphone: access,
            accessibilityAuthorized: true)

        #expect(decision == .showMicrophoneWarning,
                "\(access): expected the warning, got \(decision)")
        #expect(!decision.startsRecording)
    }

    @Test("both permissions in place start the recording")
    func everythingGrantedRecords() {
        let decision = DictationAttempt.decide(
            microphone: .authorized,
            accessibilityAuthorized: true)

        #expect(decision == .startRecording)
    }

    /// Accessibility keeps its place in front: without it the paste cannot
    /// land, and that holds whatever the microphone says.
    @Test("missing Accessibility comes first, whatever the microphone says",
          arguments: [MicrophoneAccess.notDetermined, .denied, .restricted])
    func accessibilityBeforeMicrophone(access: MicrophoneAccess) {
        let decision = DictationAttempt.decide(
            microphone: access,
            accessibilityAuthorized: false)

        #expect(decision == .showAccessibilityWarning)
    }

    @Test("a transcription in progress waits, before any permission is asked")
    func transcriptionWaitsFirst() {
        let decision = DictationAttempt.decide(
            microphone: .notDetermined,
            accessibilityAuthorized: false,
            isTranscribing: true)

        #expect(decision == .waitForTranscription)
    }

    @Test("a visible warning rejects reentrant presentation until it ends")
    func warningPresentationRejectsReentry() {
        var gate = PresentationGate()

        let first = gate.begin()
        let reentrant = gate.begin()
        gate.end()
        let afterEnding = gate.begin()

        #expect(first)
        #expect(!reentrant)
        #expect(afterEnding)
    }
}
