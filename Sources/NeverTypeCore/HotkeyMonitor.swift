import AppKit

/// Watches a global modifier key: press starts, release finishes.
///
/// Uses a pure modifier on purpose. Holding right ⌘ alone types no character and
/// triggers no system action, so there is no need to *swallow* the event — just
/// listen. That spares an intercepting CGEventTap, which is more code and can
/// freeze input for the whole system if something goes wrong.
/// Lives on the main actor. `NSEvent` monitors are AppKit API tied to the main
/// run loop, and the type now says so instead of leaving it implicit.
@MainActor
public final class HotkeyMonitor {
    public enum Event {
        case pressed
        case released
        /// A regular key was pressed during the hold. Without this, a normal ⌘V
        /// done with the right hand would become a phantom dictation.
        case cancelled
        /// Double tap: the recording continues without the key held.
        case latched
    }

    /// The trigger rule, separated from `NSEvent`.
    ///
    /// Pure on purpose: a 31-second dictation showed up in the usage log, and
    /// holding the key that whole time is the nuisance hands-free mode solves.
    /// All the "was this a tap or a hold?" logic lives here, so every path is
    /// exercisable without a keyboard — including the ones that only happen at
    /// specific milliseconds.
    public struct Latch {
        /// A hold shorter than this is a tap, not a dictation.
        ///
        /// The price: a short tap has its conclusion delayed by up to `tapWindow`,
        /// waiting to see whether the second one comes. Only affects holds under
        /// 250 ms, which have no usable audio anyway — normal dictation pays nothing.
        public static let tapThreshold: TimeInterval = 0.25
        /// Maximum interval between the two taps.
        public static let tapWindow: TimeInterval = 0.30

        public enum Input {
            case down(TimeInterval)
            case up(TimeInterval)
            /// Regular key, which during the hold means "this was a shortcut".
            case otherKey
            case escape
            case timeout
        }

        public enum Action: Equatable {
            case start
            case finish
            case cancel
            case latch
            case armTimeout(TimeInterval)
            case disarmTimeout
        }

        enum State: Equatable {
            case idle
            case holding(since: TimeInterval)
            /// Already released a short tap; the recording continues while
            /// waiting for the second tap.
            case awaitingSecondTap
            /// Hands-free: records without the key held.
            case latched
        }

        private(set) var state: State = .idle

        public init() {}

        public var isLatched: Bool { state == .latched }

        public mutating func handle(_ input: Input) -> [Action] {
            switch (state, input) {

            case (.idle, .down(let t)):
                state = .holding(since: t)
                return [.start]

            case (.holding(let since), .up(let t)):
                guard t - since < Self.tapThreshold else {
                    state = .idle
                    return [.finish]
                }
                state = .awaitingSecondTap
                return [.armTimeout(Self.tapWindow)]

            case (.holding, .otherKey), (.holding, .escape):
                state = .idle
                return [.cancel]

            // Second tap inside the window: lock.
            case (.awaitingSecondTap, .down):
                state = .latched
                return [.disarmTimeout, .latch]

            // The window passed: it really was just a short tap.
            case (.awaitingSecondTap, .timeout):
                state = .idle
                return [.finish]

            case (.awaitingSecondTap, .otherKey), (.awaitingSecondTap, .escape):
                state = .idle
                return [.disarmTimeout, .cancel]

            // Locked, one tap finishes. The following `up` lands in `.idle` and
            // is ignored there.
            case (.latched, .down):
                state = .idle
                return [.finish]

            case (.latched, .escape):
                state = .idle
                return [.cancel]

            // Locked, a regular key does NOT cancel.
            //
            // While holding the key, a regular key means "this was a shortcut,
            // not a dictation". In hands-free there is no modifier held, so
            // typing is just typing — and cancelling a long dictation because of
            // that would lose precisely what the mode exists to allow.
            case (.latched, .otherKey):
                return []

            default:
                return []
            }
        }
    }

    /// Right ⌘. The keyCode identifies the key; the mask identifies the *side*,
    /// since `.command` is set with either of the two ⌘.
    public struct Trigger: Sendable {
        public let keyCode: UInt16
        public let deviceMask: UInt
        public let label: String

