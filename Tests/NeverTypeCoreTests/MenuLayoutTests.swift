import Foundation
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

    private func conditions(microphone: MicrophoneAccess = .authorized,
                            accessibility: Bool = true,
                            option: Bool = false,
                            history: Int = 0,
                            trigger: String = "Right ⌘",
                            handsFree: Bool = true,
                            handsFreeKey: String? = nil,
                            startsAtLogin: Bool = false,
                            needsApproval: Bool = false,
                            pillAlwaysVisible: Bool = true,
                            pausesMedia: Bool = true,
                            updateCheck: Bool = false) -> MenuLayout.Conditions {
        MenuLayout.Conditions(microphone: microphone,
                              accessibilityAuthorized: accessibility,
                              showsDiagnostics: option,
                              historyCount: history,
                              triggerLabel: trigger,
                              handsFreeEnabled: handsFree,
                              handsFreeKeyLabel: handsFreeKey,
                              startsAtLogin: startsAtLogin,
                              loginItemNeedsApproval: needsApproval,
                              pillAlwaysVisible: pillAlwaysVisible,
                              pausesMedia: pausesMedia,
                              updateCheckAvailable: updateCheck)
    }

    @Test("with everything in order the menu holds nothing you cannot click")
    func theDefaultMenu() {
        let rows = MenuLayout.rows(for: conditions(history: 30))

        #expect(rows == [
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .pillAlwaysVisible(enabled: true),
            .pauseMedia(enabled: true),
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
            .pillAlwaysVisible(enabled: true),
            .pauseMedia(enabled: true),
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

    /// The microphone line comes with its way out, like the Accessibility one.
    /// It used to come alone, on the idea that macOS asks once at launch; on
    /// 2026-10-15 a person got the Accessibility prompt and never the
    /// microphone one, and the menu had nothing to offer.
    @Test("a denied or restricted microphone shows its line with its settings item under it",
          arguments: [MicrophoneAccess.denied, .restricted])
    func microphoneMissing(access: MicrophoneAccess) {
        let rows = MenuLayout.rows(for: conditions(microphone: access))

        #expect(rows == [
            .microphoneMissing,
            .openMicrophoneSettings,
            .separator,
            .hotkey(trigger: "Right ⌘"),
            .handsFree(enabled: true),
            .vocabulary,
            .pillAlwaysVisible(enabled: true),
            .pauseMedia(enabled: true),
            .separator,
            .startAtLogin(enabled: false),
            .quit,
        ])
    }

    /// Audit B2: never answered, the app may not be in the Microphone list
    /// yet, and that page has no + button. The way out is the prompt, so the
    /// item asks again instead of sending the person to a list with nothing
    /// to turn on.
    @Test("a microphone never answered offers to ask again, never the Settings page")
    func undeterminedMicrophoneAsksAgain() {
        let rows = MenuLayout.rows(for: conditions(microphone: .notDetermined))

        #expect(Array(rows.prefix(4)) == [
            .microphoneMissing,
            .askForMicrophone,
            .separator,
            .hotkey(trigger: "Right ⌘"),
        ])
        #expect(!rows.contains(.openMicrophoneSettings),
                "the Microphone page may not list the app yet: \(rows)")
    }

    @Test("a granted microphone takes no line and no item")
    func microphoneGrantedHasNoItem() {
        let rows = MenuLayout.rows(for: conditions(microphone: .authorized, accessibility: false))

        #expect(!rows.contains(.microphoneMissing))
        #expect(!rows.contains(.openMicrophoneSettings))
        #expect(!rows.contains(.askForMicrophone))
    }

    @Test("with both permissions missing both lines show, Accessibility first")
    func bothPermissionsMissing() {
        let denied = MenuLayout.rows(for: conditions(microphone: .denied, accessibility: false))
        let unanswered = MenuLayout.rows(for: conditions(microphone: .notDetermined, accessibility: false))

        #expect(Array(denied.prefix(5)) == [
            .accessibilityMissing,
            .openAccessibilitySettings,
            .microphoneMissing,
            .openMicrophoneSettings,
            .separator,
        ])
        #expect(Array(unanswered.prefix(5)) == [
            .accessibilityMissing,
            .openAccessibilitySettings,
            .microphoneMissing,
            .askForMicrophone,
            .separator,
        ])
    }

    /// `Sources/NeverType/` is not importable from here, so the alert and the
    /// item are held by the text of `main.swift`: the oracle the repository
    /// uses for the executable target (`.vibeflow/conventions.md`, Team
    /// Conventions). The behavior itself is checked by hand.
    ///
    /// Each call is looked for inside the body that has to make it, never
    /// anywhere in the file: audit B1 found `showMicrophoneRequiredAlert()`
    /// matching its own declaration, and the test stayed green with the call
    /// deleted from the trigger.
    @Test("the app draws the microphone items and alerts, and opens the Microphone page")
    func microphoneWiring() throws {
        let source = try Self.mainSource()
        #expect(source.components(separatedBy: "\"Open Microphone Settings…\"").count - 1 == 1,
                "expected the menu item once")
        #expect(source.components(separatedBy: "\"Ask for Microphone Access…\"").count - 1 == 1,
                "expected the menu item once")
        let openItem = try Self.body(of: "case .openMicrophoneSettings:", in: source)
        #expect(openItem.contains("#selector(openMicrophoneSettings)"))
        let askItem = try Self.body(of: "case .askForMicrophone:", in: source)
        #expect(askItem.contains("#selector(askForMicrophoneFromMenu)"))
        let opener = try Self.body(of: "@objc private func openMicrophoneSettings() {", in: source)
        #expect(opener.contains("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"))

        // Denied or restricted: the alert that opens the Microphone page.
        let refused = try Self.body(of: "case .showMicrophoneWarning:", in: source)
        #expect(refused.contains("self?.showMicrophoneRequiredAlert()"),
                "the trigger with a refused microphone must reach its alert:\n\(refused)")
        try Self.expectAlert("private func showMicrophoneRequiredAlert() {", in: source,
                             title: "\"NeverType needs Microphone access\"",
                             text: "\"Recording did not start. Enable NeverType in System Settings › Privacy & Security › Microphone, then try again.\"",
                             buttons: ["\"Open System Settings\"", "\"Not Now\""])
        #expect(try Self.body(of: "private func showMicrophoneRequiredAlert() {", in: source)
            .contains("openMicrophoneSettings()"))

        // Launch goes through the Core rule that waits for the microphone
        // answer, never the two calls side by side.
        #expect(source.components(separatedBy: "LaunchPermissions.run(").count - 1 == 1)
        #expect(!source.contains("requestMicrophoneAccess()\n        warnIfAccessibilityMissing()"),
                "the two prompts back to back are the race this replaced")
    }

    /// Audit D1: the trigger with a microphone never answered. With a request
    /// in flight the waiting alert comes at once; with none, the app asks
    /// again and the same alert comes when the wait ends with no answer.
    @Test("the trigger with an unanswered microphone reaches the request and the waiting alert")
    func undeterminedMicrophoneWiring() throws {
        let source = try Self.mainSource()

        // The launch request is the one a trigger can find in flight.
        let launch = try Self.body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: source)
        #expect(launch.contains("requestMicrophone: { await self.microphoneRequest.ask { await self.askForMicrophone() } }"),
                "the launch request must go through the request in flight:\n\(launch)")

        let handle = try Self.body(of: "private func handle(_ event: HotkeyMonitor.Event) -> Bool {", in: source)
        #expect(handle.contains("microphoneRequestPending: microphoneRequest.isPending"),
                "the trigger must tell the rule whether a request is in flight")

        let waiting = try Self.body(of: "case .showMicrophoneWaitingAlert:", in: source)
        #expect(waiting.contains("self?.showMicrophoneWaitingAlert()"),
                "with a request in flight the trigger must show the alert:\n\(waiting)")

        let asking = try Self.body(of: "case .requestMicrophoneAccess:", in: source)
        #expect(asking.contains("self?.askAgainForMicrophone()"),
                "the unanswered trigger must ask again:\n\(asking)")
        let menuAction = try Self.body(of: "@objc private func askForMicrophoneFromMenu() {", in: source)
        #expect(menuAction.contains("askAgainForMicrophone()"))

        let again = try Self.body(of: "private func askAgainForMicrophone() {", in: source)
        #expect(again.contains("await self.microphoneRequest.askAgain("))
        #expect(again.contains("request: { await self.askForMicrophone() }"))
        #expect(again.contains("onNoAnswer: { self.showMicrophoneWaitingAlert() }"),
                "the alert after the wait must be wired:\n\(again)")

        try Self.expectAlert("private func showMicrophoneWaitingAlert() {", in: source,
                             title: "\"NeverType is waiting for the microphone answer\"",
                             text: "\"Recording did not start. The macOS prompt may be behind other windows. If there is none, quit NeverType and open it again: it asks at launch.\"",
                             buttons: ["\"OK\""])
    }

    /// The `permissions:` line at launch, before the prompts, and the call
    /// that writes it. Audit S16 removed the first and stayed green.
    @Test("the permissions line is written at launch, before and after the prompts")
    func permissionLineWiring() throws {
        let source = try Self.mainSource()
        let launch = try Self.body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: source)
        let before = try #require(launch.range(of: "logPermissionsIfChanged()"),
                                  "no permissions line at launch")
        let run = try #require(launch.range(of: "LaunchPermissions.run("))
        #expect(before.upperBound <= run.lowerBound, "the first line has to come before the prompts")
        #expect(launch[run.upperBound...].contains("self.logPermissionsIfChanged()"),
                "and another one after them")

        let writer = try Self.body(of: "private func logPermissionsIfChanged(", in: source)
        #expect(writer.contains("permissionLog.lineIfChanged("))
        #expect(writer.contains("log(line)"), "the line has to reach the log:\n\(writer)")
    }

    /// The icon slashed with both permissions granted, until the first trigger
    /// (2026-10-16 08:28). The app now re-reads the two permissions while one
    /// is missing, and each change writes the `permissions:` line and redraws
    /// by the Core rule, which keeps the model's slash (`StatusIcon`). The
    /// watch stops itself in Core; what is held here is that the app starts
    /// it, reads the system with it, and redraws from what it reads.
    @Test("the app re-reads the permissions while one is missing, and redraws by the Core rule")
    func permissionWatchWiring() throws {
        let source = try Self.mainSource()

        let property = try Self.body(of: "private lazy var permissionWatch = PermissionWatch(", in: source)
        #expect(property.contains("read: { PermissionReading.current }"),
                "the watch has to read the system:\n\(property)")
        #expect(property.contains("onChange: { [weak self] reading in self?.permissionsChanged(reading) }"),
                "a change has to reach the app:\n\(property)")
        #expect(!property.contains("interval:"),
                "the app re-reads every second, the default:\n\(property)")

        // Audit A1 of part 1b: each call used to be looked for anywhere in its
        // body, and six sabotages stayed green, two of them bringing back the
        // slash of 08:28 (an early return ahead of the redraw, the dictation
        // guard inverted). The decisions moved to Core (`StatusIcon.redraw`,
        // `ModelState(loaded:metalActive:)`, `StatusIcon.visual`), and what is
        // left here is held line by line, like `expectAlert`.
        let changed = try Self.body(of: "private func permissionsChanged(_ reading: PermissionReading) {", in: source)
        #expect(Self.codeLines(changed) == [
            "logPermissionsIfChanged(microphone: reading.microphone, accessibility: reading.accessibilityGranted)",
            "renderResting(reading)",
        ], "a change writes the permissions line and redraws, and nothing else:\n\(changed)")

        let resting = try Self.body(of: "private func renderResting(", in: source)
        #expect(Self.codeLines(resting) == [
            "if let visual = StatusIcon.redraw(permissions: permissions, recording: recorder.isRecording,",
            "transcribing: transcriptionSession.isTranscribing, model: modelState) {",
            "render(visual)",
            "}",
        ], "the resting icon is what the Core rule says, drawn as it says:\n\(resting)")

        let launch = try Self.body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: source)
        let launchLines = Self.codeLines(launch)
        #expect(!launch.contains("if !self.micAuthorized { self.render(.blocked) }"),
                "the launch redraw went back to looking at the microphone alone")
        // Inside the permissions `Task`, right after the prompts: anywhere
        // else in launch (audit M10, in the model's failure branch) the
        // reported case is not watched.
        let run = try #require(launchLines.firstIndex(of: "await LaunchPermissions.run("),
                               "no launch prompts:\n\(launch)")
        #expect(run > 0 && launchLines[run - 1] == "Task { @MainActor in",
                "the prompts have to run in their own Task:\n\(launch)")
        let lastArgument = try #require(launchLines[run...].firstIndex { $0.hasPrefix("requestAccessibility: ") })
        #expect(Array(launchLines[(lastArgument + 1)...].prefix(4)) == [
            "self.renderResting()",
            "self.logPermissionsIfChanged()",
            "self.permissionWatch.start()",
            "}",
        ], "after the prompts: redraw, the permissions line, start watching, and the Task ends:\n\(launch)")
        #expect(launchLines.filter { $0.contains("permissionWatch.start()") }.count == 1,
                "the watch starts once at launch, after the prompts:\n\(launch)")
        // The model load: its state comes from the Core, recorded once, and
        // the icon redrawn from it (audit M5 swapped `.ready` and `.noMetal`).
        #expect(launchLines.filter { $0.contains("modelState") } == [
            "self.modelState = ModelState(loaded: loaded, metalActive: metalActive)",
        ], "the model state is recorded once, by the Core:\n\(launch)")
        let recorded = try #require(launchLines.firstIndex(of: "self.modelState = ModelState(loaded: loaded, metalActive: metalActive)"))
        #expect(launchLines.indices.contains(recorded + 1) && launchLines[recorded + 1] == "self.renderResting()",
                "the icon is redrawn once the model state is known:\n\(launch)")
        #expect(launchLines.contains("let loaded = await self.transcription.didLoad()"))
        #expect(launchLines.contains("metalActive = await self.transcription.isMetalActive()"))

        // The trigger: watch again before deciding, on every press (audit
        // M11 moved it into `.startRecording`, which never has one missing).
        let handle = try Self.body(of: "private func handle(_ event: HotkeyMonitor.Event) -> Bool {", in: source)
        let handleLines = Self.codeLines(handle)
        let decide = try #require(handleLines.firstIndex(of: "switch DictationAttempt.decide("),
                                  "no decision on the trigger:\n\(handle)")
        #expect(Array(handleLines[...decide]) == [
            "switch event {",
            "case .pressed:",
            "let microphone = MicrophoneAccess.current",
            "let accessibility = HotkeyMonitor.hasAccessibilityPermission",
            "logPermissionsIfChanged(microphone: microphone, accessibility: accessibility)",
            "permissionWatch.start()",
            "switch DictationAttempt.decide(",
        ], "a press reads, writes the line and starts watching before deciding:\n\(handle)")
        #expect(handleLines.filter { $0.contains("permissionWatch.start()") }.count == 1,
                "the trigger starts the watch once, before the decision:\n\(handle)")

        // Audit L6 of part 1: the normal icon drawn over a model failure.
        let again = try Self.body(of: "private func askAgainForMicrophone() {", in: source)
        #expect(again.contains("self.renderResting()"), "asking again redraws by the rule:\n\(again)")
        #expect(again.contains("self.permissionWatch.start()"))
        #expect(!again.contains("micAuthorized ? .idle"), "asking again draws the normal icon over the model")
    }

    /// Audit N2 of part 1: a call commented out counted as the call, and the
    /// sabotage S14c survived.
    @Test("a commented-out line counts neither as the call nor as the marker")
    func bodyIgnoresComments() throws {
        let source = """
        // func wired() {
        func wired() {
            // self?.showAlert()
            /// self?.showAlert()
                // self?.showAlert()
            other()
        }
        """
        let body = try Self.body(of: "func wired() {", in: source)
        #expect(!body.contains("showAlert()"), "a commented call counted:\n\(body)")
        #expect(body.contains("other()"))
    }

    // MARK: - Reading main.swift

    private static func mainSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/NeverType/main.swift"),
                          encoding: .utf8)
    }

    /// The lines after `marker`, up to the first one indented no deeper than
    /// the marker's own line: the body of a function or of a `case`. The marker
    /// has to be unique, or the body found could be the wrong one.
    ///
    /// Lines that are only a comment are dropped first, the marker's own
    /// included: a call commented out is not the call (audit N2 of part 1,
    /// where `// self?.showMicrophoneRequiredAlert()` kept the test green).
    private static func body(of marker: String, in source: String) throws -> String {
        let lines = source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let hits = lines.indices.filter { lines[$0].contains(marker) }
        try #require(hits.count == 1, "expected \"\(marker)\" once in main.swift, found \(hits.count)")
        let start = hits[0]
        let indent = lines[start].prefix { $0 == " " }.count
        var body: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && line.prefix(while: { $0 == " " }).count <= indent { break }
            body.append(line)
        }
        return body.joined(separator: "\n")
    }

    /// The code lines of a body, trimmed, blank lines dropped: what the
    /// line-by-line oracles compare.
    private static func codeLines(_ body: String) -> [String] {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A permission alert: behind the shared gate, with its title, text and
    /// buttons, shown modally, and with no way out before it is shown (audit
    /// S17 put a `return` ahead of it and stayed green).
    private static func expectAlert(_ marker: String, in source: String,
                                    title: String, text: String, buttons: [String]) throws {
        let alert = try body(of: marker, in: source)
        let lines = alert.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first == "guard permissionAlertGate.begin() else { return }",
                "\(marker): the shared gate has to come first, so two alerts never stack")
        #expect(lines.contains("defer { permissionAlertGate.end() }"))
        #expect(lines.contains("alert.messageText = \(title)"), "\(marker): title")
        #expect(lines.contains("alert.informativeText = \(text)"), "\(marker): text")
        let added = lines.filter { $0.hasPrefix("alert.addButton(withTitle: ") }
        #expect(added == buttons.map { "alert.addButton(withTitle: \($0))" }, "\(marker): buttons \(added)")
        #expect(alert.contains("alert.runModal()"), "\(marker): the alert is never shown")
        let exits = lines.dropFirst().filter { $0 == "return" || $0.hasPrefix("return ") || $0.contains("{ return }") }
        #expect(exits.isEmpty, "\(marker): a way out before the alert shows: \(exits)")
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
            .pillAlwaysVisible(enabled: true),
            .pauseMedia(enabled: true),
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
            .pillAlwaysVisible(enabled: true),
            .pauseMedia(enabled: true),
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

    @Test("the pill visibility item carries its own checkmark")
    func pillAlwaysVisibleCheckmark() {
        #expect(MenuLayout.rows(for: conditions(pillAlwaysVisible: true))
            .contains(.pillAlwaysVisible(enabled: true)))
        #expect(MenuLayout.rows(for: conditions(pillAlwaysVisible: false))
            .contains(.pillAlwaysVisible(enabled: false)))
    }

    /// The title used to promise a position the body never looked at. The item
    /// belongs at the root because it governs the pill everywhere. A place under
    /// Hotkey would say it applies while dictating with that key. The index is
    /// what pins it.
    @Test("the pill visibility item sits at the root, right after Vocabulary")
    func pillAlwaysVisibleSitsAtTheRoot() {
        let rows = MenuLayout.rows(for: conditions())
        guard let vocabulary = rows.firstIndex(of: .vocabulary) else {
            Issue.record("no Vocabulary row: \(rows)")
            return
        }
        #expect(rows.firstIndex(of: .pillAlwaysVisible(enabled: true)) == vocabulary + 1,
                "got: \(rows)")
    }

    @Test("the pause media item carries its own checkmark")
    func pauseMediaCheckmark() {
        #expect(MenuLayout.rows(for: conditions(pausesMedia: true))
            .contains(.pauseMedia(enabled: true)))
        #expect(MenuLayout.rows(for: conditions(pausesMedia: false))
            .contains(.pauseMedia(enabled: false)))
    }

    /// It shipped under Hotkey, beside Sounds, and the author opened the menu
    /// after updating and did not find it. The index is what pins it.
    @Test("the pause media item sits at the root, right after Always Show Pill")
    func pauseMediaSitsAtTheRoot() {
        let rows = MenuLayout.rows(for: conditions())
        guard let pill = rows.firstIndex(of: .pillAlwaysVisible(enabled: true)) else {
            Issue.record("no Always Show Pill row: \(rows)")
            return
        }
        #expect(rows.firstIndex(of: .pauseMedia(enabled: true)) == pill + 1, "got: \(rows)")
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
            conditions(microphone: .denied, accessibility: false, option: true, history: 30,
                       startsAtLogin: true, needsApproval: true),
            conditions(updateCheck: true),
        ]

        for state in states {
            #expect(MenuLayout.rows(for: state).last == .quit)
        }
    }

    /// The line only makes sense with a checkout to fetch from. Without one it
    /// goes, rather than sitting there disabled: an item you cannot click is
    /// the grey text this layout exists to avoid.
    @Test("the update check sits right above Quit, and only with a checkout reachable")
    func checkForUpdatesNeedsACheckout() {
        let without = MenuLayout.rows(for: conditions())
        #expect(!without.contains(.checkForUpdates))

        let with = MenuLayout.rows(for: conditions(updateCheck: true))
        #expect(Array(with.suffix(3)) == [.startAtLogin(enabled: false), .checkForUpdates, .quit])

        let withNotice = MenuLayout.rows(for: conditions(startsAtLogin: true, needsApproval: true, updateCheck: true))
        #expect(Array(withNotice.suffix(3)) == [.openLoginItems, .checkForUpdates, .quit],
                "the Login Items notice keeps its place under the login item; the check stays next to Quit")
    }
}
