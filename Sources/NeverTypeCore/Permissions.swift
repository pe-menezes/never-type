import AVFoundation

/// The four answers macOS gives about the microphone, kept apart.
///
/// A single "authorized or not" hid the difference that decides what to do
/// next. Not determined means nobody answered the prompt yet, so asking again
/// shows it. Denied or restricted means the prompt will not come back, and the
/// only way out is the Microphone page in System Settings. On 2026-10-15 a
/// person got the Accessibility prompt and never the microphone one, and the
/// trigger stayed silent from then on because both cases looked the same.
///
/// The raw values are the words of the `permissions:` log line, which
/// `scripts/verify-install.sh` reads.
public enum MicrophoneAccess: String, Equatable, Sendable, CaseIterable {
    case authorized
    case notDetermined
    case denied
    case restricted

    public init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        // A status this build does not know cannot record either, and the
        // Settings page is still the only place a person can act on it.
        @unknown default: self = .denied
        }
    }

    /// Queried from the system on every read, never kept: the person changes it
    /// in System Settings without the app hearing about it
    /// (`.vibeflow/patterns/estado-consultado.md`).
    public static var current: MicrophoneAccess {
        MicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio))
    }
}

/// The order of the two permission prompts at launch.
///
/// The app used to start the microphone request without waiting for it and ask
/// for Accessibility on the very next line. Accessibility opens System Settings
/// on top of everything, and on 2026-10-15 a person installing through an agent
/// saw that one and never saw the microphone prompt. Now the microphone answer
/// comes first, and Accessibility is only looked at after it.
///
/// The system calls come in as parameters so a test can hold the microphone
/// prompt open and check that nothing else happens meanwhile
/// (`.vibeflow/patterns/nucleo-testavel.md`).
public enum LaunchPermissions {
    @MainActor
    public static func run(microphone: () -> MicrophoneAccess,
                           accessibilityGranted: () -> Bool,
                           requestMicrophone: () async -> Void,
                           requestAccessibility: () -> Void) async {
        // Already answered, either way, the prompt would not show: asking again
        // returns at once and only delays Accessibility.
        if microphone() == .notDetermined {
            await requestMicrophone()
        }
        if !accessibilityGranted() {
            requestAccessibility()
        }
    }
}

/// The `permissions:` line of `nevertype.log`, and when to write it.
///
/// The log said nothing about the microphone, so a person whose trigger did
/// nothing had no line to read and no way to tell which permission was
/// missing. The line is written at launch and whenever a reading differs from
/// the last line written.
///
/// What this type keeps is the last line it wrote, so the log does not repeat
/// itself on every key press. It is never consulted to decide anything about
/// a permission: every reading passed in comes from the system at that moment.
public struct PermissionLog: Sendable {
    private var lastWritten: String?

    public init() {}

    /// The format `scripts/verify-install.sh` parses. Change both together.
    public static func line(microphone: MicrophoneAccess, accessibilityGranted: Bool) -> String {
        "permissions: microphone=\(microphone.rawValue) accessibility=\(accessibilityGranted ? "granted" : "missing")"
    }

    /// The line to write for this reading, or nil when it is the one already
    /// written.
    public mutating func lineIfChanged(microphone: MicrophoneAccess,
                                       accessibilityGranted: Bool) -> String? {
        let line = Self.line(microphone: microphone, accessibilityGranted: accessibilityGranted)
        guard line != lastWritten else { return nil }
        lastWritten = line
        return line
    }
}
