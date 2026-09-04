import AppKit
import AVFoundation
import NeverTypeCore

/// Where the audio of the last recording lives: a single file, overwritten on
/// every dictation. Transcription does not read from here — it uses the samples
/// kept in memory (`recorder.lastSamples`); the WAV is a debugging artifact.
///
/// It is not the only copy of what you said that stays on disk, and this comment
/// once claimed otherwise (backlog D4). In the same directory,
/// `~/Library/Application Support/NeverType/`, there are:
///
/// - `last.wav` — the audio of the last dictation, overwritten on every
///   recording. "Clear History" deletes it (since 2026-08-29; before that it was
///   left behind).
/// - `historico.json` — the last 30 transcriptions, in plain text
///   (`TranscriptHistory`). "Clear History" deletes it.
/// - `nevertype.log` — session diagnostics, truncated on every launch. Keeps the
///   time and size of each transcription, never the text (see `log(_:)`).
/// - `vocabulario.json` — the terms and replacements the user entered.
/// - `ultima-transcricao.txt`, from the previous version, is deleted on launch.
///
/// Off disk: the text goes through the clipboard to be pasted (restored
/// afterwards, marked as concealed for clipboard managers); what the user copies
/// from the menu goes without the mark (`copy(_:)`).
private func lastRecordingURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("NeverType/last.wav")
}

/// Owner of the model, loaded once and kept warm.
///
/// It is an `actor` and not a serial queue on purpose: the whisper.cpp context
/// must be used serially, and an actor makes the compiler guarantee that. A
/// serial queue would depend on me remembering to always dispatch through it.
/// `Result` requires the failure to conform to `Error`; a String does not.
struct TranscriptionFailure: Error { let reason: String }

actor TranscriptionService {
    private var transcriber: Transcriber?
    private(set) var status: String = "model not loaded yet"
    private(set) var metalActive = false
    private(set) var loadedOK = false
    private(set) var devices = ""

    func isMetalActive() -> Bool { metalActive }
    func didLoad() -> Bool { loadedOK }
    func deviceList() -> String { devices }

    /// Loads and warms up. Called once, at launch.
    func prepare() {
        let started = Date()
        do {
            let t = try Transcriber()
            let loaded = Int(Date().timeIntervalSince(started) * 1000)
            t.warmedUp = t.warmUp()
            let warmed = Int(Date().timeIntervalSince(started) * 1000)
            transcriber = t
            let warmedOK = t.warmedUp
            let gpu = t.usesMetal ? "Metal" : "CPU (SLOW)"
            status = "\(gpu) · load \(loaded) ms · warm-up \(warmed - loaded) ms"
                + (warmedOK ? "" : " (WARM-UP FAILED)")
            metalActive = t.usesMetal
            devices = t.backend
            loadedOK = true
        } catch {
            status = "\(error)"
        }
    }

    /// Returns the real error instead of `nil`.
    ///
    /// The previous version used `try?` and the delegate reported the *model
    /// load* status as if it were the cause: with the model loaded and whisper
    /// returning an error code, the user read "transcription unavailable:
    /// Metal · load 168 ms" — a message that describes health, not failure.
    func transcribe(_ samples: [Float], prompt: String? = nil) -> Result<(text: String, ms: Int), TranscriptionFailure> {
        guard let transcriber else { return .failure(TranscriptionFailure(reason: status)) }
        let started = Date()
        do {
            let text = try transcriber.transcribe(samples, prompt: prompt)
            return .success((text, Int(Date().timeIntervalSince(started) * 1000)))
        } catch {
            return .failure(TranscriptionFailure(reason: "\(error)"))
        }
    }

    func currentStatus() -> String { status }
}

/// Audible feedback for dictation actions.
///
/// The pill is draggable and may be in a corner you are not looking at — and
/// even when you are, confirming by sound is faster than checking by color.
///
/// The tones are generated, not picked from the system's: `Tink` and `Pop` are
/// alerts, designed to be noticed. Here the sound confirms an action the user
/// just took on purpose, so it needs to be the opposite of that.
///
/// The notes go down when something ends and up when something starts or locks
/// — the direction carries the meaning, so you can tell what happened without
/// learning which sound is which.
@MainActor
enum Feedback {
    private static let key = "somDasAcoes"

