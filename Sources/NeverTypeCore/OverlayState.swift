import Foundation

/// The moments the overlay must distinguish through shape and motion.
///
/// This lives in Core because the pill's visibility rule reads it, and a rule
/// the test target cannot reach is a rule nothing holds in place
/// (`nucleo-testavel.md`). The geometry stays with the view, in
/// `RecordingOverlay.swift`. What is here is the meaning of each state.
public enum OverlayState: Equatable, Sendable, CaseIterable {
    case idle
    case recording
    case latched
    case transcribing

    /// What VoiceOver reads off the orb.
    public var accessibilityValue: String {
        switch self {
        case .idle:          "Ready"
        case .recording:     "Listening"
        case .latched:       "Hands-free recording"
        case .transcribing:  "Writing"
        }
    }
}

/// Whether the pill is on screen, and what the absence of the preference means.
///
/// Turning the preference off gives up two things. Both are what the pill is
/// for. It is the only way back into the menu once
/// a full-screen application hides the menu bar (`docs/pitfalls.md`, "In full
/// screen there is no menu bar"), and the idle pill is the only sign that an
/// accessory app with no Dock tile and no window is still alive: one that dies
/// changes nothing on screen. Whoever turns it off is trading those away on
/// purpose.
///
/// A third cost is not visible here and is not measured: an ordered-out panel
/// leaves the accessibility hierarchy, so with the preference off VoiceOver
/// does not move to the orb on its own and the "Writing, 40%" the pill
/// announces is out of reach unless the person navigates to it inside every
/// dictation.
public enum PillVisibility {

    /// Absent means on, so an install that never touched the preference keeps
    /// the behavior it always had. The shape is `TextInjector`'s
    /// `resolvedRestoreDelay`. The default lives in one function, where a test
    /// reaches it, and every reading site asks that function for it.
    public static func resolvedAlwaysVisible(_ stored: Bool?) -> Bool {
        stored ?? true
    }

    /// Only the idle pill is ever hidden.
    ///
    /// Recording, hands-free and transcribing reach the screen whatever the
    /// preference says. The first version left that to the call order in
    /// `main.swift`. `AudioRecorder` reports a write error and carries on
    /// capturing, and the app's error handler answers it with `hide()`: the
    /// pill went off screen with the microphone still open, and the
    /// transcription that followed drew on a panel nobody could see.
    public static func isVisible(state: OverlayState, alwaysVisible: Bool) -> Bool {
        state == .idle ? alwaysVisible : true
    }
}
