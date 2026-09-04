import AppKit
import NeverTypeCore

/// The panel that waits for the next key or mouse button and turns it into a
/// trigger.
///
/// Draws and forwards, nothing else: `TriggerCapture` decides, and every
/// sentence on screen comes from there. The second window of an accessory app,
/// after the vocabulary one, and it follows the two rules that one learned:
/// activate before showing, so the keyboard reaches it, and hand the focus back
/// on close, through `FocusHandback`, so the person returns to where they were
/// with the orb still on screen.
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
    /// Where the focus goes back to when the panel closes.
    private let focus = FocusHandback()
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
        // Everything is rebuilt on every call, even with the panel already
        // open. The menu stays reachable while it is, so the other role can be
        // asked for from under it; an early return here kept the first role's
        // rule and callback, and the key pressed for hands-free became the
        // trigger.
        let wasVisible = window?.isVisible == true
        self.onChosen = onChosen
        self.onClosed = onClosed
        capture = TriggerCapture(purpose: purpose)
        pending = nil
        // Read before activating, and only on the way in: afterwards the app in
        // front is this one, so a second `show` on an open panel would remember
        // NeverType itself.
        if !wasVisible { focus.remember() }
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
        if !wasVisible { window.center() }
    }

    // MARK: - Listening

    private func startListening() {
        stopListening()
        // Two masks, because the two monitors see different things. A key goes
        // to the key window, which is this panel, so the keyboard belongs to
        // the local monitor alone: with the panel open behind another app, a
        // solo modifier tapped in that app would otherwise choose the trigger
        // and close the panel with nothing on screen to explain it. Every click
        // is global, since a click over another app's window is delivered
        // there. The primary click is the exception the local monitor cannot
        // take: it is how the buttons in this panel are pressed.
        let global: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp, .rightMouseDown, .leftMouseDown]
        let local: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp, .rightMouseDown]
        // `assumeIsolated`, and not `Task { @MainActor in }`, on purpose.
        //
        // AppKit delivers these events on the main thread: the monitors are
        // installed on the main run loop. And here order matters more than
        // purity: an asynchronous hop could process a `keyDown` after the
        // release it spoiled, turning a refused combination into an accepted
        // key. The synchronous call preserves arrival order. The same two
        // reasons as `HotkeyMonitor.start()`.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: global) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
        // The local monitor sees what is dispatched to this app, which with the
        // panel in front is every key. It returns nil for what it handled: a
        // refused key that went on to the window would beep, and the panel has
        // already said what it had to say. An event born in another app never
        // comes this way, so nothing of anyone else's is swallowed.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: local) { [weak self] event in
            // `assumeIsolated` can only return a `Sendable` value, and `NSEvent`
            // is not one: the answer crosses as a Bool, and the event stays out.
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        armIdleHint()
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
        // The hint answers a panel nothing ever reached, so the first event
        // retires it for good. Restarting it here overwrote a refusal five
        // seconds later with a sentence about firmware and mouse software that
        // had nothing to do with what the person had just pressed.
        idleHint?.cancel()
        idleHint = nil
        render(verdict)
        return true
    }

    /// Five seconds of nothing gets a sentence. A `Task` and a sleep, so that
    /// the hop back to the main actor is checked by the compiler, and the two
    /// monitors stay the only `assumeIsolated` in this file.
    private func armIdleHint() {
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
        // goes. This panel is where hiding the app was first seen taking the
        // orb with it (2026-09-03); `FocusHandback` says why, and what it does
        // instead.
        focus.giveBack()
    }

    // MARK: - Building

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 232),
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

        // Two lines, because one does not hold the hands-free sentence: at 13
        // pt semibold it measures 547 px against the label's 428, and what was
        // cut was `tap again to finish`, the half that teaches the gesture.
        instruction.font = .systemFont(ofSize: 13, weight: .semibold)
        instruction.frame = NSRect(x: 16, y: 178, width: 428, height: 40)
        instruction.maximumNumberOfLines = 2

        accepts.font = .systemFont(ofSize: 11)
        accepts.textColor = .secondaryLabelColor
        accepts.frame = NSRect(x: 16, y: 138, width: 428, height: 34)
        accepts.maximumNumberOfLines = 2

        status.font = .systemFont(ofSize: 12)
        status.frame = NSRect(x: 16, y: 54, width: 428, height: 76)
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
