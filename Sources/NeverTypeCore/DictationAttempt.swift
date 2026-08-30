/// Decides whether a trigger may start a dictation.
///
/// This is deliberately evaluated on every key press. Both permissions can be
/// changed in System Settings while the app is running, and a value captured at
/// launch would go stale. In particular, macOS may still deliver the modifier
/// event while Accessibility is off; what fails later is the synthetic paste.
public enum DictationAttempt: Equatable, Sendable {
    case startRecording
    case showMicrophoneWarning
    case showAccessibilityWarning

    public static func decide(
        microphoneAuthorized: Bool,
        accessibilityAuthorized: Bool
    ) -> Self {
        guard accessibilityAuthorized else { return .showAccessibilityWarning }
        guard microphoneAuthorized else { return .showMicrophoneWarning }
        return .startRecording
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