    /// On by default, and switchable off from the menu. A sound that cannot be
    /// turned off is a defect for anyone working in a shared room.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Generated once. Rebuilding the WAV on every dictation would redo ~7.5 KB
    /// (start and stop: 0.085 s × 44,100 Hz × 2 bytes) or ~11.5 KB (latch and
    /// discard: two notes of 0.065 s) of arithmetic for nothing.
    private static let start   = sound(Tone.wav([330], seconds: 0.085))
    private static let stop    = sound(Tone.wav([262], seconds: 0.085))
    private static let latch   = sound(Tone.wav([294, 392], seconds: 0.065))
    private static let discard = sound(Tone.wav([262, 196], seconds: 0.065))

    /// Recording started.
    ///
    /// The tone enters the audio through the speaker and comes back through the
    /// microphone, in the first ~85 ms of the recording (the duration of
    /// `start`). It is a short sine, not speech, and the bet is that Whisper
    /// ignores it — not measured (backlog I3); that is why it is short and quiet.
    static func started()   { play(start) }
    static func stopped()   { play(stop) }
    static func latched()   { play(latch) }
    static func discarded() { play(discard) }

    private static func sound(_ data: Data) -> NSSound? {
        let sound = NSSound(data: data)
        sound?.volume = 0.18
        return sound
    }

