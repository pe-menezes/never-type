import AppKit

/// Whether the ⌘V has anywhere to land.
///
/// The app posts a synthetic ⌘V wherever the cursor is. With the focus on
/// something that takes no text, that ⌘V becomes an arbitrary shortcut in the
/// application in front, and in several applications ⌘V does something else
/// (Finder pastes a file, and a menu item can be triggered by it).
///
/// The whole design of this type follows from one asymmetry: **a false negative
/// is worse than the defect it fixes**. Refusing to paste where pasting would
/// have worked leaves the app mute after a dictation the person already spoke,
/// which is the complaint the README exists to avoid. So the only answer that
/// stops the ⌘V is a positive `notEditable`. An error from the Accessibility
/// API, a missing permission, an element with no role and a role nobody here
/// recognizes all come back as `unknown`, and `unknown` pastes.
public enum PasteTarget {

    /// What the Accessibility API managed to say about the focused element.
    ///
    /// Two fields, and both are what the rule below needs. Kept apart from the
    /// query so the decision can be exercised without a focused application:
    /// the same split as `Transcriber.isValid(magic:size:)`.
    public struct Focus: Equatable, Sendable {
        /// `AXRole`. `nil` when the element does not answer the attribute.
        public let role: String?
        /// `AXValue` answered `AXUIElementIsAttributeSettable` with true.
        /// Settable implies present: the call returns
        /// `kAXErrorAttributeUnsupported` for an attribute the element lacks.
        public let valueIsSettable: Bool

        public init(role: String?, valueIsSettable: Bool) {
            self.role = role
            self.valueIsSettable = valueIsSettable
        }
    }

    /// The verdict, with the reason that produced it so the log can name it.
    public enum Decision: Equatable, Sendable {
        case editable(String)
        case notEditable(String)
        case unknown(String)

        /// Only a positive "no" stops the paste. See the type's doc comment.
        public var allowsPaste: Bool {
            guard case .notEditable = self else { return true }
            return false
        }
    }

    /// Roles that take typed text.
    ///
    /// Three, and no more. Every role added here is a promise that the ⌘V lands
    /// as text, and a wrong entry costs nothing (the element would fall through
    /// to `unknown`, which also pastes), while the list being short costs
    /// nothing either.
    public static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox",
    ]

    /// Roles where a ⌘V has no text destination.
    ///
    /// Controls and menus, which is the set where the answer does not depend on
    /// the application: a button takes no text in any app, and a dictation
    /// arriving as ⌘V on a focused button is the defect this check exists for.
    ///
    /// Lists, tables and outlines are deliberately absent. Finder in list view
    /// would be a good catch, and a spreadsheet cell and an in-place rename live
    /// under the same roles, where typing does start editing. Those go to
    /// `unknown` and paste.
    public static let rolesWithoutText: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXSlider", "AXStepper", "AXIncrementor", "AXImage", "AXStaticText",
        "AXProgressIndicator", "AXScrollBar", "AXDisclosureTriangle",
        "AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem",
        "AXToolbar", "AXTabGroup",
    ]

    /// The rule, with no system call in it.
    ///
    /// Order matters. A settable `AXValue` is checked first, so an element that
    /// takes text is accepted even when its role sits in `rolesWithoutText`: an
    /// `AXStaticText` that answers "yes, you can set my value" is editable, and
    /// the role list never gets to veto it.
    public static func decide(_ focus: Focus?) -> Decision {
        guard let focus else { return .unknown("no focused element") }
        if focus.valueIsSettable { return .editable("settable AXValue") }
        guard let role = focus.role else { return .unknown("element with no role") }
        if editableRoles.contains(role) { return .editable(role) }
        if rolesWithoutText.contains(role) { return .notEditable(role) }
        return .unknown(role)
    }

    /// `UserDefaults` key, domain `com.nevertype.app`. On by default.
    ///
    /// Switchable off because the check is the kind of thing that can be wrong
    /// on a machine nobody here has seen: an application that reports a role
    /// from `rolesWithoutText` while a text field is right there would leave the
    /// person with a mute app and no way out. `defaults write com.nevertype.app
    /// checkFocusBeforePaste -bool false` is that way out, and with the check off
    /// the behavior is the one shipped until 2026-08-30.
    public static let checkKey = "checkFocusBeforePaste"

    /// Queried on every dictation, never stored: the person can flip the key
    /// while the app runs, the same way the permissions are read from the system
    /// every time the menu opens.
    public static var isCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: checkKey) as? Bool ?? true
    }

    /// Cap on how long the focused application has to answer.
    ///
    /// The AX call is a message to the application in front, and a hung
    /// application would hold this one. The API's own default is not documented
    /// with a number, so the timeout is set explicitly. Timing out is not a
    /// problem: it reaches `unknown`, which pastes, so the worst case is this
    /// much added to a dictation that already costs ~600 ms. Chosen, not
    /// measured.
    public static let messagingTimeout: Float = 0.2

    // The attribute names as literals, not the `kAX…` constants.
    //
    // `HotkeyMonitor.requestAccessibilityPermission` already does this for
    // `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects for concurrency.
    // These are the strings the API compares, they are stable across macOS
    // versions, and the literal keeps a global `var` out of the file.
    private static let focusedUIElementAttribute = "AXFocusedUIElement"
    private static let roleAttribute = "AXRole"
    private static let valueAttribute = "AXValue"

    /// Asks the system what has the focus, session wide.
    ///
    /// Cheap because the app already holds Accessibility for the global key, so
    /// there is no permission to acquire here. Without the grant the call fails
    /// with `kAXErrorAPIDisabled` and this returns `unknown`, which pastes,
    /// which is the behavior of the version that never asked.
    ///
    /// Isolated to no actor, and that is deliberate: the AX API documents no
    /// main thread contract, and there is no state here to protect. Asserting a
    /// main thread that Apple never promised is the mistake that took this
    /// process down twice (`docs/pitfalls.md`).
    public static func current() -> Decision {
        guard isCheckEnabled else { return .unknown("check turned off") }

        let system = AXUIElementCreateSystemWide()
        // Best effort. A failure here leaves the API default in place, which is
        // slower to give up and still ends in `unknown`.
        _ = AXUIElementSetMessagingTimeout(system, messagingTimeout)

        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system, focusedUIElementAttribute as CFString, &focused)
        // The type is confirmed before the cast, and the cast is not `as!`: the
        // conventions rule out force unwrapping outside provably safe literals.
        guard status == .success, let value = focused,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .unknown("AXFocusedUIElement failed (\(status.rawValue))")
        }
        return decide(read(unsafeBitCast(value, to: AXUIElement.self)))
    }

    private static func read(_ element: AXUIElement) -> Focus {
        var raw: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(
            element, roleAttribute as CFString, &raw)
        let role = (roleStatus == .success) ? (raw as? String) : nil

        var settable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(
            element, valueAttribute as CFString, &settable)
        return Focus(role: role,
                     valueIsSettable: settableStatus == .success && settable.boolValue)
    }
}
