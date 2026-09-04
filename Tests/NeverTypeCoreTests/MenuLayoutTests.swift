import Testing
@testable import NeverTypeCore

/// Which lines the menu builds, given the state it read when it opened.
///
/// The verdict that produced this layout was about the state where everything
/// works: the menu opened with six lines of grey text before anything you could
/// click. That is the first test here, and it is an equality against the whole
/// list, not a search for what should be missing: a menu is an ordered thing,
/// and the order is half of the complaint.
@Suite("Menu layout")
struct MenuLayoutTests {

    /// The six lines the verdict was about, plus the notice that comes with the
    /// login item. None of them takes a click.
    private static let unclickable: [MenuLayout.Row] = [
        .trigger, .gestureHint, .model, .version,
        .microphoneMissing, .accessibilityMissing, .loginItemTurnedOff,
    ]

    private func conditions(microphone: Bool = true,
                            accessibility: Bool = true,
                            option: Bool = false,
                            history: Int = 0,
                            trigger: String = "Right ⌘",
                            handsFree: Bool = true,
                            handsFreeKey: String? = nil,
                            startsAtLogin: Bool = false,
                            needsApproval: Bool = false) -> MenuLayout.Conditions {
        MenuLayout.Conditions(microphoneAuthorized: microphone,
                              accessibilityAuthorized: accessibility,
                              showsDiagnostics: option,
                              historyCount: history,
                              triggerLabel: trigger,
                              handsFreeEnabled: handsFree,
                              handsFreeKeyLabel: handsFreeKey,
                              startsAtLogin: startsAtLogin,
                              loginItemNeedsApproval: needsApproval)
    }

    @Test("with everything in order the menu holds nothing you cannot click")
    func theDefaultMenu() {
        let rows = MenuLayout.rows(for: conditions(history: 30))

        #expect(rows == [
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .separator,
            .copyLastTranscription,
            .history(count: 30),
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
        for dead in Self.unclickable {
            #expect(!rows.contains(dead), "\(dead) takes no click and it was in the default menu")
        }
    }

    /// Option restores the four lines that left, each one back where it used to
    /// be: the trigger and its summary open the menu, the model and the version
    /// sit above the login item.
    @Test("Option brings the four diagnostic lines back, and touches nothing else")
    func optionShowsTheDiagnostics() {
        let rows = MenuLayout.rows(for: conditions(option: true, history: 30))

        #expect(rows == [
            .trigger,
            .gestureHint,
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .separator,
            .copyLastTranscription,
            .history(count: 30),
            .separator,
            .model,
            .version,
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
    }