    private static func play(_ sound: NSSound?) {
        guard isEnabled, let sound else { return }
        // Rewind: `play()` on a sound that is still playing does not restart it,
        // and two dictations in a row would lose the second sound.
        sound.stop()
        sound.play()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created in applicationDidFinishLaunching, not here.
    //
    // The delegate's constructor runs before `setActivationPolicy(.accessory)`,
    // and changing the activation policy after an item already exists in the
    // menu bar gets the item discarded. The app stays alive, the object answers
    // `isVisible = true` and `frame.width = 30`, and still nothing is drawn.
    private var statusItem: NSStatusItem!
    private let monitor = HotkeyMonitor()
    private var accessibilityAlertGate = PresentationGate()
    private let recorder = AudioRecorder(destination: lastRecordingURL())
    private let menu = NSMenu()
    private let overlay = RecordingOverlay()
    private let transcription = TranscriptionService()
    private var modelStatus = "loading model…"

    /// The last transcription, kept for the menu.
    ///
    /// Resolves a tension in the spec: it says to restore the pasteboard after
    /// pasting (polite) and also not to lose the transcription if there is
    /// nowhere to paste. Together they contradict each other — restoring erases
    /// the text. Since 2026-08-30 the app does query the Accessibility API
    /// before pasting (`PasteTarget`), and that answers a different question:
    /// whether the focused element takes text, never whether the ⌘V landed.
    ///
    /// So: always restore the pasteboard, and the text stays reachable from
    /// here. Nothing is lost, and nobody's clipboard is hijacked.
    /// No longer a variable: the last one is the first in the history, and
    /// having both would create two sources of truth for the same text.
    private var lastTranscript: String? { history.last?.text }

    private let vocabulary = Vocabulary(
        url: logURL.deletingLastPathComponent().appendingPathComponent("vocabulario.json"))
    private lazy var vocabularyWindow = VocabularyWindow(vocabulary: vocabulary)

    private let history = TranscriptHistory(
        url: logURL.deletingLastPathComponent().appendingPathComponent("historico.json"))

    private static var legacyTranscriptURL: URL {
        logURL.deletingLastPathComponent().appendingPathComponent("ultima-transcricao.txt")
    }

    /// The previous version's file held the last transcription and would now
    /// never be updated again. Leaving it on disk would abandon a copy of what
    /// the user said in a file the app does not use and they do not know exists.
    private func removeLegacyTranscriptFile() {
        try? FileManager.default.removeItem(at: Self.legacyTranscriptURL)
    }

    /// Queried from the system every time, instead of kept in a variable.
    ///
    /// The previous version kept the state in a flag filled during launch, and
    /// the menu was built before that — so it showed "Microphone: missing" with
    /// the permission granted and recording working. Permission state also
    /// changes from outside, in System Settings, without telling the app.
    /// Asking is cheap and never goes stale.
    private var micAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Queried from the system every time, same as the microphone.
    ///
    /// The user turns the app off in System Settings › Login Items without the
    /// app finding out. A checkmark kept in a variable would start lying from
    /// then on — and the menu is rebuilt on every open precisely so it never
    /// shows stale state.
    private var loginItemState: LoginItem.State { LoginItem.current() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A single instance, with an atomic lock.
        //
        // The previous version queried `NSRunningApplication` and decided — two
        // steps, and the LaunchServices registration is asynchronous. In
        // simultaneous launches both instances read zero and both survived: the
        // audit reproduced it 3 out of 3. The effect is not cosmetic — two
        // global key monitors turn one dictation into two recordings, two
        // transcriptions and two ⌘V, and that is 1.1 GB of model in memory.
        //
        // `flock` solves it in one indivisible step: whoever grabs it, runs.
        guard Self.acquireInstanceLock() else {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.nevertype.app")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate()
            NSApp.terminate(nil)
            return
        }

        startLog()
        removeLegacyTranscriptFile()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)
        // The menu rebuilds itself when opened (menuNeedsUpdate), so it never
        // shows stale state.
        menu.delegate = self
        statusItem.menu = menu
        // The same object, so a click on the orb opens the menu that was just
        // rebuilt. It is the only way to reach the menu in full screen, where
        // macOS hides the menu bar and the icon with it.
        overlay.menu = menu

        if let saved = HotkeyMonitor.Trigger.named(UserDefaults.standard.string(forKey: Self.triggerKey)) {
            monitor.trigger = saved
        }
        monitor.handsFreeEnabled = Self.handsFreeIsOn
        monitor.onEvent = { [weak self] event in self?.handle(event) ?? false }
        recorder.onLevel = { [weak self] level in self?.overlay.push(level: level) }
        recorder.onError = { [weak self] message in
            self?.overlay.hide()
            self?.render(.blocked)
            self?.log(message)
        }
        monitor.start()
        // Always on screen: an accessory app that dies changes nothing visually,
        // so the idle pill is the only sign that it is still alive.
        overlay.showIdle()
        // After the orb exists, since one of the two hints lives on it.
        refreshHoverHint()

        requestMicrophoneAccess()
        warnIfAccessibilityMissing()

        // Load and warm up off the main thread: it is hundreds of MB and a
        // throwaway inference. Blocking here would freeze the menu bar.
        Task {
            await transcription.prepare()
            let status = await transcription.currentStatus()
            self.modelStatus = status
            self.log("model: \(status)")
            // The Metal warning only applies if the model loaded. Before, a
            // missing model also triggered "no Metal" — sending whoever was
            // debugging in the wrong direction.
            if await self.transcription.didLoad() {
                self.log("ggml devices: \(await self.transcription.deviceList())")
                if await !self.transcription.isMetalActive() {
                    self.log("WARNING: without Metal, transcription runs on the CPU and is ~11x slower.")
                    self.render(.blocked)
                }
            } else {
                self.render(.blocked)
            }
        }
        log("ready. trigger: \(monitor.trigger.label) · hands-free: \(monitor.handsFreeEnabled ? "on" : "off")")
        // The two insertion preferences have no menu item, so this line is how
        // you confirm that a `defaults write` took effect. Effective values, not
        // what is stored: both are read through the rule that bounds them.
        log("insertion: clipboard given back after \(TextInjector.restoreDelay) s · focus checked before pasting: \(PasteTarget.isCheckEnabled ? "yes" : "no")")
    }

    // MARK: - Visual states

    private enum Visual { case idle, recording, blocked }

    private func render(_ state: Visual) {
        guard let button = statusItem.button else {
            log("NO BUTTON on the status item — nowhere to draw the icon")
            return
        }
        let style: BrandMark.StatusStyle
        let accessibilityValue: String
        switch state {
        // Shape carries the state at menu bar scale. The brand is idle, a live
        // waveform is recording, and the slashed brand means attention needed.
        case .idle:
            style = .idle
            accessibilityValue = "Ready"
        case .recording:
            style = .recording
            accessibilityValue = "Listening"
        case .blocked:
            style = .blocked
            accessibilityValue = "Needs attention"
        }
        // Template images let macOS keep the custom mark legible on every menu
        // bar background. The approved identity is monochrome in every state.
        let image = BrandMark.statusImage(style)
        button.image = image
        button.contentTintColor = nil
        button.title = ""
        button.setAccessibilityLabel("NeverType")
        button.setAccessibilityValue(accessibilityValue)
        log("icon → \(style.logName) (monochrome), template=\(image.isTemplate), width=\(button.frame.width)")
    }

