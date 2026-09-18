import Foundation

/// Answers "is there a newer NeverType than the one running?" from the source
/// checkout this build came from, and hands the update itself to Terminal.
///
/// The one place in the app that reaches the network, and only when the person
/// clicks: `git fetch` on the clone stamped in `Info.plist`, then three local
/// git questions. Nothing here runs on a timer or at launch. PR #14 proposed a
/// daily check, on by default; the decision to keep it to the click, and why,
/// is in `.vibeflow/decisions.md` (2026-09-18).
///
/// Applying is not done here on purpose. `scripts/install.sh` ends the running
/// app to replace it, and any failure after that point has no window left to
/// show it in. Terminal is the one process that survives, so "Update Now" asks
/// it to run `scripts/update.sh`, the same script a person runs by hand, with
/// the same messages.
///
/// Shaped like `LoginItem`: the rule is pure and public, and every system call
/// comes in as a parameter with a default, so each branch has a test that runs
/// without a network or a checkout.
public enum UpdateCheck {

    /// What a command returned: the exit status and everything it printed,
    /// stdout and stderr together, since the alert quotes whichever came.
    public struct CommandResult: Equatable, Sendable {
        public let status: Int32
        public let output: String

        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// A command already bound to its executable: `git` bound to `-C <root>`
    /// and its timeout, `open` bound to nothing. One shape for both, so a test
    /// stands in with a closure.
    public typealias Command = @Sendable ([String]) async -> CommandResult

    /// What the click found, with the alert's text already written.
    ///
    /// The wording lives here, next to the rule, the way `LoginItem.Outcome`
    /// carries its refusal: the executable only draws, and the text of each
    /// failure names the way out, as `falha-alta.md` asks.
    public enum Outcome: Equatable, Sendable {
        /// The app already runs the commit `update.sh` would build.
        case upToDate(installed: String)
        /// The checkout has the commit and the app does not: a pull done by
        /// hand without a reinstall, or a build that never got installed.
        case reinstallNeeded(installed: String, local: String)
        /// The remote has commits the checkout lacks.
        case behind(commits: Int, installed: String, remote: String)
        /// The branch tracks no remote branch, so there is nothing to compare
        /// against. `update.sh` prints the command that fixes it.
        case noUpstream
        /// `git fetch` (or one of the local questions) failed; carries the
        /// command's output.
        case unreachable(String)

        /// Whether the alert gets an "Update Now" button.
        public var offersUpdate: Bool {
            switch self {
            case .reinstallNeeded, .behind: return true
            case .upToDate, .noUpstream, .unreachable: return false
            }
        }

        public var title: String {
            switch self {
            case .upToDate:                   return "NeverType is up to date"
            case .reinstallNeeded, .behind:   return "Update available"
            case .noUpstream, .unreachable:   return "Could not check for updates"
            }
        }

        public var detail: String {
            switch self {
            case .upToDate(let installed):
                return "Running \(installed). Nothing newer on the remote."
            case .reinstallNeeded(let installed, let local):
                return "The checkout is at \(local) and the installed app is \(installed). "
                    + "Update Now opens Terminal and runs scripts/update.sh, which rebuilds "
                    + "and reinstalls; NeverType quits and reopens at the end."
            case .behind(let commits, let installed, let remote):
                let count = commits == 1 ? "1 new commit" : "\(commits) new commits"
                return "\(count) on the remote: \(installed) → \(remote). "
                    + "Update Now opens Terminal and runs scripts/update.sh, which pulls, "
                    + "rebuilds and reinstalls; NeverType quits and reopens at the end."
            case .noUpstream:
                return "The branch at the checkout tracks no remote branch. "
                    + "Run bash scripts/update.sh in a terminal: it prints the command that fixes it."
            case .unreachable(let output):
                let reason = UpdateCheck.lastLine(of: output)
                return "git fetch failed" + (reason.isEmpty ? "" : ": \(reason)") + ". "
                    + "Check the network, or run bash scripts/update.sh in a terminal."
            }
        }
    }

    // MARK: - The rule

    /// The rule itself, separated from any git call.
    ///
    /// `behind` is how many commits the remote has that the local branch lacks,
    /// `git rev-list --count HEAD..@{u}`. Up to date means the app already runs
    /// the commit `update.sh` would build: the remote's when the checkout is
    /// behind, the checkout's own otherwise. PR #14 compared SHAs for
    /// inequality instead, which confuses ahead with behind: a machine with one
    /// unpushed commit was offered a rebuild every day, to end up on the same
    /// commit, because `git pull --ff-only` with the local branch ahead does
    /// nothing.
    public static func decide(installed: String, local: String, remote: String, behind: Int) -> Outcome {
        let target = behind > 0 ? remote : local
        if installed == target { return .upToDate(installed: installed) }
        return behind > 0
            ? .behind(commits: behind, installed: installed, remote: remote)
            : .reinstallNeeded(installed: installed, local: local)
    }

    /// Whether the menu has anything to offer.
    ///
    /// `repoRoot` is the path `build-app.sh` stamped into `Info.plist`, or nil
    /// for a copy built without it. Two files decide: `.git`, because
    /// `update.sh` refuses without it, and `scripts/update.sh` itself. A `stat`
    /// each, run on every menu rebuild, since a checkout moves or gets deleted
    /// without telling the app. PR #14 asked git once at launch and kept the
    /// answer, which `estado-consultado.md` is written against.
    public static func isAvailable(repoRoot: String?,
                                   exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        guard let repoRoot, !repoRoot.isEmpty else { return false }
        return exists(repoRoot + "/.git") && exists(updateScriptPath(repoRoot: repoRoot))
    }

