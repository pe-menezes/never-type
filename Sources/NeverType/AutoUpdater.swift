import AppKit

/// Checks the git remote this app was built from and, on confirmation,
/// updates in place: fetch, pull, rebuild, reinstall, relaunch.
///
/// This is the one place in the app that reaches the network at run time —
/// everywhere else, "no network calls at run time" holds exactly as
/// `docs/reference.md` describes. Enabling this setting trades that away on
/// purpose: it runs the same `git fetch`/`git pull` `scripts/update.sh`
/// already ran when a person invoked it by hand, just invoked by the app
/// instead of a terminal.
///
/// The apply step shells out to `scripts/update.sh` unmodified rather than
/// reimplementing its git safety checks (refuses on uncommitted changes or a
/// diverged branch) here — one script stays the single place those rules
/// live, whether a person or this class runs it.
///
/// `scripts/install.sh`, which `update.sh` calls, ends by running
/// `pkill -x NeverType` — which on success kills *this app's own process*,
/// since this app is NeverType. That is expected, not avoided: the spawned
/// `bash` process is not matched by that `pkill` (it matches the compiled
/// executable's name, not the shell running the script), so it survives its
/// own parent dying, reparented to launchd, and finishes the job — ending in
/// `install.sh`'s own `open` of the newly installed app. See
/// `UpdateProgressWindow`'s doc comment for what that means for the UI.
@MainActor
final class AutoUpdater {
    private static let enabledKey = "autoUpdateEnabled"
    private static let lastCheckKey = "autoUpdateLastCheck"
    private static let dismissedSHAKey = "autoUpdateDismissedSHA"
    /// Below the daily interval, so a "Later" dismissal is not immediately
    /// re-asked by the very next scheduled check.
    private static let launchCheckThrottle: TimeInterval = 3600
    private static let backgroundCheckInterval: TimeInterval = 86_400

    /// On by default, matching `Feedback.isEnabled`'s pattern: an absent key
    /// reads as on.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Whether a reachable git checkout exists for this build. False for a
    /// copy of the app on a machine with no source checkout, or one whose
    /// checkout moved after the app was built — checked once at launch since
    /// it practically never changes while the app runs, and re-running `git`
    /// on every menu open would be a cost for no benefit.
    let isAvailable: Bool

    /// Set by `AppDelegate` after init: whether a dictation is in progress.
    /// An apply step must never start mid-recording — it ends with the app
    /// itself being killed to reinstall.
    var isDictationActive: () -> Bool = { false }

    /// Set by `AppDelegate` after init, the same closure-wiring shape as
    /// `recorder.onLevel`/`onError`.
    var log: (String) -> Void = { _ in }

    private let repoRoot: String?
    private let progressWindow = UpdateProgressWindow()
    private var dailyTimer: Timer?
    private var tailTimer: Timer?
    private var applyProcess: Process?
    private var isBusy = false

    init() {
        let path = Bundle.main.object(forInfoDictionaryKey: "NeverTypeRepoRoot") as? String
        repoRoot = (path?.isEmpty == false) ? path : nil
        isAvailable = Self.isValidGitCheckout(repoRoot)
    }

    // MARK: - Scheduling

