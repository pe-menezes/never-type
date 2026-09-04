import AppKit

/// Watches a global modifier key, or an extra mouse button: press starts,
/// release finishes.
///
/// Uses a pure modifier on purpose. Holding right ⌘ alone types no character and
/// triggers no system action, so there is no need to *swallow* the event — just
/// listen. That spares an intercepting CGEventTap, which is more code and can
/// freeze input for the whole system if something goes wrong. A mouse button is
/// listened to the same way, and its click does reach the app in front.
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

        public enum Input: Equatable {
            case down(TimeInterval)
            case up(TimeInterval)
            /// Regular key, which during the hold means "this was a shortcut".
            case otherKey
            case escape
            case timeout
            /// The hands-free key went down. It asks; the release decides.
            case toggleDown
            /// The hands-free key came up with no regular key in between: lock,
            /// or finish if it was already locked.
            case toggleUp
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
            /// A toggle asked to start. `resolveStart` moves an accepted start
            /// on to `.armingLatch`, and a refused one back to idle. Transient:
            /// the app resolves the start in the same main-actor turn, so no
            /// other input ever lands here.
            case startingLatched
            /// Recording, with the hands-free key still down. Its release locks
            /// and a regular key cancels, the same rule the trigger's own hold
            /// has. Without this state the key locked on its press, and a
            /// shortcut that starts with it (⌃C with Left ⌃ chosen) opened a
            /// locked recording that no later key could cancel.
            case armingLatch
            /// Locked, with the hands-free key down again. Its release finishes,
            /// and a regular key puts the gesture back to `.latched`: the key
            /// was a shortcut, not the end of the dictation.
            case armingFinish
        }

        private(set) var state: State = .idle

        /// Whether the double tap locks at all.
        ///
        /// Off, `.awaitingSecondTap` is never entered: a short tap concludes on
        /// the release itself, so `(.awaitingSecondTap, .down)` has no state to
        /// fire from. The other way of writing it was to arm the window as usual
        /// and refuse the latch when the second tap arrived. That keeps a timer
        /// running for a gesture that cannot happen, and leaves a case in this
        /// table that no input can ever produce.
        ///
        /// It also gives the delay back: with hands-free on, a tap under 250 ms
        /// waits up to 300 ms to see whether the second one arrives.
        private let handsFree: Bool

        public init(handsFree: Bool = true) {
            self.handsFree = handsFree
        }

        /// Locked, the key held for the finishing tap included: the recording
        /// runs with no key holding it open either way.
        public var isLatched: Bool { state == .latched || state == .armingFinish }

        /// True while the gesture in flight is holding the hands-free key.
        ///
        /// What a change of that key abandons. A locked recording is not in
        /// this set: every way out of `.latched` is key-agnostic, so the lock
        /// survives a key that changes under it.
        public var isHoldingHandsFreeKey: Bool {
            state == .startingLatched || state == .armingLatch || state == .armingFinish
        }

        /// Resolves whether the app accepted the `.start` action, and returns
        /// what follows from that.
        ///
        /// A rejected start has already moved the state to `.holding`. Leaving it
        /// there lets the following release arm the hands-free double-tap path for
        /// a recording that never existed.
        ///
        /// A start asked by the hands-free key arms the lock only once it is
        /// accepted. Moving straight to a locked state from the toggle would
        /// make the app play the lock tone and show the locked pill over a
        /// recording that never began, on the day Accessibility, the microphone
        /// or the recorder refuse. The order "only lock what started" is a
        /// rule, so it lives here, in the pure type, where it has a test.
        public mutating func resolveStart(accepted: Bool) -> [Action] {
            guard accepted else {
                reset()
                return []
            }
            guard state == .startingLatched else { return [] }
            state = .armingLatch
            return []
        }

        /// Abandons a gesture whose `.start` action was refused by the app.
        /// The following key-up must land in idle, not arm the double-tap window.
        public mutating func reset() {
            state = .idle
        }

        public mutating func handle(_ input: Input) -> [Action] {
            // Off, the hands-free key is as dead as the double tap: a key that
            // locks with the mode off would contradict the line the submenu
            // shows then, "only records while held".
            if !handsFree, input == .toggleDown || input == .toggleUp { return [] }

            switch (state, input) {

            case (.idle, .down(let t)):
                state = .holding(since: t)
                return [.start]

            case (.holding(let since), .up(let t)):
                guard handsFree, t - since < Self.tapThreshold else {
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

            // The hands-free key, from rest: ask to start, and arm the lock
            // once the app says the recording began (see `resolveStart`).
            case (.idle, .toggleDown):
                state = .startingLatched
                return [.start]

            // The hands-free key while the trigger is held, or inside the
            // second-tap window: the recording is already running, so only the
            // lock is armed. No second tap needed.
            case (.holding, .toggleDown):
                state = .armingLatch
                return []

            case (.awaitingSecondTap, .toggleDown):
                state = .armingLatch
                return [.disarmTimeout]

            // The release is what locks, and only if nothing came in between.
            case (.armingLatch, .toggleUp):
                state = .latched
                return [.latch]

            // A regular key while the hands-free key is down means the two were
            // a shortcut, the same reading the trigger's own hold has. Without
            // this, ⌃C with Left ⌃ chosen opened a locked recording that no
            // later key could cancel, and the microphone stayed open.
            case (.armingLatch, .otherKey), (.armingLatch, .escape):
                state = .idle
                return [.cancel]

            // Locked, the hands-free key asks to finish, and its release
            // decides.
            case (.latched, .toggleDown):
                state = .armingFinish
                return []

            case (.armingFinish, .toggleUp):
                state = .idle
                return [.finish]

            // Locked, a regular key does not cancel, so a shortcut using this
            // key only takes the finish back. The recording stays locked.
            case (.armingFinish, .otherKey):
                state = .latched
                return []

            case (.armingFinish, .escape):
                state = .idle
                return [.cancel]

            case (.startingLatched, _):
                return []

            default:
                return []
            }
        }
    }

    /// The key or button that starts a dictation.
    ///
    /// A modifier is identified by keyCode plus device mask: the keyCode names
    /// the key, and the mask names the *side*, since `.command` is set with
    /// either of the two ⌘. A mouse button is identified by its number.
    ///
    /// Pure modifiers and extra mouse buttons only, on purpose. The app listens
    /// to the trigger without intercepting it, and a modifier alone types no
    /// character and triggers no system action, which is what spares the
    /// intercepting `CGEventTap`. A letter or a function key would reach the
    /// application in front at the same time as this app. The mouse button is
    /// the same bet made knowingly: the click still reaches the app in front,
    /// and the person choosing it is told so.
    public struct Trigger: Sendable, Equatable, Hashable {
        /// Where the trigger comes from. One enum for the two kinds, so that a
        /// mouse trigger carries no keyCode that could be mistaken for a key.
        public enum Source: Sendable, Equatable, Hashable {
            /// The keyCode names the key; the mask names the side.
            case modifier(keyCode: UInt16, deviceMask: UInt)
            /// Numbered as people count them: 3 is the middle button. `NSEvent`
            /// counts from zero, and the two meet in one place, `handle`.
            case mouseButton(Int)
        }

        /// What `handle` filters events by.
        public let source: Source
        public let label: String

        /// One static per key and side, so that the menu, the tests and the
        /// saved choice all name the same value. The keyCodes and masks are
        /// what macOS reports for each key. The left side and Fn were
        /// confirmed by dictating with each of them on 2026-09-03; a table
        /// copied from a header is a hypothesis until a key is held.
        public static let rightCommand = Trigger(keyCode: 54, deviceMask: 0x0010, label: "Right ⌘")
        public static let leftCommand  = Trigger(keyCode: 55, deviceMask: 0x0008, label: "Left ⌘")
        public static let rightOption  = Trigger(keyCode: 61, deviceMask: 0x0040, label: "Right ⌥")
        public static let leftOption   = Trigger(keyCode: 58, deviceMask: 0x0020, label: "Left ⌥")
        public static let rightControl = Trigger(keyCode: 62, deviceMask: 0x2000, label: "Right ⌃")
        public static let leftControl  = Trigger(keyCode: 59, deviceMask: 0x0001, label: "Left ⌃")
        public static let rightShift   = Trigger(keyCode: 60, deviceMask: 0x0004, label: "Right ⇧")
        public static let leftShift    = Trigger(keyCode: 56, deviceMask: 0x0002, label: "Left ⇧")
        /// Fn has no side, so the mask is `NSEvent.ModifierFlags.function`
        /// itself. Whether the key reaches a listening monitor at all depends
        /// on the keyboard: some handle Fn in firmware, and macOS never sees it.
        public static let fn           = Trigger(keyCode: 63, deviceMask: 0x0080_0000, label: "Fn")

        /// The quick picks in the menu: the three right-side modifiers.
        ///
        /// Right side because it is what the hand that is not on the mouse
        /// reaches without leaving its position, and because those keys are
        /// almost never part of a shortcut. Every shortcut that uses the
        /// trigger key starts a recording and cancels it a moment later, with
        /// the microphone, the tone and the pill along for the ride.
        public static let all: [Trigger] = [rightCommand, rightOption, rightControl]

        /// Every modifier key the app knows, reachable by `modifier(keyCode:)`.
        ///
        /// The table knows more keys than the menu offers: ⇧ and Left ⌘ are
        /// here so that a saved choice resolves, and it is the capture rule
        /// that refuses them. Caps Lock stays out on purpose: it cannot be
        /// held, and pressing it toggles the keyboard state.
        public static let modifiers: [Trigger] = [
            rightCommand, leftCommand, rightOption, leftOption,
            rightControl, leftControl, rightShift, leftShift, fn,
        ]

        /// The known modifier behind a keyCode, or nil for any other key. It is
        /// how a saved choice comes back from disk, and how the capture rule
        /// finds the mask for a key it has just seen.
        public static func modifier(keyCode: UInt16) -> Trigger? {
            modifiers.first {
                if case .modifier(let code, _) = $0.source { return code == keyCode }
                return false
            }
        }

        /// A mouse button, numbered as people count them. Nil for the first
        /// two: the primary and secondary clicks are never a trigger, since
        /// every click would start a recording.
        public static func mouseButton(_ number: Int) -> Trigger? {
            guard number >= 3 else { return nil }
            return Trigger(source: .mouseButton(number), label: "Mouse button \(number)")
        }

        /// Identifier for saving the choice.
        ///
        /// A key keeps the bare keyCode, which is what has been on disk since
        /// the menu first offered a choice; changing it would need a migration
        /// for a gain nobody sees. A mouse button carries a prefix, so the two
        /// never collide. The label is never saved: it is interface text, and
        /// changes.
        public var id: String {
            switch source {
            case .modifier(let keyCode, _): return String(keyCode)
            case .mouseButton(let number): return "mouse:\(number)"
            }
        }

        public static func named(_ id: String?) -> Trigger? {
            guard let id else { return nil }
            if id.hasPrefix("mouse:") {
                guard let number = Int(id.dropFirst("mouse:".count)) else { return nil }
                return mouseButton(number)
            }
            guard let keyCode = UInt16(id) else { return nil }
            return modifier(keyCode: keyCode)
        }

        /// The lines of the Hotkey submenu: the quick picks, plus the current
        /// trigger as a fourth line when it is off the list. Without that line
        /// a key chosen elsewhere would leave the submenu with no check mark,
        /// and the person with no way to see what is in use.
        public static func menuChoices(current: Trigger) -> [Trigger] {
            all.contains(current) ? all : all + [current]
        }

        public init(keyCode: UInt16, deviceMask: UInt, label: String) {
            self.source = .modifier(keyCode: keyCode, deviceMask: deviceMask)
            self.label = label
        }

        private init(source: Source, label: String) {
            self.source = source
            self.label = label
        }
    }

    /// Switchable in use: the choice lives in the menu.
    ///
    /// No need to reinstall the monitors, which listen to `.flagsChanged` from
    /// any key and to every extra mouse button, with the filter happening on
    /// read. What does need resetting is the state machine: a gesture in
    /// flight belongs to the key that started it. Ending the recording that
    /// gesture was holding open is the app's job (`chooseTrigger`, in
    /// `main.swift`), since the recorder does not live here.
    public var trigger: Trigger {
        didSet {
            guard trigger != oldValue else { return }
            // One press cannot mean both. The capture panel refuses the
            // trigger for the hands-free role, but the three quick picks never
            // go through the panel: without this line, picking the hands-free
            // key as the trigger would leave one key that both starts a hold
            // and locks, and the press meant to lock would be the press that
            // starts the hold.
            if handsFreeTrigger == trigger { handsFreeTrigger = nil }
            resetGesture()
        }
    }

    /// The optional second trigger: one tap locks hands-free, the next
    /// finishes. Nil means none, which is the default.
    ///
    /// Changing it resets the state machine for the same reason switching the
    /// trigger does: a gesture in flight belongs to the rule that started it.
    /// Without the reset, a lock started by the old key would wait for a
    /// finishing tap that the new key never sends as `.toggle` of the same
    /// gesture. Whoever changes it ends the recording that the abandoned
    /// gesture was holding open (`setHandsFreeTrigger`, in `main.swift`).
    public var handsFreeTrigger: Trigger? {
        didSet {
            guard handsFreeTrigger != oldValue else { return }
            // Only a gesture holding this key is abandoned by the change. A
            // locked recording is not: every way out of it, the trigger's tap
            // and Esc, works without this key, so resetting would throw away a
            // dictation that the change cannot affect.
            guard latch.isHoldingHandsFreeKey else { return }
            resetGesture()
        }
    }

    /// True while the gesture in flight is holding the hands-free key. Whoever
    /// changes that key reads this first: it is what says whether a recording
    /// was left with no way to end it.
    public var isHoldingHandsFreeKey: Bool { latch.isHoldingHandsFreeKey }

    /// Whether two taps lock the recording, switchable from the menu.
    ///
    /// Somebody who locks by accident needs a way out of the mode, and the mode
    /// costs everyone else up to 300 ms on a tap under the threshold. Changing
    /// it resets the state machine for the same reason switching keys does: a
    /// gesture already in flight belongs to the rule that started it.
    ///
    /// What the reset cannot do is stop a recording, because the recorder does
    /// not live here. Whoever flips this has to end the recording that the
    /// abandoned gesture was holding open (`toggleHandsFree`, in `main.swift`).
    public var handsFreeEnabled: Bool {
        didSet {
            guard handsFreeEnabled != oldValue else { return }
            resetGesture()
        }
    }

    /// Returns whether `.pressed` actually started a recording. Other event
    /// return values are ignored. A refusal resets the gesture in the monitor,
    /// so every failure path gets the same state-machine cleanup.
    public var onEvent: (@MainActor (Event) -> Bool)?

    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var latch: Latch
    private var tapTimer: Timer?

    /// True while the recording continues without the key held.
    public var isLatched: Bool { latch.isLatched }

    /// The `Latch` is built here as well: a property observer does not run
    /// during initialization, so setting `handsFreeEnabled` alone would leave
    /// the state machine on the default rule, whatever was chosen.
    public init(trigger: Trigger = .rightCommand, handsFreeEnabled: Bool = true) {
        self.trigger = trigger
        self.handsFreeEnabled = handsFreeEnabled
        self.latch = Latch(handsFree: handsFreeEnabled)
    }

    /// The Accessibility grant required for synthetic input.
    ///
    /// Do not infer it from the global monitor: macOS can still deliver the
    /// modifier event while this is false, then refuse the ⌘V at the end. The
    /// app queries the real permission before every recording attempt.
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

        // The extra mouse buttons are in the mask whatever the trigger is, so
        // that switching to a button needs no reinstall, the same as switching
        // keys. The primary and secondary clicks never are: with them in the
        // mask, every click in the system would come through here.
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp]
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
        resetGesture()
    }

    /// Back to idle, with nothing armed. The `Latch` is rebuilt, because the
    /// rule it was built with is what changed.
    private func resetGesture() {
        tapTimer?.invalidate()
        tapTimer = nil
        latch = Latch(handsFree: handsFreeEnabled)
    }


    /// Whether the event is this trigger's press (true), its release (false),
    /// or somebody else's (nil).
    private static func press(of trigger: Trigger, in event: NSEvent) -> Bool? {
        switch (event.type, trigger.source) {
        case (.flagsChanged, .modifier(let keyCode, let deviceMask)):
            guard event.keyCode == keyCode else { return nil }
            return (event.modifierFlags.rawValue & deviceMask) != 0
        // `buttonNumber` counts from zero and people count from one, so the
        // middle button is 2 here and "Mouse button 3" everywhere else. This
        // is the one place the two meet.
        case (.otherMouseDown, .mouseButton(let number)), (.otherMouseUp, .mouseButton(let number)):
            guard event.buttonNumber + 1 == number else { return nil }
            return event.type == .otherMouseDown
        default:
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            // 53 is Escape. In hands-free it is the only way out without
            // transcribing. A regular key during a mouse-button hold cancels
            // too, the same rule as for a key, so the state machine stays
            // untouched.
            apply(latch.handle(event.keyCode == 53 ? .escape : .otherKey))
            return
        }
        // Both edges of the hands-free key reach the machine: the press asks,
        // and the release decides. A regular key in between means the two were
        // a shortcut.
        if let handsFreeTrigger, let down = Self.press(of: handsFreeTrigger, in: event) {
            apply(latch.handle(down ? .toggleDown : .toggleUp))
            return
        }
        if let down = Self.press(of: trigger, in: event) {
            apply(latch.handle(down ? .down(event.timestamp) : .up(event.timestamp)))
        }
    }

    private func apply(_ actions: [Latch.Action]) {
        for action in actions {
            switch action {
            case .start:
                let accepted = onEvent?(.pressed) ?? false
                apply(latch.resolveStart(accepted: accepted))
            case .finish: _ = onEvent?(.released)
            case .cancel: _ = onEvent?(.cancelled)
            case .latch:  _ = onEvent?(.latched)
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
