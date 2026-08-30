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
            microphoneAuthorized: true,
            accessibilityAuthorized: false)

        #expect(decision == .showAccessibilityWarning)
        #expect(!decision.startsRecording)
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