    func scheduleDailyChecks() {
        dailyTimer?.invalidate()
        dailyTimer = Timer.scheduledTimer(withTimeInterval: Self.backgroundCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runBackgroundCheck() }
        }
    }

    /// Skips the check if one already ran within the last hour — otherwise an
    /// auto-applied update would relaunch straight into another check.
    func checkOnLaunchIfDue() {
        guard isAvailable, isEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Self.launchCheckThrottle else { return }
        runBackgroundCheck()
    }

    private func runBackgroundCheck() {
        guard isAvailable, isEnabled, !isBusy, !isDictationActive() else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        isBusy = true
        Task {
            defer { isBusy = false }
            guard let result = await performCheck(), result.needsUpdate else { return }
            let dismissed = UserDefaults.standard.string(forKey: Self.dismissedSHAKey)
            guard result.remoteSHA != dismissed else { return }
            isBusy = true
            promptToUpdate(result)
        }
    }

    // MARK: - Manual check

    func checkNowInteractively() {
        guard !isBusy else { return }
        guard isAvailable else {
            showInfo("Auto-update is unavailable: no source checkout was found for this build.")
            return
        }
        isBusy = true
        Task {
            guard let result = await performCheck() else {
                isBusy = false
                showInfo("Could not check for updates. Is the network reachable?")
                return
            }
            guard result.needsUpdate else {
                isBusy = false
                showInfo("NeverType is up to date (\(result.localSHA)).")
                return
            }
            // A manual check always asks, regardless of an earlier "Later".
            promptToUpdate(result)
        }
    }

    // MARK: - Checking

    private struct CheckResult {
        let installedSHA: String
        let localSHA: String
        let remoteSHA: String
        /// Matches `update.sh`'s own three-way comparison (`update.sh:56-70`):
        /// a pull that succeeded but a build/install that did not would
        /// otherwise leave `local == remote` and hide a still-broken install.
        var needsUpdate: Bool { localSHA != remoteSHA || installedSHA != localSHA }
    }

    private func performCheck() async -> CheckResult? {
        guard let repoRoot else { return nil }
        let fetch = await run("/usr/bin/git", ["-C", repoRoot, "fetch", "--quiet"])
        guard fetch.status == 0 else { return nil }
        let local = await run("/usr/bin/git", ["-C", repoRoot, "rev-parse", "--short", "HEAD"])
        let remote = await run("/usr/bin/git", ["-C", repoRoot, "rev-parse", "--short", "@{u}"])
        guard local.status == 0, remote.status == 0 else { return nil }
        let installed = Bundle.main.object(forInfoDictionaryKey: "NeverTypeCommit") as? String ?? "unknown"
        return CheckResult(installedSHA: installed,
                           localSHA: local.output.trimmingCharacters(in: .whitespacesAndNewlines),
                           remoteSHA: remote.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func promptToUpdate(_ result: CheckResult) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "NeverType \(result.localSHA) → \(result.remoteSHA) is available."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            beginApply()
        } else {
            UserDefaults.standard.set(result.remoteSHA, forKey: Self.dismissedSHAKey)
            isBusy = false
        }
    }

    private func showInfo(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Applying

    private func beginApply() {
        guard let repoRoot else { isBusy = false; return }
        progressWindow.show()

        let logURL = Self.logFileURL()
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            progressWindow.reportFailure(status: "Could not open the update log.")
            isBusy = false
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["\(repoRoot)/scripts/update.sh"]
        // `install.sh` kills the running app by exact PID when this variable
        // is set, instead of finding it by name with `pgrep`/`pkill -x
        // NeverType`. Measured on 2026-09-16: that name-based lookup finds
        // nothing when run from a child this app spawned via `Process()`,
        // even while the app is provably still running — `install.sh`'s own
        // comment on the block that reads this variable has the repro. `kill
        // -TERM`/`kill -0` on an exact, already-known pid has no such blind
        // spot, which is the whole reason this exists instead of leaving
        // `install.sh`'s existing `pgrep` path to find this app on its own.
        var environment = ProcessInfo.processInfo.environment
        environment["NEVERTYPE_CALLER_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
        process.environment = environment
        // A log file, not a `Pipe()`: on success this app's own process dies
        // partway through (see the type's doc comment), and a pipe whose
        // reader has gone away can raise SIGPIPE in the still-running script
        // on its next write — a file has no reader to lose. It also sidesteps
        // an unrelated hazard a `Pipe()` would have regardless: `swift build`
        // output can exceed the pipe's kernel buffer and block the child.
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] proc in
            // Fires on an arbitrary background queue — hop explicitly rather
            // than `MainActor.assumeIsolated`, which is only for callbacks
            // this codebase's own APIs document as running isolated
            // (`HotkeyMonitor`, `RecordingOverlay`'s pulse timer).
            Task { @MainActor in
                self?.finishFailedApply(exitCode: proc.terminationStatus)
            }
        }

        startTailing(logURL)
        log("update: starting (\(repoRoot))")

        do {
            try process.run()
            applyProcess = process
        } catch {
            stopTailing()
            progressWindow.reportFailure(status: "Could not start the update: \(error.localizedDescription)")
            isBusy = false
        }
    }

    /// Reached only on the failure path: a bad fetch, uncommitted local
    /// changes, a diverged branch, or a build error, all of which exit
    /// `update.sh` before `install.sh`'s `pkill` — the success path never
    /// reaches this, because the app is the thing that pkill kills.
    private func finishFailedApply(exitCode: Int32) {
        stopTailing()
        isBusy = false
        applyProcess = nil
        let text = (try? String(contentsOf: Self.logFileURL(), encoding: .utf8)) ?? ""
        let lastLine = Self.stripANSI(text)
            .split(separator: "\n")
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init) ?? "update failed (exit \(exitCode))"
        log("update: failed — \(lastLine)")
        progressWindow.reportFailure(status: lastLine)
    }

    // MARK: - Log tailing

    private func startTailing(_ url: URL) {
        tailTimer?.invalidate()
        tailTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tail(url) }
        }
    }

    private func stopTailing() {
        tailTimer?.invalidate()
        tailTimer = nil
    }

    /// Re-reads the whole file on every tick rather than tracking a byte
    /// offset: it holds a handful of KB of `info`/`ok`/`warn`/`fail` lines
    /// for the length of one update, so the simpler read costs nothing that
    /// matters and cannot skip a line split across two ticks.
    private func tail(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        guard let last = Self.stripANSI(text)
            .split(separator: "\n")
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        progressWindow.report(status: String(last))
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private static func logFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NeverType/update.log")
    }

    // MARK: - Process helpers

    private func run(_ executable: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "\(error)"))
            }
        }
    }

    private static func isValidGitCheckout(_ path: String?) -> Bool {
        guard let path else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--git-dir"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
