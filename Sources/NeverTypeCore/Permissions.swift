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

/// Whether this process has a microphone request open, and what a trigger
/// does about it.
///
/// Audit D1, 2026-10-15: with the launch prompt still open, a trigger asked
/// again, the second request joined the first and nothing new showed; and when
/// the prompt never appeared at all, every trigger was the slashed icon and
/// nothing else, which is the case this front started from. Now a trigger that
/// finds a request open says so at once, and one that asks again says so when
/// the wait ends with no answer.
///
/// What it keeps is about this process, never about the system: a request it
/// started and that has not returned. The permission itself is still read from
/// macOS every time (`.vibeflow/patterns/estado-consultado.md`).
///
/// The request and the wait come in as parameters, so a test holds the prompt
/// open and ends the wait itself, with no clock
/// (`.vibeflow/patterns/nucleo-testavel.md`).
@MainActor
public final class MicrophoneRequest {
    public private(set) var isPending = false

    public init() {}

    /// The launch request: marked as in flight while it runs, with no limit.
    /// A limit here would bring the two prompts back together for whoever
    /// takes a while to read the first one (audit L5).
    public func ask(_ request: () async -> Void) async {
        isPending = true
        defer { isPending = false }
        await request()
    }

    /// A trigger, or the menu item, with the microphone never answered.
    ///
    /// With a request already in flight, `onNoAnswer` runs at once and nothing
    /// is asked. Otherwise the request starts, and if it has not returned when
    /// `wait` does, `onNoAnswer` runs, once. An answer first shows nothing.
    /// Returns when the request returns.
    public func askAgain(request: @escaping @MainActor () async -> Void,
                         wait: @escaping @MainActor () async -> Void = MicrophoneRequest.tenSeconds,
                         onNoAnswer: @escaping @MainActor () -> Void) async {
        guard !isPending else {
            onNoAnswer()
            return
        }
        isPending = true
        let timer = Task { @MainActor [weak self] in
            await wait()
            guard !Task.isCancelled, let self, self.isPending else { return }
            onNoAnswer()
        }
        await request()
        isPending = false
        timer.cancel()
    }

    /// Long enough for a prompt that is on screen to be read and clicked,
    /// short enough that a trigger with nothing showing does not look dead.
    public static let tenSeconds: @MainActor () async -> Void = {
        try? await Task.sleep(for: .seconds(10))
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
