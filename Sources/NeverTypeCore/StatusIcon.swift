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

    /// How a finished load ends. Metal only counts once the model loaded:
    /// a missing model used to log "no Metal" as well, which sent whoever was
    /// debugging the wrong way. The branches lived in the app, where audit A1
    /// of part 1b swapped `.ready` and `.noMetal` and no test noticed.
    public init(loaded: Bool, metalActive: Bool) {
        if !loaded {
            self = .notLoaded
        } else if metalActive {
            self = .ready
        } else {
            self = .noMetal
        }
    }

    /// How the load ended, from the app's own reads.
    ///
    /// The reads come in as calls, so Metal is asked only once the model
    /// loaded. With the condition in the app, `if loaded {` turned into
    /// `if !loaded {` left the icon slashed on every working Mac, and the
    /// suite stayed green (audit A2 of part 1b).
    @MainActor
    public static func afterLoad(loaded: () async -> Bool,
                                 devices: () async -> String,
                                 metalActive: () async -> Bool,
                                 log: (String) -> Void) async -> ModelState {
        // A missing model used to log "no Metal" as well, which sent whoever
        // was debugging the wrong way.
        guard await loaded() else { return .notLoaded }
        let list = await devices()
        log("ggml devices: \(list)")
        let metal = await metalActive()
        if !metal {
            log("WARNING: without Metal, transcription runs on the CPU and is ~11x slower.")
        }
        return ModelState(loaded: true, metalActive: metal)
    }
}

/// What the app draws in the menu bar: the brand, the live waveform, or the
/// slashed brand.
public enum StatusVisual: Equatable, Sendable {
    case idle
    case recording
    case blocked
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

    /// The icon at rest as the app draws it.
    public var visual: StatusVisual {
        switch self {
        case .normal: return .idle
        case .slashed: return .blocked
        }
    }

    /// What to draw at rest with this reading, or nothing while a dictation
    /// is on. While recording the icon is the waveform, and the release draws
    /// the normal icon, without this rule (audit B3 of part 1b). While
    /// transcribing, nothing redraws when the transcription succeeds, so a
    /// reading that arrives then waits for the next redraw (audit B7).
    ///
    /// In the app, an early return or an inverted guard here brought back the
    /// slash of 2026-10-16 08:28 with every test green (audit A1 of part 1b).
    public static func redraw(permissions: PermissionReading, recording: Bool, transcribing: Bool,
                              model: ModelState) -> StatusVisual? {
        guard !recording, !transcribing else { return nil }
        return resting(permissions: permissions, model: model).visual
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
