import AppKit

/// The rule behind the capture panel: which press becomes the trigger, which
/// is refused, and what each answer says.
///
/// Pure on purpose, the same split as `HotkeyMonitor.Latch` and
/// `PointerGesture`: the panel turns `NSEvent` into `Input` and draws the
/// `Verdict`, and every branch here runs without a keyboard, a mouse or a
/// window. The table of accepted and refused keys is product behavior, and the
/// reason behind most of it is what a false start costs: pressing the trigger
/// switches the microphone on, plays the start tone and shows the pill, and
/// the cancel plays the discard tone. A key that is part of everyday shortcuts
/// would do all of that on each of them.
public struct TriggerCapture: Sendable {
    /// The trigger type, under the shorter name this file uses throughout.
    public typealias Trigger = HotkeyMonitor.Trigger

    /// What the chosen trigger is for. The hands-free key is a toggle, and it
    /// cannot be the push-to-talk key, since one press cannot mean both.
    public enum Purpose: Sendable, Equatable {
        case pushToTalk
        case handsFree(pushToTalk: Trigger)
    }

    /// One event, stripped down to what the rule needs.
    public enum Input: Sendable, Equatable {
        /// `.flagsChanged`: the key, and the raw modifier flags after the
        /// change. Whether that is a press or a release depends on the key's
        /// own mask, which the rule looks up.
        case flagsChanged(keyCode: UInt16, rawFlags: UInt)
        case keyDown(keyCode: UInt16)
        /// `NSEvent.buttonNumber + 1`, as people count.
        case mouseDown(button: Int)
        case mouseUp(button: Int)
        case rightMouseDown
    }

    /// Why a press was refused. The text names the way out, the same as the
    /// project's error enums.
    public enum Refusal: Sendable, Equatable, CustomStringConvertible {
        /// A regular key, or a combination: the app listens without
        /// intercepting, so the app in front would get it too.
        case reachesFrontApp
        case everyCapitalLetter
        case everyShortcut
        case togglesKeyboardState
        case secondaryClick
        case alreadyThePushToTalkKey

        public var description: String {
            switch self {
            case .reachesFrontApp:
                return "One key on its own. A regular key or a combination would also reach the app in front."
            case .everyCapitalLetter:
                return "Not ⇧: every capital letter would start a recording."
            case .everyShortcut:
                return "Not Left ⌘: every shortcut would start a recording. Right ⌘ works."
            case .togglesKeyboardState:
                return "Not Caps Lock: it toggles the keyboard state and cannot be held."
            case .secondaryClick:
                return "Not the primary or secondary click. A mouse button from the third on works."
            case .alreadyThePushToTalkKey:
                return "That is the push-to-talk key. Pick another one for hands-free."
            }
        }
    }

    /// Accepted, with something the person should know before it counts.
    public enum Caveat: Sendable, Equatable, CustomStringConvertible {
        case fnSystemAction
        case leftOptionAccents
        case clickReachesFrontApp

        public var description: String {
            switch self {
            case .fnSystemAction:
                return "Fn also opens the emoji picker unless System Settings > Keyboard sets \"Press 🌐 key to\" to \"Do Nothing\". Some keyboards handle Fn on their own, and macOS never sees it."
            case .leftOptionAccents:
                return "On a US layout, Left ⌥ types the accents, and every accent would start a recording."
            case .clickReachesFrontApp:
                return "The click still reaches the app in front: in a browser, button 4 is Back. A button remapped by the mouse software never reaches NeverType."
            }
        }
    }

    /// What the panel does next. `.waiting` leaves it as it is; the other
    /// four each end or change what is on screen.
    public enum Verdict: Sendable, Equatable {
        case waiting
        case accepted(Trigger)
        case acceptedWithCaveat(Trigger, Caveat)
        case refused(Refusal)
        case cancelled
    }

    /// What the panel says around the verdicts. Kept with the rule so that the
    /// panel draws and nothing else, and every sentence a person reads sits in
    /// one file.
    public enum Prompt {
        /// The window title.
        public static let title = "Choose the trigger"
        /// The standing line: what the panel takes, and the way out.
        public static let accepts = "A modifier key on either side, Fn, or a mouse button from the third on. Esc closes."
        /// Shown after `idleDelay` with no event at all. A keyboard that
        /// handles Fn in firmware, or a button taken by the mouse software,
        /// would otherwise leave the panel waiting in silence.
        public static let nothingArrived = "Nothing arrived. Some keyboards handle Fn on their own, and a button remapped by the mouse software never reaches NeverType. Esc closes."
        /// The silence before `nothingArrived`. Five seconds: long enough to
        /// find the key on the keyboard, short enough to answer a keyboard
        /// that never sends it.
        public static let idleDelay: TimeInterval = 5

        /// The first line, which names the role the key is about to play.
        public static func instruction(for purpose: Purpose) -> String {
            switch purpose {
            case .pushToTalk:
                return "Press the key or mouse button to hold while you dictate."
            case .handsFree:
                return "Press the key or mouse button that will lock hands-free: tap to lock, tap again to finish."
            }
        }

