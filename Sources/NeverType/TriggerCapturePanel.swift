import AppKit
import NeverTypeCore

/// The panel that waits for the next key or mouse button and turns it into a
/// trigger.
///
/// Draws and forwards, nothing else: `TriggerCapture` decides, and every
/// sentence on screen comes from there. The second window of an accessory app,
/// after the vocabulary one, and it follows the two rules that one learned:
/// activate before showing, so the keyboard reaches it, and hide the app on
/// close, so the focus goes back to where the person was.
///
/// Two monitors, the same pair as `HotkeyMonitor`. A mouse button pressed with
/// the pointer over another app's window is delivered to that app, and only
/// the global monitor sees it. A key goes to the key window, which is this
/// panel, and only the local monitor sees it. The two feed the same rule, and
/// no event arrives through both.
@MainActor
final class TriggerCapturePanel: NSObject, NSWindowDelegate {
    typealias Trigger = HotkeyMonitor.Trigger

    private var window: NSPanel?
    private let instruction = NSTextField(wrappingLabelWithString: "")
    private let accepts = NSTextField(wrappingLabelWithString: TriggerCapture.Prompt.accepts)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let useButton = NSButton(title: "", target: nil, action: nil)

    private var capture: TriggerCapture?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var idleHint: Task<Void, Never>?
    /// Accepted with a caveat: waits for the button, then becomes the trigger.
    private var pending: Trigger?
    /// The app that was in front when the panel opened, to hand the focus
    /// back to on close.
    private var previousApp: NSRunningApplication?
    private var onChosen: ((Trigger) -> Void)?
    private var onClosed: (() -> Void)?

    /// Opens the panel, or brings it to the front if it is already open.
    ///
    /// `onClosed` runs on every way out, chosen or not. It is where the app
    /// switches the trigger monitor back on, and a way out that skipped it
    /// would leave the app mute until the next launch.
    func show(purpose: TriggerCapture.Purpose,
              onChosen: @escaping (Trigger) -> Void,
              onClosed: @escaping () -> Void) {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.onChosen = onChosen
        self.onClosed = onClosed
        capture = TriggerCapture(purpose: purpose)
        pending = nil
        // Read before activating: afterwards the app in front is this one.
        previousApp = NSWorkspace.shared.frontmostApplication
        instruction.stringValue = TriggerCapture.Prompt.instruction(for: purpose)
        status.stringValue = ""
        hideUseButton()

        let window = self.window ?? makeWindow()
        self.window = window
        startListening()
        // Activate before showing, the vocabulary window's lesson: without it
        // the window of an accessory app opens behind whatever is in front and
        // gets no keyboard.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    // MARK: - Listening

    private func startListening() {
        stopListening()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp, .rightMouseDown]
        // `assumeIsolated`, and not `Task { @MainActor in }`, on purpose.
        //
        // AppKit delivers these events on the main thread: the monitors are
        // installed on the main run loop. And here order matters more than
        // purity: an asynchronous hop could process a `keyDown` after the
        // release it spoiled, turning a refused combination into an accepted
        // key. The synchronous call preserves arrival order. The same two
        // reasons as `HotkeyMonitor.start()`.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
        // The local monitor sees what is dispatched to this app, which with the
        // panel in front is every key. It returns nil for what it handled: a
        // refused key that went on to the window would beep, and the panel has
        // already said what it had to say. An event born in another app never
        // comes this way, so nothing of anyone else's is swallowed.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // `assumeIsolated` can only return a `Sendable` value, and `NSEvent`
            // is not one: the answer crosses as a Bool, and the event stays out.
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        restartIdleHint()
    }

