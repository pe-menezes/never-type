import AppKit

/// Gives the focus back to the app that was in front before one of this app's
/// windows opened.
///
/// An accessory app that stays active after closing its window leaves the
/// person not knowing where the keyboard goes. `NSApp.hide(nil)` answers that,
/// and it also hides every window of this app, the orb included: closing the
/// vocabulary window made the orb vanish until the next recording, seen on
/// 2026-09-03 through the capture panel, which had copied the line. Handing the
/// activation to the app that was in front returns the focus and leaves the
/// orb where it was; macOS 14 lets the active app do that. Hiding stays as the
/// fallback for when there is no such app, or it refuses.
///
/// The system calls enter as parameters with defaults, the same shape as
/// `TextInjector.insert(secureInput:)`, so every branch runs in a test without
/// activating or hiding anything.
@MainActor
public final class FocusHandback {
    private let frontmost: (@MainActor () -> pid_t?)?
    private let activate: (@MainActor (pid_t) -> Bool)?
    private let hide: (@MainActor () -> Void)?
    private let isActive: (@MainActor () -> Bool)?
    private let own: pid_t
    private var remembered: pid_t?

    /// Every system call enters as a parameter with a default, so the tests
    /// exercise each branch without activating or hiding anything. `own` is
    /// this process, the one app the hand-back must never activate.
    public init(frontmost: (@MainActor () -> pid_t?)? = nil,
                activate: (@MainActor (pid_t) -> Bool)? = nil,
                hide: (@MainActor () -> Void)? = nil,
                isActive: (@MainActor () -> Bool)? = nil,
                own: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.frontmost = frontmost
        self.activate = activate
        self.hide = hide
        self.isActive = isActive
        self.own = own
    }

    /// Reads which app is in front. Call before activating this app:
    /// afterwards the app in front is this one, and there would be nothing to
    /// give the focus back to.
    public func remember() {
        remembered = (frontmost ?? Self.systemFrontmost)()
    }

    /// Hands the activation to the remembered app. Returns false when it hid
    /// this app instead, which happens with nothing remembered, with this app
    /// itself remembered, or with an activation the system refused. Forgets the
    /// app either way: a stale one would send the focus to a window the person
    /// left long ago.
    ///
    /// With this app no longer in front there is nothing to hand back, and
    /// doing it anyway would pull the person out of wherever they went while
    /// the window was open. `activate` reports that the request was allowed,
    /// which is not a promise that the app comes forward; there is no call that
    /// promises more.
    @discardableResult
    public func giveBack() -> Bool {
        defer { remembered = nil }
        guard (isActive ?? Self.systemIsActive)() else { return true }
        if let pid = remembered, pid != own, (activate ?? Self.systemActivate)(pid) {
            return true
        }
        (hide ?? Self.systemHide)()
        return false
    }

    private static func systemFrontmost() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private static func systemActivate(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate(from: .current, options: []) ?? false
    }

    private static func systemHide() {
        NSApp.hide(nil)
    }

    private static func systemIsActive() -> Bool {
        NSApp.isActive
    }
}