    public static func updateScriptPath(repoRoot: String) -> String {
        repoRoot + "/scripts/update.sh"
    }

    // MARK: - The two things the click does

    /// Fetches and compares. `installed` is the commit stamped in the bundle,
    /// `NeverTypeCommit`.
    ///
    /// Four git calls, in this order: the fetch is the only one that can take
    /// long or need the network; the other three read the checkout. A failure
    /// of the fetch or of the count comes back as `.unreachable` with the
    /// output, and a missing upstream as its own case, since its way out is a
    /// git command and not a network.
    public static func check(repoRoot: String, installed: String, git: Command? = nil) async -> Outcome {
        let git = git ?? gitCommand(repoRoot: repoRoot)

        let fetch = await git(["fetch", "--quiet"])
        guard fetch.status == 0 else { return .unreachable(fetch.output) }

        let local = await git(["rev-parse", "--short", "HEAD"])
        guard local.status == 0 else { return .unreachable(local.output) }

        let remote = await git(["rev-parse", "--short", "@{u}"])
        guard remote.status == 0 else { return .noUpstream }

        let behind = await git(["rev-list", "--count", "HEAD..@{u}"])
        guard behind.status == 0, let count = Int(trimmed(behind.output)) else {
            return .unreachable(behind.output)
        }

        return decide(installed: installed,
                      local: trimmed(local.output),
                      remote: trimmed(remote.output),
                      behind: count)
    }

    /// Asks Terminal to run `update.sh`. Nil on success; otherwise the text for
    /// the alert, with the command to run by hand.
    ///
    /// `open -a Terminal <script>`, not `osascript`: an Apple event to Terminal
    /// would need the Automation permission and hang on its dialog, the trap
    /// `conventions.md` records for scripts. `open` goes through LaunchServices
    /// and asks nobody.
    public static func openUpdateScript(repoRoot: String, open: Command? = nil) async -> String? {
        let script = updateScriptPath(repoRoot: repoRoot)
        let result = await (open ?? openCommand)(["-a", "Terminal", script])
        guard result.status == 0 else {
            let reason = lastLine(of: result.output)
            return "Could not open Terminal" + (reason.isEmpty ? "" : " (\(reason))")
                + ". Run in a terminal: bash \(script)"
        }
        return nil
    }

    // MARK: - Running processes

    /// The fetch is the one call that can wait on a network; the rest read
    /// the checkout and answer at once.
    public static let fetchTimeout: Duration = .seconds(30)
    public static let localTimeout: Duration = .seconds(10)

    /// The environment git runs with.
    ///
    /// `GIT_TERMINAL_PROMPT=0`: with no terminal attached, a remote asking for
    /// credentials would wait for an answer that never comes, until the
    /// timeout. With it, git fails at once and its output says why.
    public static var gitEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return environment
    }

    /// Absolute paths, because an app opened from Finder or the login item
    /// carries the system's PATH, not the shell's.
    static func gitCommand(repoRoot: String) -> Command {
        { arguments in
            await run("/usr/bin/git", ["-C", repoRoot] + arguments,
                      timeout: arguments.first == "fetch" ? fetchTimeout : localTimeout,
                      environment: gitEnvironment)
        }
    }

    static let openCommand: Command = { arguments in
        await run("/usr/bin/open", arguments, timeout: localTimeout,
                  environment: ProcessInfo.processInfo.environment)
    }

    /// Runs one process to completion or to the timeout, whichever comes
    /// first. A timeout ends the process and comes back as a non-zero status
    /// with `timed out` in the output.
    ///
    /// The timeout exists because a network that drops packets leaves
    /// `git fetch` waiting with no error, and a click that never answers is the
    /// silent failure `falha-alta.md` is about. Output is read in the
    /// termination handler, off the caller's thread, so a long fetch never
    /// blocks a cooperative-pool thread the way a synchronous read would.
    public static func run(_ executable: String, _ arguments: [String],
                           timeout: Duration, environment: [String: String]) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let box = ProcessBox(process)

        let ended: (status: Int32, output: String)? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus,
                                                String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            // Started after `run()`: `terminate()` on a process that never
            // launched raises an Objective-C exception, which no `catch` sees.
            box.watch(for: timeout)
        }
        box.stopWatching()

        guard let ended else {
            return CommandResult(status: -1, output: "could not start \(executable)")
        }
        if box.didTimeOut {
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            return CommandResult(status: ended.status == 0 ? -1 : ended.status,
                                 output: "timed out after \(formatted(seconds)) s")
        }
        return CommandResult(status: ended.status, output: ended.output)
    }

    /// `Process` is not `Sendable`, and the watchdog runs on another task. The
    /// box exposes the one operation that task needs, behind a lock, and
    /// remembers whether it was the one that ended the process.
    private final class ProcessBox: @unchecked Sendable {
        private let process: Process
        private let lock = NSLock()
        private var timedOut = false
        private var watchdog: Task<Void, Never>?

        init(_ process: Process) {
            self.process = process
        }

        func watch(for timeout: Duration) {
            lock.lock()
            defer { lock.unlock() }
            watchdog = Task { [self] in
                guard (try? await Task.sleep(for: timeout)) != nil else { return }
                terminateIfRunning()
            }
        }

        func stopWatching() {
            lock.lock()
            defer { lock.unlock() }
            watchdog?.cancel()
            watchdog = nil
        }

        var didTimeOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }

        private func terminateIfRunning() {
            lock.lock()
            defer { lock.unlock() }
            guard process.isRunning else { return }
            timedOut = true
            process.terminate()
        }
    }

    // MARK: - Text helpers

    static func lastLine(of output: String) -> String {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
    }

    private static func trimmed(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatted(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
    }
}
