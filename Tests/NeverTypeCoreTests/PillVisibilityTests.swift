import Foundation
import Testing
@testable import NeverTypeCore

/// Whether the pill is on screen, in every state and both settings, plus what
/// the absence of the preference means.
@Suite("Pill visibility")
struct PillVisibilityTests {

    @Test("with the preference on, every state is on screen")
    func alwaysVisible() {
        for state in OverlayState.allCases {
            #expect(PillVisibility.isVisible(state: state, alwaysVisible: true),
                    "\(state) went missing with the preference on")
        }
    }

    @Test("with the preference off, only the idle pill goes away")
    func onlyIdleHides() {
        #expect(!PillVisibility.isVisible(state: .idle, alwaysVisible: false))
        // The three that matter. `AudioRecorder` reports a write error without
        // stopping the capture, and the app's error handler asks the overlay to
        // go back to idle: if that answer were "hidden" for anything but idle,
        // the microphone would be open with nothing on screen saying so.
        #expect(PillVisibility.isVisible(state: .recording, alwaysVisible: false))
        #expect(PillVisibility.isVisible(state: .latched, alwaysVisible: false))
        #expect(PillVisibility.isVisible(state: .transcribing, alwaysVisible: false))
    }

    @Test("a preference nobody set is on, so an old install keeps its pill")
    func absentMeansOn() {
        #expect(PillVisibility.resolvedAlwaysVisible(nil))
        #expect(PillVisibility.resolvedAlwaysVisible(true))
        #expect(!PillVisibility.resolvedAlwaysVisible(false))
    }

    @Test("every state says what it is to VoiceOver, and no two say the same")
    func accessibilityValues() {
        let spoken = OverlayState.allCases.map(\.accessibilityValue)
        #expect(spoken.allSatisfy { !$0.isEmpty })
        #expect(Set(spoken).count == OverlayState.allCases.count)
    }
}

/// The overlay lives in the executable target, which a test cannot import, so
/// what a test sees of it is the text of its source. Same shape as
/// `ProgressWiringTests`: the rule sits in Core with real tests above, and this
/// keeps the panel wired to it.
@Suite("The pill is wired to the rule")
struct PillVisibilityWiringTests {

    private static func source(of path: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    /// The count is what matters. The first version of this feature ordered
    /// the panel from `showIdle()`, `show()` and `hide()` as well, and each of
    /// those sites was a way for a state to reach the screen without asking the
    /// rule. Putting one back would leave every test above green.
    @Test("the panel is ordered in exactly one place, and that place asks the rule")
    func orderingGoesThroughTheRule() {
        let overlay = Self.source(of: "Sources/NeverType/RecordingOverlay.swift")
        #expect(!overlay.isEmpty, "could not read RecordingOverlay.swift")

        #expect(overlay.contains("PillVisibility.isVisible(state:"),
                "the panel no longer asks the rule whether it should be on screen")
        #expect(overlay.contains("PillVisibility.resolvedAlwaysVisible("),
                "the reading site has to ask the rule for the default")

        #expect(overlay.components(separatedBy: "orderFrontRegardless()").count - 1 == 1,
                "ordering the panel front belongs in apply(_:) and nowhere else")
        #expect(overlay.components(separatedBy: "orderOut(").count - 1 == 1,
                "ordering the panel out belongs in apply(_:) and nowhere else")
    }

    /// The pill that comes back has to come back somewhere a person can reach.
    @Test("before it is ordered front, a frame on no screen is moved back")
    func offScreenFrameIsRecovered() {
        let overlay = Self.source(of: "Sources/NeverType/RecordingOverlay.swift")
        #expect(overlay.contains("NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) })"),
                "an ordered-out panel keeps a frame its display may no longer have")
        #expect(overlay.contains("panel.setFrameOrigin(restoredOrigin(for: panel.frame.size))"),
                "the recovery must reuse the corner restoredOrigin already picks")
    }
}
