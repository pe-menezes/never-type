import Foundation
import Testing
@testable import NeverTypeCore

/// The rule behind "Check for Updates…", and the two things the click does,
/// with git and open standing in as closures.
///
/// No test here touches the network or a checkout: a fetch in the suite would
/// make `swift test` depend on the machine's connection and on GitHub, and it
/// would be the one network call the project promises not to make on its own.
/// The only real processes are `/bin/echo` and `/bin/sleep`, for the runner.
@Suite("Check for Updates")
struct UpdateCheckTests {

    /// Records every call so a test can check the order: the closure passed as
    /// `git` is `@Sendable` and cannot append to a plain array.
    private actor Calls {
        var list: [[String]] = []
        func add(_ arguments: [String]) { list.append(arguments) }
    }

    // MARK: - The rule

    @Test("with the app on the commit update.sh would build, there is nothing to do")
    func upToDate() {
        #expect(UpdateCheck.decide(installed: "b07c6da", local: "b07c6da", remote: "b07c6da", behind: 0)
                == .upToDate(installed: "b07c6da"))
        #expect(UpdateCheck.decide(installed: "1a2b3c4", local: "1a2b3c4", remote: "b07c6da", behind: 0)
                == .upToDate(installed: "1a2b3c4"),
                "a local branch ahead of the remote is not behind: a rebuild would land on the same commit")
        #expect(UpdateCheck.decide(installed: "b07c6da", local: "17a7ff2", remote: "b07c6da", behind: 1)
                == .upToDate(installed: "b07c6da"),
                "the app already runs what the remote has; only the checkout is stale")
    }

    @Test("a checkout ahead of the installed app asks for a reinstall, not a pull")
    func reinstallNeeded() {
        #expect(UpdateCheck.decide(installed: "17a7ff2", local: "b07c6da", remote: "b07c6da", behind: 0)
                == .reinstallNeeded(installed: "17a7ff2", local: "b07c6da"))
        #expect(UpdateCheck.decide(installed: "unknown", local: "b07c6da", remote: "b07c6da", behind: 0)
                == .reinstallNeeded(installed: "unknown", local: "b07c6da"),
                "a bundle with no stamp is treated as behind, never as current")
    }

    @Test("commits on the remote that the checkout lacks are an update, counted")
    func behind() {
        #expect(UpdateCheck.decide(installed: "17a7ff2", local: "17a7ff2", remote: "b07c6da", behind: 3)
                == .behind(commits: 3, installed: "17a7ff2", remote: "b07c6da"))
        #expect(UpdateCheck.decide(installed: "unknown", local: "17a7ff2", remote: "b07c6da", behind: 1)
                == .behind(commits: 1, installed: "unknown", remote: "b07c6da"))
    }

    @Test("only the two outcomes with something to install offer Update Now")
    func offersUpdate() {
        #expect(UpdateCheck.Outcome.reinstallNeeded(installed: "a", local: "b").offersUpdate)
        #expect(UpdateCheck.Outcome.behind(commits: 1, installed: "a", remote: "b").offersUpdate)
        #expect(!UpdateCheck.Outcome.upToDate(installed: "a").offersUpdate)
        #expect(!UpdateCheck.Outcome.noUpstream.offersUpdate)
        #expect(!UpdateCheck.Outcome.unreachable("").offersUpdate)
    }

    @Test("the alert text quotes git and names the way out")
    func alertText() {
        let unreachable = UpdateCheck.Outcome.unreachable(
            "fatal: unable to access 'https://github.com/x/y/': Could not resolve host: github.com\n")
        #expect(unreachable.title == "Could not check for updates")
        #expect(unreachable.detail.contains("Could not resolve host"), "git's last line is the reason shown")
        #expect(unreachable.detail.contains("bash scripts/update.sh"))
        #expect(UpdateCheck.Outcome.unreachable("").detail.hasPrefix("git fetch failed."),
                "no output leaves no dangling colon")
        #expect(UpdateCheck.Outcome.noUpstream.detail.contains("bash scripts/update.sh"))
        #expect(UpdateCheck.Outcome.behind(commits: 1, installed: "a", remote: "b").detail
                .hasPrefix("1 new commit on the remote: a → b"))
        #expect(UpdateCheck.Outcome.behind(commits: 2, installed: "a", remote: "b").detail
                .hasPrefix("2 new commits on the remote"))
        #expect(UpdateCheck.Outcome.reinstallNeeded(installed: "17a7ff2", local: "b07c6da").detail
                .contains("checkout is at b07c6da and the installed app is 17a7ff2"))
        #expect(UpdateCheck.Outcome.upToDate(installed: "b07c6da").detail == "Running b07c6da. Nothing newer on the remote.")
    }

    // MARK: - The click, with git standing in

    @Test("the happy path asks git four questions, in order, and decides from the answers")
    func fourGitCalls() async {
        let calls = Calls()
        let git: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            switch arguments.first {
            case "fetch":     return .init(status: 0, output: "")
            case "rev-parse": return .init(status: 0, output: arguments.last == "HEAD" ? "17a7ff2\n" : "b07c6da\n")
            case "rev-list":  return .init(status: 0, output: "2\n")
            default:          return .init(status: 1, output: "unexpected \(arguments)")
            }
        }

        let outcome = await UpdateCheck.check(repoRoot: "/tmp/never-type", installed: "17a7ff2", git: git)

        #expect(outcome == .behind(commits: 2, installed: "17a7ff2", remote: "b07c6da"))
        #expect(await calls.list == [
            ["fetch", "--quiet"],
            ["rev-parse", "--short", "HEAD"],
            ["rev-parse", "--short", "@{u}"],
            ["rev-list", "--count", "HEAD..@{u}"],
        ], "the fetch comes first and the count last; the alert depends on the count")
    }

    @Test("a fetch that fails is unreachable, with git's own words, and nothing else runs")
    func fetchFails() async {
        let calls = Calls()
        let git: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            return .init(status: 128, output: "fatal: unable to access: Could not resolve host\n")
        }

        let outcome = await UpdateCheck.check(repoRoot: "/tmp/never-type", installed: "17a7ff2", git: git)

        #expect(outcome == .unreachable("fatal: unable to access: Could not resolve host\n"))
        #expect(await calls.list.count == 1, "after a failed fetch there is nothing to compare")
    }

    @Test("a branch with no upstream is its own outcome, not a network failure")
    func noUpstream() async {
        let git: UpdateCheck.Command = { arguments in
            if arguments == ["rev-parse", "--short", "@{u}"] {
                return .init(status: 128, output: "fatal: no upstream configured for branch 'main'\n")
            }
            return .init(status: 0, output: "17a7ff2\n")
        }

        #expect(await UpdateCheck.check(repoRoot: "/tmp/x", installed: "17a7ff2", git: git) == .noUpstream)
    }

    @Test("a count git cannot produce is a failure, not a guess")
    func badCount() async {
        let git: UpdateCheck.Command = { arguments in
            if arguments.first == "rev-list" { return .init(status: 0, output: "not a number\n") }
            return .init(status: 0, output: "17a7ff2\n")
        }

        #expect(await UpdateCheck.check(repoRoot: "/tmp/x", installed: "17a7ff2", git: git)
                == .unreachable("not a number\n"))
    }

    // MARK: - Update Now, with open standing in

    @Test("Update Now asks Terminal to run update.sh from the checkout")
    func opensTerminal() async {
        let calls = Calls()
        let open: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            return .init(status: 0, output: "")
        }

        let failure = await UpdateCheck.openUpdateScript(repoRoot: "/Users/me/never-type", open: open)

        #expect(failure == nil)
        #expect(await calls.list == [["-a", "Terminal", "/Users/me/never-type/scripts/update.sh"]])
    }

    @Test("when open fails the message carries the command to run by hand")
    func openFails() async {
        let open: UpdateCheck.Command = { _ in
            .init(status: 1, output: "Unable to find application named 'Terminal'\n")
        }

        let failure = await UpdateCheck.openUpdateScript(repoRoot: "/Users/me/never-type", open: open)

        #expect(failure?.contains("bash /Users/me/never-type/scripts/update.sh") == true, "got: \(failure ?? "nil")")
        #expect(failure?.contains("Unable to find application") == true, "open's own words are the reason shown")
    }

    // MARK: - Availability

    @Test("the line exists only with a .git and an update.sh at the stamped path")
    func availability() {
        let present: Set<String> = ["/repo/.git", "/repo/scripts/update.sh", "/moved/.git"]
        let exists: (String) -> Bool = { present.contains($0) }

        #expect(UpdateCheck.isAvailable(repoRoot: "/repo", exists: exists))
        #expect(!UpdateCheck.isAvailable(repoRoot: "/moved", exists: exists),
                "a checkout without the script has nothing to run")
        #expect(!UpdateCheck.isAvailable(repoRoot: "/gone", exists: exists))
        #expect(!UpdateCheck.isAvailable(repoRoot: nil, exists: exists), "a build with no stamp")
        #expect(!UpdateCheck.isAvailable(repoRoot: "", exists: exists))
    }

    // MARK: - The runner, with real processes

    @Test("a command that never ends is cut at the timeout and says so")
    func timeout() async {
        let clock = ContinuousClock()
        let start = clock.now

        let result = await UpdateCheck.run("/bin/sleep", ["5"], timeout: .milliseconds(300), environment: [:])

        let elapsed = clock.now - start
        #expect(result.status != 0)
        #expect(result.output.contains("timed out"), "got: \(result.output)")
        #expect(elapsed < .seconds(2), "took \(elapsed): the process was not cut at the timeout")
    }

    @Test("a command that ends returns its status and output whole")
    func echo() async {
        let result = await UpdateCheck.run("/bin/echo", ["hello"], timeout: .seconds(10), environment: [:])
        #expect(result == .init(status: 0, output: "hello\n"))
    }

    @Test("a command that cannot start says which, instead of hanging")
    func cannotStart() async {
        let result = await UpdateCheck.run("/nonexistent/binary", [], timeout: .seconds(1), environment: [:])
        #expect(result.status == -1)
        #expect(result.output.contains("/nonexistent/binary"), "got: \(result.output)")
    }

    @Test("git never waits for a credential prompt")
    func noTerminalPrompt() {
        #expect(UpdateCheck.gitEnvironment["GIT_TERMINAL_PROMPT"] == "0")
    }
}
