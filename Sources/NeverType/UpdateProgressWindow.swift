import AppKit
import NeverTypeCore

/// Shows what `AutoUpdater` is doing while it fetches, rebuilds and
/// reinstalls.
///
/// On the path that succeeds, this window does not close itself: the app it
/// belongs to dies partway through, killed by `install.sh`'s own `pkill` as
/// part of the reinstall, and the newly installed copy opens moments later
/// with no memory of this window ever existing. That is expected, not a bug
/// to route around — it is the same "closes and reopens" every ordinary Mac
/// app auto-updater does. This window only ever gets to show a *finished*
/// state on the path that fails before reaching that point: a bad fetch,
/// uncommitted local changes, a diverged branch, or a build error, all of
/// which exit before `install.sh` runs.
@MainActor
final class UpdateProgressWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var statusField: NSTextField!
    private var spinner: NSProgressIndicator!
    private var closeButton: NSButton!
    /// Where the focus goes back to when the window closes, the same idiom
    /// `VocabularyWindow` and `TriggerCapturePanel` use.
    private let focus = FocusHandback()

    func show() {
        if panel?.isVisible != true { focus.remember() }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        closeButton.isHidden = true
        spinner.startAnimation(nil)
        statusField.stringValue = "Checking for updates…"
        // Activate before showing: an accessory app's window opens behind
        // whatever is in front and gets no keyboard otherwise, the same rule
        // as `VocabularyWindow.show()`.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.center()
    }

    /// A line from the update log, ANSI codes already stripped by the caller.
    func report(status: String) {
        guard !status.isEmpty else { return }
        statusField.stringValue = status
    }

    /// Reached only on the failure path — see the type's doc comment.
    func reportFailure(status: String) {
        spinner.stopAnimation(nil)
        statusField.stringValue = status
        closeButton.isHidden = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.title = "Updating NeverType"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        // Stays visible even if this isn't the frontmost app for a moment —
        // the update can take a while, and it shouldn't vanish because focus
        // moved, the same reason `TriggerCapturePanel` sets this.
        panel.hidesOnDeactivate = false

        let content = panel.contentView!

        let spinner = NSProgressIndicator(frame: NSRect(x: 160, y: 70, width: 40, height: 40))
        spinner.style = .spinning
        spinner.isIndeterminate = true
        content.addSubview(spinner)
        self.spinner = spinner

        let status = NSTextField(labelWithString: "")
        status.frame = NSRect(x: 20, y: 40, width: 320, height: 20)
        status.alignment = .center
        status.lineBreakMode = .byTruncatingTail
        content.addSubview(status)
        self.statusField = status

        let close = NSButton(title: "Close", target: self, action: #selector(closePanel))
        close.frame = NSRect(x: 280, y: 12, width: 60, height: 24)
        close.bezelStyle = .rounded
        close.isHidden = true
        content.addSubview(close)
        self.closeButton = close

        return panel
    }

    @objc private func closePanel() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        focus.giveBack()
    }
}