    /// The state that has something to say says it first. Without Accessibility
    /// the trigger does not even start a recording, so the line and the way out
    /// of it open the menu, above the settings.
    @Test("a missing Accessibility opens the menu, with its settings item under it")
    func accessibilityMissing() {
        let rows = MenuLayout.rows(for: conditions(accessibility: false, history: 30))

        #expect(Array(rows.prefix(4)) == [
            .accessibilityMissing,
            .openAccessibilitySettings,
            .separator,
            .hotkey(trigger: "Right ⌘"),
        ])
        #expect(!rows.contains(.microphoneMissing), "the microphone was granted")
    }

    /// The microphone line comes alone: the prompt for it is the system's, asked
    /// once at launch, and the app has no settings item to offer for it.
    @Test("a missing microphone shows its line and no item under it")
    func microphoneMissing() {
        let rows = MenuLayout.rows(for: conditions(microphone: false))

        #expect(rows == [
            .microphoneMissing,
            .separator,
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
    }

    @Test("with both permissions missing both lines show, Accessibility first")
    func bothPermissionsMissing() {
        let rows = MenuLayout.rows(for: conditions(microphone: false, accessibility: false))

        #expect(Array(rows.prefix(4)) == [
            .accessibilityMissing,
            .openAccessibilitySettings,
            .microphoneMissing,
            .separator,
        ])
    }

    /// A missing permission is the only thing that puts unclickable text in the
    /// menu, and it earns it: with it missing the app does not dictate at all.
    @Test("even with a permission missing, Option is what adds the rest")
    func aMissingPermissionDoesNotBringTheDiagnosticsBack() {
        let rows = MenuLayout.rows(for: conditions(accessibility: false))

        #expect(!rows.contains(.model))
        #expect(!rows.contains(.version))
        #expect(!rows.contains(.trigger))
        #expect(!rows.contains(.gestureHint))
    }

    @Test("before the first transcription the whole block is gone, its separator included")
    func nothingTranscribedYet() {
        let rows = MenuLayout.rows(for: conditions(history: 0))

        #expect(rows == [
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
    }

    /// A "History (1)" holding the same text as the line above it is a second
    /// copy of one item, not a history.
    @Test("the history submenu appears from the second transcription on")
    func historyAppearsFromTheSecondOn() {
        let afterOne = MenuLayout.rows(for: conditions(history: 1))
        let afterTwo = MenuLayout.rows(for: conditions(history: 2))

        #expect(afterOne.contains(.copyLastTranscription))
        #expect(!afterOne.contains(.history(count: 1)))
        #expect(afterTwo.contains(.copyLastTranscription))
        #expect(afterTwo.contains(.history(count: 2)), "the count is the one that reached the layout")
    }

    /// The title is where the gesture is taught, so the key has to reach the
    /// line. A "Hotkey" that never names a key teaches nobody anything.
    @Test("the chosen key reaches the item that names it")
    func theChosenKeyReachesTheItem() {
        for label in ["Right ⌘", "Right ⌥", "Right ⌃"] {
            let rows = MenuLayout.rows(for: conditions(trigger: label))

            #expect(rows.contains(.hotkey(trigger: label)),
                    "the menu was built with \(label) chosen and the line did not carry it")
        }
    }

    /// Turned off, two taps no longer lock, and a line still promising the lock
    /// would be teaching a gesture that does nothing.
    @Test("with hands-free off the item says so, and the menu keeps its shape")
    func handsFreeOff() {
        let rows = MenuLayout.rows(for: conditions(handsFree: false))

        #expect(rows == [
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: false),
            .vocabulary,
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
    }

    /// The second key reaches the title for the same reason the first does.
    /// Off, the key is not taught: the mode does not listen to it, and the
    /// title says so instead.
    @Test("the hands-free key reaches the item that names it")
    func theHandsFreeKeyReachesTheItem() {
        let none = MenuLayout.rows(for: conditions())
        let chosen = MenuLayout.rows(for: conditions(handsFreeKey: "Right ⌥"))
        let off = MenuLayout.rows(for: conditions(handsFree: false, handsFreeKey: "Right ⌥"))

        #expect(none.contains(.handsFree(enabled: true, key: nil)))
        #expect(chosen.contains(.handsFree(enabled: true, key: "Right ⌥")),
                "the menu was built with Right ⌥ as the hands-free key and the line did not carry it")
        #expect(off.contains(.handsFree(enabled: false, key: nil)),
                "off, the title says off; the key stays with the monitor")
    }

    /// The summary under Option is the double tap's. Without the double tap it
    /// is grey text about a gesture that no longer exists, and the line above
    /// it, the trigger held and spoken into, is by then the whole cycle.
    @Test("the gesture summary leaves the diagnostics with hands-free off")
    func theGestureSummaryFollowsHandsFree() {
        let on = MenuLayout.rows(for: conditions(option: true))
        let off = MenuLayout.rows(for: conditions(option: true, handsFree: false))

        #expect(on.contains(.gestureHint))
        #expect(!off.contains(.gestureHint), "it describes the lock, and there is no lock")
        #expect(off.contains(.trigger), "hold and speak is still what the key does")
    }

    @Test("the login item carries its own checkmark")
    func loginItemCheckmark() {
        #expect(MenuLayout.rows(for: conditions(startsAtLogin: true)).contains(.startAtLogin(enabled: true)))
        #expect(MenuLayout.rows(for: conditions(startsAtLogin: false)).contains(.startAtLogin(enabled: false)))
    }

    /// Turned off in System Settings, no click in this menu fixes it, so the
    /// notice and the shortcut to that pane only exist in that state.
    @Test("the Login Items notice only shows when macOS is the one holding it off")
    func loginItemNoticeOnlyWhenNeeded() {
        let refused = MenuLayout.rows(for: conditions(needsApproval: true))
        let ordinary = MenuLayout.rows(for: conditions())

        #expect(Array(refused.suffix(4)) == [
            .startAtLogin(enabled: false),
            .loginItemTurnedOff,
            .openLoginItems,
            .quit,
        ])
        #expect(!ordinary.contains(.loginItemTurnedOff))
        #expect(!ordinary.contains(.openLoginItems))
    }

    /// Quit closes the menu in every state, and nothing is ever added after it.
    @Test("Quit is the last line whatever the state")
    func quitIsAlwaysLast() {
        let states = [
            conditions(),
            conditions(history: 30),
            conditions(microphone: false, accessibility: false, option: true, history: 30,
                       startsAtLogin: true, needsApproval: true),
        ]

        for state in states {
            #expect(MenuLayout.rows(for: state).last == .quit)
        }
    }
}
