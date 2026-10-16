import Foundation

/// The two permissions as macOS reports them at one moment.
///
/// A value, read and thrown away: what the app decides from it is decided on
/// the spot, and the next decision reads again
/// (`.vibeflow/patterns/estado-consultado.md`).
public struct PermissionReading: Equatable, Sendable {
    public var microphone: MicrophoneAccess
    public var accessibilityGranted: Bool

    public init(microphone: MicrophoneAccess, accessibilityGranted: Bool) {
        self.microphone = microphone
        self.accessibilityGranted = accessibilityGranted
    }

    /// Nothing missing: the app can record and insert.
    public var isComplete: Bool { microphone == .authorized && accessibilityGranted }

    /// Both read from the system now.
    @MainActor
    public static var current: PermissionReading {
        PermissionReading(microphone: .current,
                          accessibilityGranted: HotkeyMonitor.hasAccessibilityPermission)
    }
}

/// How the model load ended, as far as the icon is concerned.
///
/// Loading draws no slash: that is how launch has always looked, and a
/// dictation in the meantime says what it needs on its own.
public enum ModelState: Equatable, Sendable {
    case loading
    case ready
    case notLoaded
    case noMetal
}

/// The menu bar icon at rest, when nothing is recording.
///
/// The slash had several causes and no single place that knew them, so each
/// path drew what it saw: asking again for the microphone drew the normal
/// icon with the model failed to load (audit L6 of part 1), and nothing at
/// all redrew it when a permission was granted in System Settings
/// (2026-10-16 08:28: slashed with both granted, until the first trigger).
/// The rule is here so a permission granted clears only its own slash.
public enum StatusIcon: Equatable, Sendable {
    case normal
    case slashed

    public static func resting(permissions: PermissionReading, model: ModelState) -> StatusIcon {
        guard permissions.isComplete else { return .slashed }
        switch model {
        case .loading, .ready: return .normal
        case .notLoaded, .noMetal: return .slashed
        }
    }
}

/// Reads both permissions again while one is missing, and says when the
/// reading changes.
///
/// macOS tells the app nothing when a permission is turned on in System
/// Settings, so the icon stayed slashed with both granted until a key press
/// redrew it (2026-10-16 08:28). Nothing missing, nothing to watch: it does
/// not start, and it stops on the reading that has both granted, after
/// handing that reading over.
///
/// What it keeps is the last reading it handed over, to tell a change from a
/// repeat. It never decides anything from it; the caller decides from the
/// reading it is handed, read from the system at that moment.
///
/// The reading and the interval come in as parameters, so a test advances the
/// re-reads one by one with no clock (`.vibeflow/patterns/nucleo-testavel.md`).
@MainActor
public final class PermissionWatch {
    private let read: @MainActor () -> PermissionReading
    private let interval: @MainActor () async -> Void
    private let onChange: @MainActor (PermissionReading) -> Void
    private var loop: Task<Void, Never>?

    public var isRunning: Bool { loop != nil }

    public init(read: @escaping @MainActor () -> PermissionReading,
                interval: @escaping @MainActor () async -> Void = PermissionWatch.oneSecond,
                onChange: @escaping @MainActor (PermissionReading) -> Void) {
        self.read = read
        self.interval = interval
        self.onChange = onChange
    }

    /// Starts watching when a permission is missing. Already watching, or
    /// nothing missing, it does nothing, so every place that finds a
    /// permission missing can call it.
    public func start() {
        guard loop == nil else { return }
        var last = read()
        guard !last.isComplete else { return }
        loop = Task { @MainActor [weak self] in
            while true {
                guard let interval = self?.interval else { return }
                await interval()
                guard let self, !Task.isCancelled else { return }
                let now = self.read()
                if now != last {
                    last = now
                    self.onChange(now)
                }
                if now.isComplete {
                    self.loop = nil
                    return
                }
            }
        }
    }

    /// Long enough to cost nothing, short enough that the slash goes away
    /// about when the switch in System Settings is turned on.
    public static let oneSecond: @MainActor () async -> Void = {
        try? await Task.sleep(for: .seconds(1))
    }
}