    private func stopListening() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        idleHint?.cancel()
        idleHint = nil
    }

    /// True when the rule consumed the event.
    private func handle(_ event: NSEvent) -> Bool {
        guard var capture, let input = TriggerCapture.Input(event) else { return false }
        let verdict = capture.handle(input)
        self.capture = capture
        restartIdleHint()
        render(verdict)
        return true
    }

    /// Five seconds of nothing gets a sentence. A `Task` and a sleep, so that
    /// the hop back to the main actor is checked by the compiler, and the two
    /// monitors stay the only `assumeIsolated` in this file.
    private func restartIdleHint() {
        idleHint?.cancel()
        idleHint = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TriggerCapture.Prompt.idleDelay))
            guard !Task.isCancelled else { return }
            self?.status.stringValue = TriggerCapture.Prompt.nothingArrived
        }
    }

    // MARK: - Verdicts

    private func render(_ verdict: TriggerCapture.Verdict) {
        switch verdict {
        case .waiting:
            break
        case .refused(let refusal):
            status.stringValue = refusal.description
        case .accepted(let trigger):
            finish(with: trigger)
        // The capture stops here, so that Return is only the default button
        // and the caveat is read before the trigger counts. A second press of
        // the same key would not do: with the emoji picker still on, Fn would
        // open it twice.
        case .acceptedWithCaveat(let trigger, let caveat):
            stopListening()
            pending = trigger
            status.stringValue = caveat.description
            useButton.title = TriggerCapture.Prompt.use(trigger)
            useButton.keyEquivalent = "\r"
            useButton.isHidden = false
        case .cancelled:
            window?.close()
        }
    }

    private func finish(with trigger: Trigger) {
        stopListening()
        let chosen = onChosen
        onChosen = nil
        chosen?(trigger)
        window?.close()
    }

    private func hideUseButton() {
        useButton.isHidden = true
        useButton.keyEquivalent = ""
    }

    @objc private func useAnyway() {
        guard let pending else { return }
        finish(with: pending)
    }

    @objc private func cancel() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        stopListening()
        capture = nil
        pending = nil
        hideUseButton()
        let closed = onClosed
        onClosed = nil
        onChosen = nil
        closed?()
        // Give the focus back: an accessory app that stays active after
        // closing its window leaves the user not knowing where the keyboard
        // goes. The vocabulary window does it with `NSApp.hide(nil)`, and that
        // hides every window of this app, the orb included: after choosing a
        // key the orb was gone until the next recording (seen on 2026-09-03).
        // Handing the activation to the app that was in front returns the
        // focus and leaves the orb where it was; macOS 14 lets the active app
        // do that. Hiding stays as the fallback for when there is no such app.
        let previous = previousApp
        previousApp = nil
        if let previous, previous.activate(from: .current, options: []) { return }
        NSApp.hide(nil)
    }

    // MARK: - Building

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 212),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.title = TriggerCapture.Prompt.title
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        // A panel hides itself when the app deactivates, and a mouse button
        // pressed over another app can deactivate it. The rule keeps listening
        // through the global monitor, and a panel that vanished mid-capture
        // would look like it gave up.
        panel.hidesOnDeactivate = false

        instruction.font = .systemFont(ofSize: 13, weight: .semibold)
        instruction.frame = NSRect(x: 16, y: 172, width: 428, height: 22)
        instruction.maximumNumberOfLines = 1

        accepts.font = .systemFont(ofSize: 11)
        accepts.textColor = .secondaryLabelColor
        accepts.frame = NSRect(x: 16, y: 134, width: 428, height: 34)
        accepts.maximumNumberOfLines = 2

        status.font = .systemFont(ofSize: 12)
        status.frame = NSRect(x: 16, y: 58, width: 428, height: 70)
        status.maximumNumberOfLines = 4

        useButton.target = self
        useButton.action = #selector(useAnyway)
        useButton.bezelStyle = .rounded
        useButton.frame = NSRect(x: 224, y: 14, width: 220, height: 32)
        hideUseButton()

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 120, y: 14, width: 96, height: 32)

        for view in [instruction, accepts, status, useButton, cancel] {
            panel.contentView?.addSubview(view)
        }
        return panel
    }
}