        public static let rightCommand = Trigger(keyCode: 54, deviceMask: 0x0010, label: "Right ⌘")
        public static let rightOption  = Trigger(keyCode: 61, deviceMask: 0x0040, label: "Right ⌥")
        public static let rightControl = Trigger(keyCode: 62, deviceMask: 0x2000, label: "Right ⌃")

        /// The options offered in the menu.
        ///
        /// Only pure right-side modifiers. A modifier alone types no character
        /// and triggers no system action, which is what spares the intercepting
        /// `CGEventTap` — and the right side is what the hand that is not on the
        /// mouse reaches without leaving its position.
        public static let all: [Trigger] = [rightCommand, rightOption, rightControl]

        /// Identifier for saving the choice. The keyCode is stable across macOS
        /// versions; the label is not, because it is interface text.
        public var id: String { String(keyCode) }

        public static func named(_ id: String?) -> Trigger? {
            guard let id else { return nil }
            return all.first { $0.id == id }
        }

        public init(keyCode: UInt16, deviceMask: UInt, label: String) {
            self.keyCode = keyCode
            self.deviceMask = deviceMask
            self.label = label
        }
    }

    /// Switchable in use: the choice lives in the menu.
    ///
    /// No need to reinstall the monitors — they listen to `.flagsChanged` from
    /// any key, and the keyCode filter happens on read. What does need resetting
    /// is the state machine: switching keys in the middle of a hold would leave
    /// an orphan recording, with no key to finish it.
    public var trigger: Trigger {
        didSet {
            guard trigger.keyCode != oldValue.keyCode else { return }
            tapTimer?.invalidate()
            tapTimer = nil
            latch = Latch()
        }
    }
    public var onEvent: (@MainActor (Event) -> Void)?

    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var latch = Latch()
    private var tapTimer: Timer?

    /// True while the recording continues without the key held.
    public var isLatched: Bool { latch.isLatched }

    public init(trigger: Trigger = .rightCommand) {
        self.trigger = trigger
    }

    /// The Accessibility grant. Without it the global monitors simply receive no
    /// events — and do not say so. The app would look broken in silence.
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        // The kAXTrustedCheckOptionPrompt constant is a global `var` in
        // ApplicationServices, which Swift 6 rejects for concurrency. The value
        // is stable and documented, so we use the string directly.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        // `assumeIsolated`, and not `Task { @MainActor in }`, on purpose.
        //
        // AppKit delivers these events on the main thread — the monitors are
        // installed on the main run loop. And here order matters more than
        // purity: an asynchronous hop could process the `keyDown` after the
        // release, turning a valid dictation into a cancellation. The synchronous
        // call preserves arrival order.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            globalMonitors.append(m)
        }

        // The global monitor does not fire when the app itself is in focus. Since
        // NeverType is accessory and almost never is, this is a seat belt — but
        // without it the trigger would die with the tray menu open.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    public func stop() {
        for m in globalMonitors { NSEvent.removeMonitor(m) }
        globalMonitors.removeAll()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        tapTimer?.invalidate()
        tapTimer = nil
        latch = Latch()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard event.keyCode == trigger.keyCode else { return }
            let down = (event.modifierFlags.rawValue & trigger.deviceMask) != 0
            apply(latch.handle(down ? .down(event.timestamp) : .up(event.timestamp)))
        case .keyDown:
            // 53 is Escape. In hands-free it is the only way out without transcribing.
            apply(latch.handle(event.keyCode == 53 ? .escape : .otherKey))
        default:
            break
        }
    }

    private func apply(_ actions: [Latch.Action]) {
        for action in actions {
            switch action {
            case .start:  onEvent?(.pressed)
            case .finish: onEvent?(.released)
            case .cancel: onEvent?(.cancelled)
            case .latch:  onEvent?(.latched)
            case .armTimeout(let after):
                tapTimer?.invalidate()
                // `assumeIsolated` is the legitimate case: the Timer is scheduled
                // on the main run loop by this method, which is already `@MainActor`.
                tapTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.apply(self.latch.handle(.timeout))
                    }
                }
            case .disarmTimeout:
                tapTimer?.invalidate()
                tapTimer = nil
            }
        }
    }

    // No `deinit { stop() }`: `deinit` is nonisolated and cannot touch main-actor
    // state. Whoever creates the monitor calls `stop()`.
}