        /// The button that confirms a caveat. It names the key, so the click
        /// cannot be mistaken for a plain OK.
        public static func use(_ trigger: Trigger) -> String {
            "Use \(trigger.label)"
        }
    }

    private enum State: Equatable {
        case idle
        /// A press that becomes the trigger on its release, if nothing else
        /// comes in between.
        case holding(Trigger)
    }

    private static let capsLock: UInt16 = 57
    private static let escape: UInt16 = 53

    private let purpose: Purpose
    private var state: State = .idle

    /// A fresh rule for one opening of the panel. The purpose does not change
    /// while the panel is open, so it is fixed here.
    public init(purpose: Purpose) {
        self.purpose = purpose
    }

    /// One event in, one verdict out. `.waiting` leaves the panel as it is.
    ///
    /// A modifier is accepted on its **release**, and only if nothing else came
    /// between the press and it: a combination only shows itself after the
    /// modifier is down, and the release is when it is certain that nothing
    /// came along. A refused key is refused on the press, since there is
    /// nothing to wait for.
    public mutating func handle(_ input: Input) -> Verdict {
        switch input {
        case .flagsChanged(let keyCode, let rawFlags):
            return flagsChanged(keyCode: keyCode, rawFlags: rawFlags)

        // Escape is the way out with nothing changed. Any other key is the one
        // thing a listening monitor cannot make safe.
        case .keyDown(let keyCode):
            state = .idle
            return keyCode == Self.escape ? .cancelled : .refused(.reachesFrontApp)

        case .mouseDown(let button):
            guard let trigger = Trigger.mouseButton(button) else {
                state = .idle
                return .refused(.secondaryClick)
            }
            guard case .idle = state else {
                state = .idle
                return .refused(.reachesFrontApp)
            }
            state = .holding(trigger)
            return .waiting

        case .mouseUp(let button):
            guard case .holding(let held) = state, held.source == .mouseButton(button) else {
                return .waiting
            }
            state = .idle
            return accept(held)

        case .rightMouseDown:
            state = .idle
            return .refused(.secondaryClick)
        }
    }

    private mutating func flagsChanged(keyCode: UInt16, rawFlags: UInt) -> Verdict {
        // Caps Lock arrives as `.flagsChanged` too, and it is the one modifier
        // that cannot be held: pressing it toggles the keyboard state.
        if keyCode == Self.capsLock {
            state = .idle
            return .refused(.togglesKeyboardState)
        }
        guard let key = Trigger.modifier(keyCode: keyCode),
              case .modifier(_, let mask) = key.source else {
            // A modifier the app does not know. Nothing to say about it.
            return .waiting
        }
        let down = rawFlags & mask != 0
        switch (state, down) {
        case (.idle, true):
            if let refusal = Self.refusal(for: key) { return .refused(refusal) }
            state = .holding(key)
            return .waiting

        // A release with nothing held: the key that opened the menu, or the end
        // of a hold that a regular key already spoiled.
        case (.idle, false):
            return .waiting

        // A second modifier on top of the held one is a combination.
        case (.holding, true):
            state = .idle
            return .refused(.reachesFrontApp)

        case (.holding(let held), false):
            guard key == held else { return .waiting }
            state = .idle
            return accept(held)
        }
    }

    private func accept(_ trigger: Trigger) -> Verdict {
        if case .handsFree(let pushToTalk) = purpose, trigger == pushToTalk {
            return .refused(.alreadyThePushToTalkKey)
        }
        if let caveat = Self.caveat(for: trigger) {
            return .acceptedWithCaveat(trigger, caveat)
        }
        return .accepted(trigger)
    }

    /// The keys the app knows and still refuses, and why: each of them is part
    /// of typing or of everyday shortcuts, and would start a recording on each.
    private static func refusal(for key: Trigger) -> Refusal? {
        if key == .leftShift || key == .rightShift { return .everyCapitalLetter }
        if key == .leftCommand { return .everyShortcut }
        return nil
    }

    private static func caveat(for trigger: Trigger) -> Caveat? {
        if trigger == .fn { return .fnSystemAction }
        if trigger == .leftOption { return .leftOptionAccents }
        if case .mouseButton = trigger.source { return .clickReachesFrontApp }
        return nil
    }
}

extension TriggerCapture.Input {
    /// The event as the rule sees it, or nil for an event the rule has no
    /// opinion on. The mapping lives with the rule, so that the panel holds no
    /// keyCode, no button number and no decision.
    public init?(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            self = .flagsChanged(keyCode: event.keyCode, rawFlags: event.modifierFlags.rawValue)
        case .keyDown:
            self = .keyDown(keyCode: event.keyCode)
        // `buttonNumber` counts from zero; the rule and the labels count from
        // one. The same conversion as `HotkeyMonitor.handle`.
        case .otherMouseDown:
            self = .mouseDown(button: event.buttonNumber + 1)
        case .otherMouseUp:
            self = .mouseUp(button: event.buttonNumber + 1)
        case .rightMouseDown:
            self = .rightMouseDown
        default:
            return nil
        }
    }
}