    // MARK: - Dictation cycle

    /// Returns whether a `.pressed` event started recording. The monitor uses a
    /// refusal to reset its own latch before the release can arm hands-free.
    @discardableResult
    private func handle(_ event: HotkeyMonitor.Event) -> Bool {
        switch event {
        case .pressed:
            switch DictationAttempt.decide(
                microphoneAuthorized: micAuthorized,
                accessibilityAuthorized: HotkeyMonitor.hasAccessibilityPermission
            ) {
            case .showAccessibilityWarning:
                render(.blocked)
                log("Accessibility not granted: recording blocked before capturing audio")
                // Return the rejection before entering AppKit's nested modal loop.
                // The monitor resets its latch synchronously from this result;
                // only the next main-actor turn is allowed to present the alert.
                Task { @MainActor [weak self] in
                    self?.showAccessibilityRequiredAlert()
                }
                return false
            case .showMicrophoneWarning:
                render(.blocked)
                log("microphone not authorized — dictation ignored")
                return false
            case .startRecording:
                break
            }
            do {
                try recorder.start()
                Feedback.started()
                render(.recording)
                overlay.show()
                return true
            } catch {
                render(.blocked)
                log("failed to start recording: \(error)")
                return false
            }
        case .released:
            guard recorder.isRecording else { return false }
            Feedback.stopped()
            let url = recorder.stop()
            render(.idle)
            guard url != nil else {
                overlay.hide()
                return false
            }
            // The pill stays on screen saying "working" until the text comes
            // out. Before, it went back to idle here, and the app spent the
            // whole transcription with no sign of what was happening.
            overlay.transcribing()
            let samples = recorder.lastSamples
            log("recorded: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16_000)) s)")
            Task {
                switch await self.transcription.transcribe(samples, prompt: self.vocabulary.prompt) {
                case .success(let result):
                    // The replacements run here, on the finished text: they are
                    // deterministic and do not go through the model.
                    let corrected = self.vocabulary.apply(to: result.text)
                    // Time and size, never the text. Until 2026-08-29 these lines
                    // wrote the whole transcription to `nevertype.log` — a copy
                    // on disk that no doc mentioned and that "Clear History"
                    // does not delete. The "transcribed in N ms" prefix stays:
                    // it is what the backlog's latency measurement reads.
                    var line = "transcribed in \(result.ms) ms: \(result.text.count) chars"
                    if corrected != result.text {
                        line += ", \(corrected.count) after replacements"
                    }
                    self.log(line)
                    self.overlay.hide()
                    self.deliver(corrected)
                case .failure(let failure):
                    // Visible signal: without this the dictation vanished in
                    // silence — the icon is already back to normal, the app has
                    // no window, and stderr goes nowhere when opened from Finder.
                    self.log("TRANSCRIPTION FAILED: \(failure.reason)")
                    self.overlay.hide()
                    self.render(.blocked)
                }
            }
            return true
        case .latched:
            // The recording has been running since the first tap; here only
            // what keeps it alive changes — the state machine, not the key.
            Feedback.latched()
            overlay.latch()
            log("hands-free locked. Tap \(monitor.trigger.label) to transcribe, Esc to discard.")
            return true
        case .cancelled:
            discardRecording(reason: "regular key pressed during the hold")
            return true
        }
    }

    /// Throws the running recording away: the tone, the pill and the icon all
    /// go back to rest, and the audio is not transcribed.
    private func discardRecording(reason: String) {
        Feedback.discarded()
        recorder.cancel()
        overlay.hide()
        render(.idle)
        log("cancelled: \(reason)")
    }

