import Foundation
import Testing
@testable import NeverTypeCore

@Suite("Transcription progress")
struct TranscriptionProgressTests {

    @Test("starts empty and says nothing")
    func startsEmpty() {
        let progress = TranscriptionProgress()
        #expect(progress.fraction == 0)
        #expect(progress.spoken == nil, "before the first update there is nothing to report")
    }

    @Test("climbs with whisper's own scale")
    func climbs() {
        var progress = TranscriptionProgress()
        let first = progress.advance(percent: 40)
        #expect(first)
        #expect(progress.fraction == 0.4)
        let second = progress.advance(percent: 55)
        #expect(second)
        #expect(progress.fraction == 0.55)
    }

    /// The defect this type exists for. The updates reach the main actor through
    /// independent unstructured tasks, which carry no order between them, so the
    /// view can be handed a lower number after a higher one.
    @Test("a number that arrives out of order does not walk the ring back")
    func refusesToGoBackwards() {
        var progress = TranscriptionProgress()
        progress.advance(percent: 50)
        let stale = progress.advance(percent: 40)
        #expect(stale == false, "a stale update must not move anything")
        #expect(progress.fraction == 0.5)
    }

    @Test("the same number twice does not ask for a redraw")
    func repeatedValueIsNotMovement() {
        var progress = TranscriptionProgress()
        progress.advance(percent: 30)
        let again = progress.advance(percent: 30)
        #expect(again == false,
                "whisper reports the same number more than once on a long transcription")
    }

    @Test("stays inside 0 and 1")
    func clampsOutOfRange() {
        var progress = TranscriptionProgress()
        progress.advance(percent: 400)
        #expect(progress.fraction == 1)
        var other = TranscriptionProgress()
        let negative = other.advance(percent: -20)
        #expect(negative == false)
        #expect(other.fraction == 0)
    }

    /// Lifetime, the second half of the rule: a late update from the previous
    /// dictation must not open the next one's ring part filled.
    @Test("reset clears it, and a late update after the reset is refused only if lower")
    func resetClears() {
        var progress = TranscriptionProgress()
        progress.advance(percent: 80)
        let cleared = progress.reset()
        #expect(cleared)
        #expect(progress.fraction == 0)
        let again = progress.reset()
        #expect(again == false, "resetting an empty one changes nothing")
    }

    @Test("what the screen reader hears is the number on the ring")
    func spokenMatchesTheRing() {
        var progress = TranscriptionProgress()
        progress.advance(percent: 42)
        #expect(progress.spoken == "42%")
        progress.advance(percent: 100)
        #expect(progress.spoken == "100%")
    }
}

/// The overlay lives in the executable target, which a test cannot import, so
/// what a test sees of it is the text of its source. Same shape as
/// `FocusHandbackTests`: the behavior rule sits in Core with real tests above,
/// and this keeps the ring wired to it.
@Suite("The ring is wired to the rule")
struct ProgressWiringTests {

    private static func source(of path: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    /// The call site, not the name. The file names `TranscriptionProgress` in
    /// prose too, so looking for the word alone would stay green with the wiring
    /// pulled out, which is the mistake `FocusHandbackTests` already recorded.
    @Test("the overlay advances the ring through TranscriptionProgress, and cannot set it")
    func ringGoesThroughTheRule() {
        let overlay = Self.source(of: "Sources/NeverType/RecordingOverlay.swift")
        #expect(!overlay.isEmpty, "could not read RecordingOverlay.swift")
        #expect(overlay.contains("progress.advance(percent:"),
                "the ring is no longer advanced through TranscriptionProgress")
        #expect(overlay.contains("progress.reset()"),
                "entering a state must clear the ring, or a late update opens the next one part filled")
        #expect(!overlay.contains("pill?.progress ="),
                "assigning the fraction straight into the view is what let it run backwards")
    }
}
