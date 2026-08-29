import Foundation
import ServiceManagement

/// Turns NeverType on and off as a macOS login item.
///
/// `SMAppService` registers **the bundle that is running**, and BTM indexes that
/// registration by bundle ID, not by path. Measured on 2026-08-28 (macOS 26.2)
/// with an app proxy signed with the same identity and the same hardened
/// runtime: registered from `/private/tmp/...`, the copy in `/Applications` —
/// another path, same bundle ID — answered `status == .enabled`. And the
/// temporary bundle's `register()` threw no error at all.
///
/// That is: the only two signals the API offers say "all good" about a bundle in
/// a temporary folder. That is why the path guard runs **before** registering —
/// afterwards there is no question that returns the answer.
public enum LoginItem {

    /// What the system answers about opening the app at login.
    public enum State: Equatable, CustomStringConvertible {
        /// Opens at login.
        case on
        /// Does not open. Collapses `notRegistered` (never registered) and
        /// `notFound` (registered and later gone from BTM): they are distinct
        /// `SMAppService` cases, but the interface has nothing different to do
        /// with them — both mean "does not open".
        case off
        /// Registered, and turned off by the user in System Settings. Does not
        /// collapse into `off` because the way out is different: no click here
        /// fixes it, the action is outside the app.
        case needsApproval

        public var description: String {
            switch self {
            case .on:            return "on"
            case .off:           return "off"
            case .needsApproval: return "turned off in System Settings"
            }
        }
    }

    /// The result of trying to change the state.
    ///
    /// `refused` carries the reason already worded for the user, with the way
    /// out inside it — the app is accessory and has no window to explain later.
    public enum Outcome: Equatable {
        case changed(State)
        case refused(String)
    }

    /// The two places from which registering is valid.
    ///
    /// `~/Applications` is not a whim: `install.sh` documents that fallback for
    /// managed machines or users without admin rights, where `/Applications` is
    /// not writable. A guard that only accepted `/Applications` would leave that
    /// person with no way to turn the option on.
    private static let bundleName = "NeverType.app"

    /// The rule itself, separated from any query to the system.
    ///
    /// Pure on purpose, like `ModelStore.isValid(magic:size:)`: every branch can
    /// be exercised without assembling any bundle on disk.
    public static func isInstalledLocation(bundlePath: String, home: String) -> Bool {
        let path = withoutTrailingSlash(bundlePath)
        let home = withoutTrailingSlash(home)
        return path == "/Applications/\(bundleName)"
            || path == "\(home)/Applications/\(bundleName)"
    }

    /// Translates the system's answer into what the interface needs to know.
    public static func state(from status: SMAppService.Status) -> State {
        switch status {
        case .enabled:                  return .on
        case .requiresApproval:         return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default:               return .off
        }
    }

    /// The current state, queried from the system.
    ///
    /// Called every time the menu is rebuilt, never stored: the user turns the
    /// app off in System Settings without telling anyone, and a checkmark kept
    /// in a variable would start lying from then on.
    public static func current(status: (() -> SMAppService.Status)? = nil) -> State {
        state(from: (status ?? systemStatus)())
    }

    /// Registers the app to open at login.
    ///
    /// Refuses outside the installed location. Without that refusal, turning the
    /// option on while running `build/NeverType.app` would register the
    /// repository's copy — which `build-app.sh` rebuilds from scratch on every
    /// build — and neither `status` nor `register()` would complain.
    public static func enable(
        bundlePath: String = Bundle.main.bundlePath,
        home: String = NSHomeDirectory(),
        register: (() throws -> Void)? = nil,
        status: (() -> SMAppService.Status)? = nil
    ) -> Outcome {
        guard isInstalledLocation(bundlePath: bundlePath, home: home) else {
            return .refused("""
                this copy is at \(bundlePath), and only the installed one opens at login. \
                Run: bash scripts/install.sh
                """)
        }
        do {
            try (register ?? systemRegister)()
        } catch {
            return .refused("macOS refused to register: \(error.localizedDescription)")
        }
        return .changed(state(from: (status ?? systemStatus)()))
    }

    /// Removes the app from login.
    ///
    /// No path guard, unlike `enable`. Since BTM indexes by bundle ID,
    /// unregistering from any copy clears the registration for all of them
    /// (measured in the same spike) — and blocking the turn-off because the user
    /// is running the wrong copy would trap them in a state they want out of.
    public static func disable(
        unregister: (() throws -> Void)? = nil,
        status: (() -> SMAppService.Status)? = nil
    ) -> Outcome {
        do {
            try (unregister ?? systemUnregister)()
        } catch {
            return .refused("macOS refused to unregister: \(error.localizedDescription)")
        }
        return .changed(state(from: (status ?? systemStatus)()))
    }

    /// Opens the Login Items pane.
    ///
    /// Through the API, and not a hand-built `x-apple.systempreferences:` URL:
    /// that pane's identifier has already changed between macOS versions, and a
    /// wrong URL opens nothing and does not complain.
    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - The system calls, isolated so tests can swap them

    private static func systemStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    private static func systemRegister() throws {
        try SMAppService.mainApp.register()
    }

    private static func systemUnregister() throws {
        try SMAppService.mainApp.unregister()
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
