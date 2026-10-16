/// Decides whether a trigger may start a dictation.
///
/// This is deliberately evaluated on every key press. Both permissions can be
/// changed in System Settings while the app is running, and a value captured at
/// launch would go stale. In particular, macOS may still deliver the modifier
/// event while Accessibility is off; what fails later is the synthetic paste.
public enum DictationAttempt: Equatable, Sendable {
    case startRecording
    /// Nobody answered the microphone prompt yet, so the trigger shows it
    /// again. On 2026-10-15 it never appeared at launch for one person, and
    /// the trigger stayed silent with nothing saying why.
    case requestMicrophoneAccess
    /// Denied or restricted: macOS will not show the prompt again, so the way
    /// out is the warning that opens the Microphone page in System Settings.
    case showMicrophoneWarning
    case showAccessibilityWarning
    case waitForTranscription

    public static func decide(
        microphone: MicrophoneAccess,
        accessibilityAuthorized: Bool,
        isTranscribing: Bool = false
    ) -> Self {
        guard !isTranscribing else { return .waitForTranscription }
        guard accessibilityAuthorized else { return .showAccessibilityWarning }
        switch microphone {
        case .authorized: return .startRecording
        case .notDetermined: return .requestMicrophoneAccess
        case .denied, .restricted: return .showMicrophoneWarning
        }
    }

    public var startsRecording: Bool { self == .startRecording }
}

/// Rejects recursive presentation while an AppKit modal loop is already active.
///
/// `NSAlert.runModal()` continues pumping events. Without an explicit gate, a
/// second hotkey press can enter the same alert method and stack another modal
/// session before the first one returns.
public struct PresentationGate: Sendable {
    private var isPresenting = false

    public init() {}

    public mutating func begin() -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        return true
    }

    public mutating func end() {
        isPresenting = false
    }
}
