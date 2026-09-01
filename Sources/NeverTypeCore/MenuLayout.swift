/// Which lines the menu bar menu is made of, apart from the AppKit that draws
/// them.
///
/// The menu used to open with six lines of grey text you could not click before
/// anything you could: the trigger, its summary, both permissions, the model and
/// the version. Twelve lines, half of them unclickable. A permission that is
/// fine now says nothing, and the diagnostic lines come back with the Option
/// key held, which is where macOS puts diagnostics.
///
/// What the lean menu cannot do on its own is tell anyone the app is there:
/// reading a menu means having already found it. So the instruction lives in
/// three places at once. The two titles here carry the gesture, `Hotkey: Right ⌘`
/// and `Hands-free: double tap`; the full cycle sits inside those two submenus,
/// found by whoever goes looking; and the tooltip on the icon and on the orb
/// (`main.swift`) is the one that reaches somebody who never clicked anything.
///
/// Separated from `NSMenu` so that "which lines, given what state" is a function
/// whose answer a test can compare: the same split as `PasteTarget.decide(_:)`.
public enum MenuLayout {

    /// Everything the menu asks about, as read at the moment it opens.
    ///
    /// Values, not the sources of them. Both permissions and the login item are
    /// queried from the system on every rebuild, because all three change from
    /// outside the app, and this type is the snapshot of one such reading.
    public struct Conditions: Equatable, Sendable {
        public let microphoneAuthorized: Bool
        public let accessibilityAuthorized: Bool
        /// The Option key, held as the menu opens.
        public let showsDiagnostics: Bool
        /// Transcriptions kept, at most 30. Zero means nothing has been
        /// dictated yet in any session that kept history.
        public let historyCount: Int
        /// The chosen key's name, `Trigger.label`.
        ///
        /// A value read from the state, the same as `historyCount`. The sentence
        /// the user reads is still assembled by the AppKit that draws it. The
        /// key reaches this file because the item is where the gesture is
        /// taught, and a gesture with no key named teaches nothing.
        public let triggerLabel: String
        /// Whether two taps lock the recording. Off, the key only records while
        /// it is held.
        public let handsFreeEnabled: Bool
        /// `LoginItem.State` flattened into the two answers the menu draws: the
        /// checkmark, and whether macOS is the one holding it off. The
        /// three-state enum stays in `LoginItem`, and this file stays free of
        /// everything except the rule.
        public let startsAtLogin: Bool
        public let loginItemNeedsApproval: Bool

        public init(microphoneAuthorized: Bool,
                    accessibilityAuthorized: Bool,
                    showsDiagnostics: Bool,
                    historyCount: Int,
                    triggerLabel: String,
                    handsFreeEnabled: Bool,
                    startsAtLogin: Bool,
                    loginItemNeedsApproval: Bool) {
            self.microphoneAuthorized = microphoneAuthorized
            self.accessibilityAuthorized = accessibilityAuthorized
            self.showsDiagnostics = showsDiagnostics
            self.historyCount = historyCount
            self.triggerLabel = triggerLabel
            self.handsFreeEnabled = handsFreeEnabled
            self.startsAtLogin = startsAtLogin
            self.loginItemNeedsApproval = loginItemNeedsApproval
        }
    }

    /// One line of the menu. The titles stay with the AppKit that draws them,
    /// since a title is text for a person and this enum is a decision.
    public enum Row: Equatable, Sendable {
        case accessibilityMissing
        case openAccessibilitySettings
        case microphoneMissing
        case trigger
        case gestureHint
        /// Carries the chosen key, because the title is where the gesture is
        /// taught: a menu you have to open to learn the menu exists reaches
        /// nobody who has not opened it.
        case hotkey(trigger: String)
        case handsFree(enabled: Bool)
        case vocabulary
        case copyLastTranscription
        case history(count: Int)
        case model
        case version
        case startAtLogin(enabled: Bool)
        case loginItemTurnedOff
        case openLoginItems
        case quit
        case separator
    }

    /// The whole menu, in order.
    ///
    /// A missing permission opens the menu, above Hotkey and Vocabulary: with
    /// one of the two missing the app does not dictate at all, so it is the
    /// first thing to read and the way out is the line under it. Accessibility
    /// comes before the microphone because it is the one that blocks the
    /// trigger before any audio is captured.
    public static func rows(for conditions: Conditions) -> [Row] {
        var rows: [Row] = []

        if !conditions.accessibilityAuthorized {
            rows.append(.accessibilityMissing)
            rows.append(.openAccessibilitySettings)
        }
        // No way out under this one: the microphone prompt is the system's, it
        // is asked for once at launch, and the app has no settings item for it.
        if !conditions.microphoneAuthorized {
            rows.append(.microphoneMissing)
        }
        if !rows.isEmpty { rows.append(.separator) }

        if conditions.showsDiagnostics {
            rows.append(.trigger)
            // The summary describes the double tap, so it goes where the double
            // tap goes. With hands-free off it would be a line of grey text
            // teaching a gesture that does nothing, and the line above it,
            // hold and speak, is by then the whole cycle.
            if conditions.handsFreeEnabled { rows.append(.gestureHint) }
        }

        rows.append(.hotkey(trigger: conditions.triggerLabel))
        rows.append(.handsFree(enabled: conditions.handsFreeEnabled))
        rows.append(.vocabulary)

        // The block appears with the first transcription and the submenu with
        // the second: a "History (1)" holding the same text as the line above it
        // is a second copy of one item, not a history.
        if conditions.historyCount > 0 {
            rows.append(.separator)
            rows.append(.copyLastTranscription)
            if conditions.historyCount > 1 {
                rows.append(.history(count: conditions.historyCount))
            }
        }

        if conditions.showsDiagnostics {
            rows.append(.separator)
            rows.append(.model)
            rows.append(.version)
        }

        rows.append(.separator)
        rows.append(.startAtLogin(enabled: conditions.startsAtLogin))
        if conditions.loginItemNeedsApproval {
            rows.append(.loginItemTurnedOff)
            rows.append(.openLoginItems)
        }
        rows.append(.quit)
        return rows
    }
}
