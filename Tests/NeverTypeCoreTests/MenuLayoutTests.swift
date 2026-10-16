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
                             buttons: ["\"Open System Settings\"", "\"Not Now\""],
                             shown: ["if alert.runModal() == .alertFirstButtonReturn {",
                                     "openMicrophoneSettings()",
                                     "}"])
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
                             buttons: ["\"OK\""],
                             shown: ["_ = alert.runModal()"],
                             logged: ["log(\"microphone: waiting alert shown\")"])
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
    ///
    /// Audits A1 and A2 of part 1b: calls looked for anywhere in a body, or a
    /// line held while the condition around it was not, let sabotages through
    /// with every test green, two of them bringing back the slash of 08:28.
    /// The decisions live in Core, under test, and every binding left here is
    /// held line by line and whole, like `expectAlert`: a condition negated,
    /// branches swapped, a call deleted, an exit ahead of it or a constant in
    /// place of a system read each change a line.
    @Test("the app re-reads the permissions while one is missing, and redraws by the Core rule")
    func permissionWatchWiring() throws {
        let source = try Self.mainSource()

        let property = try Self.body(of: "private lazy var permissionWatch = PermissionWatch(", in: source)
        #expect(Self.codeLines(property) == [
            "read: { PermissionReading.current },",
            "onChange: { [weak self] reading in self?.permissionsChanged(reading) })",
        ], "the watch reads the system every second, the default, and a change reaches the app:\n\(property)")

        let changed = try Self.body(of: "private func permissionsChanged(_ reading: PermissionReading) {", in: source)
        #expect(Self.codeLines(changed) == [
            "logPermissionsIfChanged(microphone: reading.microphone, accessibility: reading.accessibilityGranted)",
            "renderResting(reading)",
        ], "a change writes the permissions line and redraws, and nothing else:\n\(changed)")

        // The signature too: its default is the system read every caller
        // but the watch relies on.
        let resting = try Self.body(of: "private func renderResting(_ permissions: PermissionReading = .current) {", in: source)
        #expect(Self.codeLines(resting) == [
            "if let visual = StatusIcon.redraw(permissions: permissions, recording: recorder.isRecording,",
            "transcribing: transcriptionSession.isTranscribing, model: modelState) {",
            "render(visual)",
            "}",
        ], "the resting icon is what the Core rule says, drawn as it says:\n\(resting)")
    }

    /// Launch, whole: the lock, the status item, the monitor and the pill,
    /// then the permissions (the line, the prompts in their order with the
    /// system reads, the redraw by the rule, the line again and the watch) and
    /// the model load ending by the Core rule. Audit M10 moved the watch into
    /// the model's failure branch, and the case of 08:28 went unwatched.
    ///
    /// Held from the first line to the last. Reaudit 2 of part 1b: with a
    /// window of lines found by an anchor, an exit or an always-false `if`
    /// written just outside it switched off the prompts, the watch or the
    /// model load, with the 296 tests green (X-AB1 to X-AB3, X-MD1, X-MD2).
    @Test("launch asks in order, redraws by the rule, watches and loads the model, held whole")
    func launchWiring() throws {
        let source = try Self.mainSource()
        let launch = try Self.body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: source)
        #expect(Self.codeLines(launch) == [
            "guard Self.acquireInstanceLock() else {",
            "NSRunningApplication",
            ".runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? \"com.nevertype.app\")",
            ".first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?",
            ".activate()",
            "NSApp.terminate(nil)",
            "return",
            "}",
            "let ranBefore = startLog()",
            "removeLegacyTranscriptFile()",
            "storeFirstPauseMedia(ranBefore: ranBefore)",
            "statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)",
            "render(.idle)",
            "menu.delegate = self",
            "statusItem.menu = menu",
            "overlay.menu = menu",
            "if let saved = HotkeyMonitor.Trigger.named(UserDefaults.standard.string(forKey: Self.triggerKey)) {",
            "setTrigger(saved)",
            "}",
            "setHandsFreeTrigger(HotkeyMonitor.Trigger.named(UserDefaults.standard.string(forKey: Self.handsFreeTriggerKey)))",
            "monitor.handsFreeEnabled = Self.handsFreeIsOn",
            "monitor.onEvent = { [weak self] event in self?.handle(event) ?? false }",
            "recorder.onLevel = { [weak self] level in self?.overlay.push(level: level) }",
            "recorder.onError = { [weak self] message in",
            "self?.overlay.hide()",
            "self?.render(.blocked)",
            "self?.log(message)",
            "}",
            "monitor.start()",
            "overlay.showIdle()",
            "refreshHoverHint()",
            "logPermissionsIfChanged()",
            "Task { @MainActor in",
            "await LaunchPermissions.run(",
            "microphone: { MicrophoneAccess.current },",
            "accessibilityGranted: { HotkeyMonitor.hasAccessibilityPermission },",
            "requestMicrophone: { await self.microphoneRequest.ask { await self.askForMicrophone() } },",
            "requestAccessibility: { self.warnIfAccessibilityMissing() })",
            "self.renderResting()",
            "self.logPermissionsIfChanged()",
            "self.permissionWatch.start()",
            "}",
            "Task {",
            "await transcription.prepare()",
            "let status = await transcription.currentStatus()",
            "self.modelStatus = status",
            "self.log(\"model: \\(status)\")",
            "self.modelState = await ModelState.afterLoad(",
            "loaded: { await self.transcription.didLoad() },",
            "devices: { await self.transcription.deviceList() },",
            "metalActive: { await self.transcription.isMetalActive() },",
            "log: { self.log($0) })",
            "self.renderResting()",
            "}",
            "log(\"ready. trigger: \\(monitor.trigger.label) · hands-free: \\(monitor.handsFreeEnabled ? \"on\" : \"off\")\"",
            "+ \" · pill: \\(overlay.alwaysVisible ? \"always visible\" : \"only while dictating\")\"",
            "+ \" · pause media: \\(Self.pausesMedia ? \"on\" : \"off\")\")",
            "log(\"insertion: clipboard given back after \\(TextInjector.restoreDelay) s · focus checked before pasting: \\(PasteTarget.isCheckEnabled ? \"yes\" : \"no\")\")",
        ], "launch, line by line:\n\(launch)")
    }

    /// The model state is recorded in one place, the end of the load held
    /// whole in `launchWiring`. Audit A2 of part 1b: `if loaded {` turned into
    /// `if !loaded {` there slashed every working Mac with the suite green.
    @Test("the model state is recorded once, at the end of the load")
    func modelLoadWiring() throws {
        let source = try Self.mainSource()
        let assignments = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && $0.contains("modelState =") }
        #expect(assignments == [
            "private var modelState = ModelState.loading",
            "self.modelState = await ModelState.afterLoad(",
        ], "the model state is recorded once, at the end of the load: \(assignments)")
    }

    /// The trigger, from the reads to the recording: read once, write the
    /// line, watch again, decide, and each refusal draws the slash, says why
    /// and reaches its alert or the new request, returning the refusal.
    /// Audit M11 of part 1b moved the watch into `.startRecording`; S14 to S17
    /// and D1a to D1f of part 1 cut the way to each alert.
    @Test("the trigger reads, watches, decides, and each refusal reaches its way out")
    func triggerWiring() throws {
        let source = try Self.mainSource()
        let handle = try Self.body(of: "private func handle(_ event: HotkeyMonitor.Event) -> Bool {", in: source)
        let lines = Self.codeLines(handle)
        let start = try #require(lines.firstIndex(of: "try recorder.start()"), "no recording on the trigger:\n\(handle)")
        #expect(Array(lines[...start]) == [
            "switch event {",
            "case .pressed:",
            "let microphone = MicrophoneAccess.current",
            "let accessibility = HotkeyMonitor.hasAccessibilityPermission",
            "logPermissionsIfChanged(microphone: microphone, accessibility: accessibility)",
            "permissionWatch.start()",
            "switch DictationAttempt.decide(",
            "microphone: microphone,",
            "accessibilityAuthorized: accessibility,",
            "isTranscribing: transcriptionSession.isTranscribing,",
            "microphoneRequestPending: microphoneRequest.isPending",
            ") {",
            "case .waitForTranscription:",
            "log(\"transcription in progress: wait for the result before recording again\")",
            "return false",
            "case .showAccessibilityWarning:",
            "render(.blocked)",
            "log(\"Accessibility not granted: recording blocked before capturing audio\")",
            "Task { @MainActor [weak self] in",
            "self?.showAccessibilityRequiredAlert()",
            "}",
            "return false",
            "case .requestMicrophoneAccess:",
            "render(.blocked)",
            "log(\"microphone not answered yet: recording did not start, asking again\")",
            "Task { @MainActor [weak self] in",
            "self?.askAgainForMicrophone()",
            "}",
            "return false",
            "case .showMicrophoneWaitingAlert:",
            "render(.blocked)",
            "log(\"microphone request still open: recording did not start\")",
            "Task { @MainActor [weak self] in",
            "self?.showMicrophoneWaitingAlert()",
            "}",
            "return false",
            "case .showMicrophoneWarning:",
            "render(.blocked)",
            "log(\"microphone \\(microphone.rawValue): recording blocked before capturing audio\")",
            "Task { @MainActor [weak self] in",
            "self?.showMicrophoneRequiredAlert()",
            "}",
            "return false",
            "case .startRecording:",
            "break",
            "}",
            "do {",
            "try recorder.start()",
        ], "the trigger, from the reads to the recording:\n\(handle)")
        #expect(lines.filter { $0.contains("permissionWatch.start()") }.count == 1,
                "the trigger starts the watch once, before the decision:\n\(handle)")
    }

    /// Asking again, from the trigger or the menu: the request, the alert
    /// when no answer comes, then the redraw by the rule (audit L6 of part 1),
    /// the line and the watch.
    @Test("asking again for the microphone requests, alerts, redraws by the rule and watches")
    func askAgainWiring() throws {
        let source = try Self.mainSource()
        let again = try Self.body(of: "private func askAgainForMicrophone() {", in: source)
        #expect(Self.codeLines(again) == [
            "Task { @MainActor in",
            "await self.microphoneRequest.askAgain(",
            "request: { await self.askForMicrophone() },",
            "onNoAnswer: { self.showMicrophoneWaitingAlert() })",
            "self.renderResting()",
            "self.logPermissionsIfChanged()",
            "self.permissionWatch.start()",
            "}",
        ], "asking again:\n\(again)")
        let ask = try Self.body(of: "private func askForMicrophone() async {", in: source)
        #expect(Self.codeLines(ask) == ["_ = await AVCaptureDevice.requestAccess(for: .audio)"],
                "the prompt is the microphone's:\n\(ask)")
        let menuAction = try Self.body(of: "@objc private func askForMicrophoneFromMenu() {", in: source)
        #expect(Self.codeLines(menuAction) == ["askAgainForMicrophone()"])
    }

    /// The `permissions:` line: written from the system reads unless the
    /// caller passes its own, and only when it changed.
    @Test("the permissions line is written from the system reads")
    func permissionLineWriterWiring() throws {
        let source = try Self.mainSource()
        let writer = try Self.body(of: "private func logPermissionsIfChanged(microphone: MicrophoneAccess = .current,", in: source)
        #expect(Self.codeLines(writer) == [
            "accessibility: Bool = HotkeyMonitor.hasAccessibilityPermission) {",
            "if let line = permissionLog.lineIfChanged(microphone: microphone, accessibilityGranted: accessibility) {",
            "log(line)",
            "}",
        ], "the permissions line:\n\(writer)")
    }

    /// The launch warning for Accessibility, and the alert the trigger shows:
    /// nothing in a test showed either, and a negated guard here asked for a
    /// permission already granted or never asked for the missing one.
    @Test("a missing Accessibility is warned at launch, and its alert opens its page")
    func accessibilityWarningWiring() throws {
        let source = try Self.mainSource()
        let warn = try Self.body(of: "private func warnIfAccessibilityMissing() {", in: source)
        #expect(Self.codeLines(warn) == [
            "guard !HotkeyMonitor.hasAccessibilityPermission else { return }",
            "render(.blocked)",
            "log(\"Accessibility not granted: dictation is blocked until it is enabled.\")",
            "HotkeyMonitor.requestAccessibilityPermission()",
        ], "the launch warning:\n\(warn)")
        try Self.expectAlert("private func showAccessibilityRequiredAlert() {", in: source,
                             title: "\"NeverType needs Accessibility access\"",
                             text: "\"Recording did not start. Enable NeverType in System Settings › Privacy & Security › Accessibility, then try again.\"",
                             buttons: ["\"Open System Settings\"", "\"Not Now\""],
                             shown: ["if alert.runModal() == .alertFirstButtonReturn {",
                                     "openAccessibilitySettings()",
                                     "}"])
    }

    /// The menu's two permission lines come from the system reads of the
    /// moment it opens, and only from them, and every row the layout returns
    /// becomes an item. Held whole: reaudit 2 of part 1b put an exit ahead of
    /// the loop over the rows, below the lines then held, and the menu opened
    /// empty with the suite green (X-MN1).
    @Test("the menu reads both permissions from the system when it opens, held whole")
    func menuPermissionConditionsWiring() throws {
        let source = try Self.mainSource()
        let rebuild = try Self.body(of: "private func rebuildMenu() {", in: source)
        #expect(Self.codeLines(rebuild) == [
            "menu.removeAllItems()",
            "logPermissionsIfChanged()",
            "let loginState = loginItemState",
            "let conditions = MenuLayout.Conditions(",
            "microphone: MicrophoneAccess.current,",
            "accessibilityAuthorized: HotkeyMonitor.hasAccessibilityPermission,",
            "showsDiagnostics: NSEvent.modifierFlags.contains(.option),",
            "historyCount: history.entries.count,",
            "triggerLabel: monitor.trigger.label,",
            "handsFreeEnabled: monitor.handsFreeEnabled,",
            "handsFreeKeyLabel: monitor.handsFreeTrigger?.label,",
            "startsAtLogin: loginState == .on,",
            "loginItemNeedsApproval: loginState == .needsApproval,",
            "pillAlwaysVisible: overlay.alwaysVisible,",
            "pausesMedia: Self.pausesMedia,",
            "updateCheckAvailable: UpdateCheck.isAvailable(repoRoot: Self.repoRoot))",
            "for row in MenuLayout.rows(for: conditions) {",
            "menu.addItem(item(for: row))",
            "}",
        ], "the menu rebuild, line by line:\n\(rebuild)")
    }

    /// Each row to its item, the permission ones to their own action. Held
    /// whole: reaudit 2 of part 1b pointed the Accessibility item at the
    /// Microphone page and stayed green (X-AV2).
    @Test("each menu row becomes its item, each permission item opens its own page")
    func menuItemsWiring() throws {
        let source = try Self.mainSource()
        let items = try Self.body(of: "private func item(for row: MenuLayout.Row) -> NSMenuItem {", in: source)
        #expect(Self.codeLines(items) == [
            "switch row {",
            "case .separator:",
            "return .separator()",
            "case .accessibilityMissing:",
            "return disabled(\"Accessibility: missing\")",
            "case .openAccessibilitySettings:",
            "return action(\"Open Accessibility Settings…\", #selector(openAccessibilitySettings))",
            "case .microphoneMissing:",
            "return disabled(\"Microphone: missing\")",
            "case .openMicrophoneSettings:",
            "return action(\"Open Microphone Settings…\", #selector(openMicrophoneSettings))",
            "case .askForMicrophone:",
            "return action(\"Ask for Microphone Access…\", #selector(askForMicrophoneFromMenu))",
            "case .trigger:",
            "return disabled(\"Trigger: \\(monitor.trigger.label) (hold and speak)\")",
            "case .gestureHint:",
            "return disabled(\"  double-tap locks · tap to finish · Esc discards\")",
            "case .hotkey(let trigger):",
            "let item = NSMenuItem(title: \"Hotkey: \\(trigger)\", action: nil, keyEquivalent: \"\")",
            "item.submenu = hotkeyMenu()",
            "return item",
            "case .handsFree(let enabled, let key):",
            "let title: String",
            "if !enabled {",
            "title = \"Hands-free: off\"",
            "} else if let key {",
            "title = \"Hands-free: double tap or \\(key)\"",
            "} else {",
            "title = \"Hands-free: double tap\"",
            "}",
            "let item = NSMenuItem(title: title, action: nil, keyEquivalent: \"\")",
            "item.submenu = handsFreeMenu(enabled: enabled)",
            "return item",
            "case .vocabulary:",
            "let counts = vocabulary.terms.count + vocabulary.replacements.count",
            "let title = counts > 0",
            "? \"Vocabulary (\\(vocabulary.terms.count) terms, \\(vocabulary.replacements.count) replacements)…\"",
            ": \"Vocabulary…\"",
            "return action(title, #selector(openVocabulary))",
            "case .pillAlwaysVisible(let enabled):",
            "let item = action(\"Always Show Pill\", #selector(togglePillAlwaysVisible))",
            "item.state = enabled ? .on : .off",
            "item.toolTip = \"Off, the pill shows only while you dictate. \"",
            "+ \"In full screen it is the only way to open this menu.\"",
            "return item",
            "case .pauseMedia(let enabled):",
            "let item = action(\"Pause Media While Dictating\", #selector(togglePauseMedia))",
            "item.state = enabled ? .on : .off",
            "item.toolTip = \"Pauses the app that is playing when you start recording and plays it again when you stop. A browser tab keeps playing.\"",
            "return item",
            "case .copyLastTranscription:",
            "let item = action(\"Copy Last Transcription\", #selector(copyLastTranscript))",
            "if let lastTranscript { item.toolTip = preview(of: lastTranscript) }",
            "return item",
            "case .history(let count):",
            "let item = NSMenuItem(title: \"History (\\(count))\", action: nil, keyEquivalent: \"\")",
            "item.submenu = historyMenu()",
            "return item",
            "case .model:",
            "return disabled(\"Model: \\(modelStatus)\")",
            "case .version:",
            "return disabled(\"Version: \\(Self.buildCommit)\")",
            "case .startAtLogin(let enabled):",
            "let item = action(\"Start NeverType with macOS\", #selector(toggleLoginItem))",
            "item.state = enabled ? .on : .off",
            "return item",
            "case .loginItemTurnedOff:",
            "return disabled(\"  turned off in Login Items\")",
            "case .openLoginItems:",
            "return action(\"Open Login Items…\", #selector(openLoginItemsSettings))",
            "case .checkForUpdates:",
            "return action(\"Check for Updates…\", #selector(checkForUpdates))",
            "case .quit:",
            "return action(\"Quit NeverType\", #selector(quitNeverType), keyEquivalent: \"q\")",
            "}",
        ], "the menu items, line by line:\n\(items)")
    }

    /// The two Settings pages. Reaudit 2 of part 1b sent the Accessibility
    /// one to the Microphone page and stayed green (X-AV1).
    @Test("each Settings opener opens its own privacy page")
    func settingsPagesWiring() throws {
        let source = try Self.mainSource()
        let accessibility = try Self.body(of: "@objc private func openAccessibilitySettings() {", in: source)
        #expect(Self.codeLines(accessibility) == [
            "let url = URL(string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\")!",
            "NSWorkspace.shared.open(url)",
        ], "the Accessibility page:\n\(accessibility)")
        let microphone = try Self.body(of: "@objc private func openMicrophoneSettings() {", in: source)
        #expect(Self.codeLines(microphone) == [
            "let url = URL(string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone\")!",
            "NSWorkspace.shared.open(url)",
        ], "the Microphone page:\n\(microphone)")
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
    ///
    /// The whole body is held line by line too: audit A2 of part 1b found the
    /// branch after `runModal()` negated, or opening the other permission's
    /// page, and the gate negated, all green.
    private static func expectAlert(_ marker: String, in source: String,
                                    title: String, text: String, buttons: [String],
                                    shown: [String], logged: [String] = []) throws {
        let alert = try body(of: marker, in: source)
        let expected = ["guard permissionAlertGate.begin() else { return }",
                        "defer { permissionAlertGate.end() }"]
            + logged
            + ["NSApp.activate(ignoringOtherApps: true)",
               "let alert = NSAlert()",
               "alert.alertStyle = .warning",
               "alert.messageText = \(title)",
               "alert.informativeText = \(text)"]
            + buttons.map { "alert.addButton(withTitle: \($0))" }
            + shown
        #expect(codeLines(alert) == expected, "\(marker): the alert, line by line:\n\(alert)")
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