    /// Ends a recording whose gesture the monitor has just thrown away.
    ///
    /// Switching the key or hands-free resets the state machine, and the
    /// recording that gesture had started would go on with nothing able to stop
    /// it: hands-free holds no key to release, and the reset already took the
    /// state a tap would have finished. Reachable from the menu, which is open
    /// during a hands-free recording precisely when somebody locked by accident
    /// and is looking for the way out. Not watched happening: the app was built,
    /// installed and exercised by hand on 2026-09-01, and switching hands-free
    /// off in the middle of a recording is the path nobody walked in that pass.
    private func endOrphanRecording(_ reason: String) {
        guard recorder.isRecording else { return }
        discardRecording(reason: reason)
    }

    /// Puts the text where the cursor is.
    private func deliver(_ text: String) {
        guard !text.isEmpty else {
            log("empty transcription — nothing to insert")
            return
        }
        history.add(text)

        switch TextInjector.insert(text) {
        case .inserted:
            break
        case .blockedBySecureInput:
            // `IsSecureEventInputEnabled()` is a session-wide flag, not "password
            // field in focus": some process turned secure input on — a password
            // field is the common case, but any app can turn it on, including in
            // the background, and some forget to turn it off. While it is on the
            // app does not post the ⌘V (whether refusing is right is under
            // discussion in backlog D3); the text stays on the clipboard and in
            // the menu.
            log("secure input is on for this session — did not paste. Some process turned it on (a password field in focus is the common case, but some apps leave it on). The text is on the clipboard and in the menu, under \"Copy Last Transcription\".")
            render(.blocked)
            flashIdle()
        case .noEditableField(let role):
            // The same three signals as any other insertion failure: the 2 s
            // slash, the line here, and the text reachable from the menu (it
            // went into the history above). The message names the way out,
            // because this is the path that can be wrong on an app nobody here
            // has tried: if it refuses where you can type, the key turns the
            // check off and the app goes back to pasting blindly.
            log("the focused element takes no text (\(role)). Did not paste, so the ⌘V would not become a shortcut in the app in front. The text is on the clipboard and in the menu, under \"Copy Last Transcription\". To turn this check off: defaults write com.nevertype.app \(PasteTarget.checkKey) -bool false")
            render(.blocked)
            flashIdle()
        case .failed(let reason):
            log("could not insert: \(reason). The text is in the menu.")
            render(.blocked)
            flashIdle()
        }
    }

    /// Back to the normal icon after signaling a problem, so the app does not
    /// stay stuck in an error state because of one dictation.
    private func flashIdle() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !self.recorder.isRecording { self.render(.idle) }
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// A menu line cannot hold a whole dictation; the full text goes in the
    /// tooltip and reaches the pasteboard on click.
    private func preview(of text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 44 ? String(flat.prefix(44)) + "…" : flat
    }

    @objc private func copyFromHistory(_ sender: NSMenuItem) {
        guard history.entries.indices.contains(sender.tag) else { return }
        copy(history.entries[sender.tag].text)
    }

    private static let triggerKey = "trigger"
    private static let handsFreeKey = "handsFree"

    /// On by default, because locking with two taps is what the app has always
    /// done. A preference arriving to turn a working gesture off would be a
    /// change nobody asked for. Same shape as the sounds toggle: absent means
    /// on, and only an explicit `false` turns it off.
    private static var handsFreeIsOn: Bool {
        UserDefaults.standard.object(forKey: handsFreeKey) as? Bool ?? true
    }

    /// What the pointer gets for standing still on the icon or on the orb.
    ///
    /// The menu teaches the gesture now, and reading a menu means having already
    /// found that there is a menu. This line is the one that reaches somebody
    /// who has never clicked either of the two, and it costs no line in the menu.
    private var hoverHint: String {
        "NeverType. Hold \(monitor.trigger.label) to dictate. Click for the menu."
    }

    private func refreshHoverHint() {
        statusItem.button?.toolTip = hoverHint
        overlay.hint = hoverHint
    }

    /// The commit this binary was built from, stamped by `build-app.sh`.
    ///
    /// Lives in the menu so the question "which version do I have?" has an
    /// answer without a terminal — and it is the same value `update.sh`
    /// compares to decide whether there is work to do.
    private static var buildCommit: String {
        Bundle.main.object(forInfoDictionaryKey: "NeverTypeCommit") as? String ?? "unknown"
    }

    @objc private func openVocabulary() {
        vocabularyWindow.show()
    }

    /// The key already chosen is left alone. Picking it again would rewrite the
    /// same value and, through `endOrphanRecording`, throw away a hands-free
    /// recording that nothing about the app had changed.
    @objc private func chooseTrigger(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let option = HotkeyMonitor.Trigger.named(id),
              option != monitor.trigger else { return }
        monitor.trigger = option
        UserDefaults.standard.set(id, forKey: Self.triggerKey)
        endOrphanRecording("the trigger key changed while recording")
        refreshHoverHint()
        log("trigger is now \(option.label)")
    }

    @objc private func toggleHandsFree() {
        monitor.handsFreeEnabled.toggle()
        UserDefaults.standard.set(monitor.handsFreeEnabled, forKey: Self.handsFreeKey)
        endOrphanRecording("hands-free switched with a recording running")
        log("hands-free: \(monitor.handsFreeEnabled ? "on" : "off")")
    }

    @objc private func toggleSound() {
        Feedback.isEnabled.toggle()
        log("sounds: \(Feedback.isEnabled ? "on" : "off")")
    }

    @objc private func clearHistory() {
        history.clear()
        // The audio is the other copy of what the user said, and it is the whole
        // recording. Until 2026-08-29 this item deleted only the text and left
        // `last.wav` behind. In hands-free mode the menu opens with a recording
        // in progress: then the open file is the current dictation's, and the
        // recorder refuses to delete it.
        if recorder.discardLastRecording() {
            log("history cleared, and last.wav with it")
        } else {
            log("history cleared; last.wav kept — a recording is in progress")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyLastTranscript() {
        guard let lastTranscript else { return }
        copy(lastTranscript)
        log("last transcription copied")
    }

    // MARK: - Permissions

    private func requestMicrophoneAccess() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            if !micAuthorized { render(.blocked) }
            return
        }
        // The async API, not the closure one.
        //
        // A closure written inside a `@MainActor` method **inherits** that
        // isolation by inference, and Swift inserts a runtime check. The TCC
        // callback arrives on a background queue, the check fails and the
        // process dies — that is what crashed the app twice. Swapping the body
        // for `Task { @MainActor in }` did not fix it: the check trips in the
        // outer closure, before reaching the body.
        //
        // With `await` there is no closure to inherit isolation, and resumption
        // happens on the main actor by construction.
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            self.render(granted ? .idle : .blocked)
        }
    }

    /// Without Accessibility, the global monitors may still receive the modifier
    /// event, but the synthetic paste cannot be posted. Checking only at launch
    /// allowed a full recording and transcription to finish before apparently
    /// doing nothing. The trigger now checks again; this launch warning remains
    /// the first chance to explain what is missing.
    private func warnIfAccessibilityMissing() {
        guard !HotkeyMonitor.hasAccessibilityPermission else { return }
        render(.blocked)
        log("Accessibility not granted: dictation is blocked until it is enabled.")
        HotkeyMonitor.requestAccessibilityPermission()
    }

    /// A trigger is an attempted action, so a changed icon or a menu line is not
    /// enough feedback. This alert says that recording did not start and offers
    /// the exact repair path instead of letting the user discover the permission
    /// only after reading diagnostics elsewhere.
    private func showAccessibilityRequiredAlert() {
        guard accessibilityAlertGate.begin() else { return }
        defer { accessibilityAlertGate.end() }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NeverType needs Accessibility access"
        alert.informativeText = "Recording did not start. Enable NeverType in System Settings › Privacy & Security › Accessibility, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    // MARK: - Menu

    /// Rebuilt from scratch on every opening, from the state of that moment.
    ///
    /// Which lines exist is decided by `MenuLayout`, which knows no AppKit; this
    /// method only turns each line into an `NSMenuItem`.
    private func rebuildMenu() {
        menu.removeAllItems()
        let loginState = loginItemState
        let conditions = MenuLayout.Conditions(
            microphoneAuthorized: micAuthorized,
            accessibilityAuthorized: HotkeyMonitor.hasAccessibilityPermission,
            // Read here, in the rebuild, because this is the one moment the
            // contents are decided. Holding Option after the menu is already
            // open changes nothing, and `docs/reference.md` says so.
            //
            // The alternative, `isAlternate` with a `keyEquivalentModifierMask`,
            // does follow the key live, and it swaps items in pairs: each hidden
            // line would need a visible line in its place, which is the wall of
            // text this menu just stopped opening with.
            showsDiagnostics: NSEvent.modifierFlags.contains(.option),
            historyCount: history.entries.count,
            triggerLabel: monitor.trigger.label,
            handsFreeEnabled: monitor.handsFreeEnabled,
            startsAtLogin: loginState == .on,
            loginItemNeedsApproval: loginState == .needsApproval)

        for row in MenuLayout.rows(for: conditions) {
            menu.addItem(item(for: row))
        }
    }

    private func item(for row: MenuLayout.Row) -> NSMenuItem {
        switch row {
        case .separator:
            return .separator()

        case .accessibilityMissing:
            return disabled("Accessibility: missing")

        case .openAccessibilitySettings:
            return action("Open Accessibility Settings…", #selector(openAccessibilitySettings))

        case .microphoneMissing:
            return disabled("Microphone: missing")

        case .trigger:
            return disabled("Trigger: \(monitor.trigger.label) (hold and speak)")

        case .gestureHint:
            return disabled("  double-tap locks · tap to finish · Esc discards")

        // The title names the key in use, so the line teaches the gesture to
        // whoever opened the menu for something else entirely.
        case .hotkey(let trigger):
            let item = NSMenuItem(title: "Hotkey: \(trigger)", action: nil, keyEquivalent: "")
            item.submenu = hotkeyMenu()
            return item

        // Off, the title stops advertising a gesture that no longer locks.
        case .handsFree(let enabled):
            let item = NSMenuItem(title: enabled ? "Hands-free: double tap" : "Hands-free: off",
                                  action: nil,
                                  keyEquivalent: "")
            item.submenu = handsFreeMenu(enabled: enabled)
            return item

        case .vocabulary:
            let counts = vocabulary.terms.count + vocabulary.replacements.count
            let title = counts > 0
                ? "Vocabulary (\(vocabulary.terms.count) terms, \(vocabulary.replacements.count) replacements)…"
                : "Vocabulary…"
            return action(title, #selector(openVocabulary))

        case .copyLastTranscription:
            let item = action("Copy Last Transcription", #selector(copyLastTranscript))
            if let lastTranscript { item.toolTip = preview(of: lastTranscript) }
            return item

        case .history(let count):
            let item = NSMenuItem(title: "History (\(count))", action: nil, keyEquivalent: "")
            item.submenu = historyMenu()
            return item

        case .model:
            return disabled("Model: \(modelStatus)")

        case .version:
            return disabled("Version: \(Self.buildCommit)")

        case .startAtLogin(let enabled):
            let item = action("Start NeverType with macOS", #selector(toggleLoginItem))
            item.state = enabled ? .on : .off
            return item

        // The item speaks this app's language; the notice speaks Apple's, which
        // is what the user will search for when looking for where to turn it back on.
        case .loginItemTurnedOff:
            return disabled("  turned off in Login Items")

        case .openLoginItems:
            return action("Open Login Items…", #selector(openLoginItemsSettings))

        case .quit:
            // The app's own selector instead of `terminate:`, which is what
            // macOS 26 recognizes as the standard Quit command and draws a
            // symbol next to. It was the only icon in the whole menu, and a menu
            // with one icon looks like a menu missing fifteen. Routing through
            // this app's method leaves AppKit no standard command to recognize.
            // Confirmed in use on 2026-09-01: the build that was approved came
            // up with no icon anywhere in the menu.
            return action("Quit NeverType", #selector(quitNeverType), keyEquivalent: "q")
        }
    }

    private func hotkeyMenu() -> NSMenu {
        let keyMenu = NSMenu()
        for option in HotkeyMonitor.Trigger.menuChoices(current: monitor.trigger) {
            let line = action(option.label, #selector(chooseTrigger(_:)))
            line.state = option == monitor.trigger ? .on : .off
            line.representedObject = option.id
            keyMenu.addItem(line)
        }
        keyMenu.addItem(.separator())
        let soundItem = action("Sounds", #selector(toggleSound))
        soundItem.state = Feedback.isEnabled ? .on : .off
        keyMenu.addItem(soundItem)
        return keyMenu
    }

    /// The whole hands-free cycle, one submenu deep.
    ///
    /// Grey text is allowed down here. This submenu is opened on purpose, by
    /// somebody looking for what the item means. The menu above it opens for
    /// anyone copying a transcription, which is where a wall of text was the
    /// verdict.
    ///
    /// The switch comes first, ahead of what cannot be clicked, and its
    /// checkmark is already the answer to "is this on?".
    private func handsFreeMenu(enabled: Bool) -> NSMenu {
        let submenu = NSMenu()
        let toggle = action("Hands-free", #selector(toggleHandsFree))
        toggle.state = enabled ? .on : .off
        submenu.addItem(toggle)
        submenu.addItem(.separator())
        if enabled {
            submenu.addItem(disabled("Double-tap \(monitor.trigger.label) to lock"))
            submenu.addItem(disabled("Tap once to finish · Esc discards"))
            submenu.addItem(disabled("Typing does not cancel while locked"))
        } else {
            submenu.addItem(disabled("\(monitor.trigger.label) only records while held"))
        }
        return submenu
    }

    private func historyMenu() -> NSMenu {
        let submenu = NSMenu()
        for (index, entry) in history.entries.enumerated() {
            let line = action("\(Self.clock.string(from: entry.date))  \(preview(of: entry.text))",
                              #selector(copyFromHistory(_:)))
            line.tag = index
            line.toolTip = entry.text
            submenu.addItem(line)
        }
        submenu.addItem(.separator())
        submenu.addItem(action("Clear History", #selector(clearHistory)))
        return submenu
    }

    /// Every clickable item carries its own target.
    ///
    /// Not for tidiness: the menu is also opened from the orb, whose panel is
    /// non-activating, and an item with no target has to find its action by
    /// walking a responder chain that starts somewhere else. With the target
    /// set, the item calls this object and the click lands the same from both
    /// places.
    private func action(_ title: String, _ selector: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func quitNeverType() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        let outcome = loginItemState == .on ? LoginItem.disable() : LoginItem.enable()
        switch outcome {
        case .changed(let state):
            log("open at login: \(state)")
        case .refused(let reason):
            // Visible signal, not just log. The menu has already closed when
            // this happens, the app has no window, and stderr goes nowhere when
            // it is opened from Finder: without the icon, the refusal would not
            // reach the user.
            log("could not change 'open at login': \(reason)")
            render(.blocked)
            flashIdle()
        }
    }

    @objc private func openLoginItemsSettings() {
        LoginItem.openSettings()
    }

    /// The app's diary.
    ///
    /// Writes to stderr and to a file. Opened from Finder, the app's stderr goes
    /// nowhere — which is why three bugs in a row (the discarded icon, the crash
    /// on the permission and the black icon on a black background) had to be
    /// diagnosed by looking at the screen instead of reading a log.
    /// Truncated on every launch: it is diagnostics for the current session, not
    /// history.
    ///
    /// Never receives transcription, history or vocabulary text: the file stays
    /// on disk and "Clear History" does not touch it, so any text here would be
    /// a copy of what the user said beyond their reach. Only time, size and state.
    private func log(_ message: String) {
        let line = "nevertype: \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard let handle = try? FileHandle(forWritingTo: Self.logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Kept open for the life of the process: closing releases the lock.
    private nonisolated(unsafe) static var instanceLock: CInt = -1

    private static func acquireInstanceLock() -> Bool {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(".instance.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        // If the lock cannot be opened, better to let the app run than to hang
        // because of a file.
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        instanceLock = fd
        return true
    }

    static let logURL = lastRecordingURL()
        .deletingLastPathComponent()
        .appendingPathComponent("nevertype.log")

    private func startLog() {
        try? FileManager.default.createDirectory(
            at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// The orb rests above every window and a menu does not, so it steps down
    /// while one is open. The reason, with the three window levels, is in
    /// `RecordingOverlay.menuOpenLevel`.
    func menuWillOpen(_ menu: NSMenu) {
        overlay.menuOpened()
    }

    func menuDidClose(_ menu: NSMenu) {
        overlay.menuClosed()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon. Lives in the menu bar; the only windows are the pill
// (an `NSPanel`, in RecordingOverlay) and the vocabulary one (VocabularyWindow).
app.setActivationPolicy(.accessory)
app.run()
