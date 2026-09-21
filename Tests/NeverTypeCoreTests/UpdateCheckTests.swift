import Foundation
import Testing
@testable import NeverTypeCore

/// The rule behind "Check for Updates…", and the two things the click does,
/// with git and open standing in as closures.
///
/// No test here touches the network or a checkout: a fetch in the suite would
/// make `swift test` depend on the machine's connection and on GitHub, and it
/// would be the one network call the project promises not to make on its own.
/// The only real processes are `/bin/echo`, `/bin/sleep` and the `/bin/sh`
/// that spawns a helper, for the runner.
@Suite("Check for Updates")
struct UpdateCheckTests {

    /// Records every call so a test can check the order: the closure passed as
    /// `git` is `@Sendable` and cannot append to a plain array.
    private actor Calls {
        var list: [[String]] = []
        func add(_ arguments: [String]) { list.append(arguments) }
    }

    /// The path an alert would carry, from a checkout stamped by `build-app.sh`.
    private static let script = "/Users/me/never-type/scripts/update.sh"

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
        #expect(!UpdateCheck.Outcome.gitFailed(stage: .fetch, output: "").offersUpdate)
    }

    @Test("the alert text quotes git and names the way out")
    func alertText() {
        let script = Self.script
        let noNetwork = UpdateCheck.Outcome.gitFailed(
            stage: .fetch,
            output: "fatal: unable to access 'https://github.com/x/y/': Could not resolve host: github.com\n")
        #expect(noNetwork.title == "Could not check for updates")
        #expect(noNetwork.detail(updateScript: script).contains("Could not resolve host"),
                "git's last line is the reason shown")
        #expect(UpdateCheck.Outcome.gitFailed(stage: .fetch, output: "").detail(updateScript: script)
                .hasPrefix("git fetch failed."), "no output leaves no dangling colon")
        #expect(UpdateCheck.Outcome.behind(commits: 1, installed: "a", remote: "b").detail(updateScript: script)
                .hasPrefix("1 new commit on the remote: a → b"))
        #expect(UpdateCheck.Outcome.behind(commits: 2, installed: "a", remote: "b").detail(updateScript: script)
                .hasPrefix("2 new commits on the remote"))
        #expect(UpdateCheck.Outcome.reinstallNeeded(installed: "17a7ff2", local: "b07c6da").detail(updateScript: script)
                .contains("checkout is at b07c6da and the installed app is 17a7ff2"))
        #expect(UpdateCheck.Outcome.upToDate(installed: "b07c6da").detail(updateScript: script)
                == "Running b07c6da. Nothing newer on the remote.")
    }

    @Test("a command the person is asked to type carries the checkout's own path")
    func recoveryCommandIsAbsolute() {
        // A Terminal opened from Finder starts in the home directory. The text
        // used to say `bash scripts/update.sh`, which answers "No such file or
        // directory" from anywhere but the checkout.
        for outcome: UpdateCheck.Outcome in [.noUpstream, .gitFailed(stage: .fetch, output: "boom")] {
            let detail = outcome.detail(updateScript: Self.script)
            #expect(detail.contains("bash \(Self.script)"), "got: \(detail)")
            #expect(!detail.contains("bash scripts/update.sh"), "got: \(detail)")
        }
    }

    @Test("the alert blames the call that actually failed, not always the network")
    func failureNamesItsStage() {
        let script = Self.script
        let fetch = UpdateCheck.Outcome.gitFailed(stage: .fetch, output: "could not resolve host")
        #expect(fetch.detail(updateScript: script).hasPrefix("git fetch failed"))
        #expect(fetch.detail(updateScript: script).contains("Check the network"))

        // The three that read the local checkout. Sending someone to look at
        // their connection because `rev-parse HEAD` failed points at the wrong
        // thing; only the fetch touches a network.
        for stage: UpdateCheck.Stage in [.head, .upstream, .count] {
            let detail = UpdateCheck.Outcome.gitFailed(stage: stage, output: "fatal: bad object")
                .detail(updateScript: script)
            #expect(!detail.contains("git fetch failed"), "\(stage) got: \(detail)")
            #expect(!detail.contains("Check the network"), "\(stage) got: \(detail)")
            #expect(detail.contains("fatal: bad object"), "\(stage) got: \(detail)")
            #expect(detail.contains("bash \(script)"), "\(stage) got: \(detail)")
        }
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

    @Test("a fetch that fails names the fetch, keeps git's own words, and stops there")
    func fetchFails() async {
        let calls = Calls()
        let git: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            return .init(status: 128, output: "fatal: unable to access: Could not resolve host\n")
        }

        let outcome = await UpdateCheck.check(repoRoot: "/tmp/never-type", installed: "17a7ff2", git: git)

        #expect(outcome == .gitFailed(stage: .fetch, output: "fatal: unable to access: Could not resolve host\n"))
        #expect(await calls.list.count == 1, "after a failed fetch there is nothing to compare")
    }

    @Test("a checkout git cannot read stops the check, and says so instead of blaming the network")
    func headFails() async {
        let calls = Calls()
        let git: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            guard arguments != ["rev-parse", "--short", "HEAD"] else {
                return .init(status: 128, output: "fatal: not a git repository\n")
            }
            return .init(status: 0, output: "")
        }

        let outcome = await UpdateCheck.check(repoRoot: "/tmp/x", installed: "17a7ff2", git: git)

        #expect(outcome == .gitFailed(stage: .head, output: "fatal: not a git repository\n"),
                "the output is kept whole, and the stage says which call failed")
        #expect(await calls.list == [["fetch", "--quiet"], ["rev-parse", "--short", "HEAD"]],
                "with no HEAD to compare, the upstream and the count are never asked")
    }

    /// `rev-parse @{u}` fails for more than one reason, and only one of them is
    /// fixed by the `--set-upstream-to` that `update.sh` prints. Git's own
    /// words, measured on 2.50.1 with `LC_ALL=C`.
    @Test("only a branch that tracks nothing is noUpstream; the rest keep git's own error",
          arguments: [
            ("fatal: no upstream configured for branch 'main'\n", UpdateCheck.Outcome.noUpstream),
            ("fatal: HEAD does not point to a branch\n",
             .gitFailed(stage: .upstream, output: "fatal: HEAD does not point to a branch\n")),
            ("fatal: Needed a single revision\n",
             .gitFailed(stage: .upstream, output: "fatal: Needed a single revision\n")),
          ])
    func upstreamErrors(output: String, expected: UpdateCheck.Outcome) async {
        let git: UpdateCheck.Command = { arguments in
            if arguments == ["rev-parse", "--short", "@{u}"] {
                return .init(status: 128, output: output)
            }
            return .init(status: 0, output: "17a7ff2\n")
        }

        #expect(await UpdateCheck.check(repoRoot: "/tmp/x", installed: "17a7ff2", git: git) == expected,
                "a detached HEAD and a missing tracking ref are a checkout to repair, not an upstream to set")
    }

    @Test("a count git cannot produce is a failure, not a guess")
    func badCount() async {
        let git: UpdateCheck.Command = { arguments in
            if arguments.first == "rev-list" { return .init(status: 0, output: "not a number\n") }
            return .init(status: 0, output: "17a7ff2\n")
        }

        #expect(await UpdateCheck.check(repoRoot: "/tmp/x", installed: "17a7ff2", git: git)
                == .gitFailed(stage: .count, output: "not a number\n"))
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

    @Test("a checkout under a path with a space is pasteable, and open still gets it raw")
    func openFailsWithAwkwardPath() async {
        let calls = Calls()
        let open: UpdateCheck.Command = { arguments in
            await calls.add(arguments)
            return .init(status: 1, output: "boom\n")
        }
        let root = "/Users/me/Dev Stuff/o'brien & co/never-type"

        let failure = await UpdateCheck.openUpdateScript(repoRoot: root, open: open)

        // `update.sh` quotes "$REPO_ROOT" throughout, so this checkout works;
        // unquoted, the line offered to the person ran `bash /Users/me/Dev` and
        // then took `&` as a shell operator.
        #expect(failure?.contains(#"bash '/Users/me/Dev Stuff/o'\''brien & co/never-type/scripts/update.sh'"#) == true,
                "got: \(failure ?? "nil")")
        #expect(await calls.list == [["-a", "Terminal", root + "/scripts/update.sh"]],
                "open takes an argument, not a shell line: it gets the path raw")
    }

    @Test("only a path a shell would mangle is quoted")
    func shellQuoting() {
        #expect(UpdateCheck.shellQuoted("/Users/me/never-type/scripts/update.sh")
                == "/Users/me/never-type/scripts/update.sh", "a plain path reads better bare")
        #expect(UpdateCheck.shellQuoted("/Users/me/my repo") == "'/Users/me/my repo'")
        #expect(UpdateCheck.shellQuoted("/tmp/a&b") == "'/tmp/a&b'")
        #expect(UpdateCheck.shellQuoted("/tmp/o'brien") == #"'/tmp/o'\''brien'"#,
                "a quote inside closes, escapes and reopens, the one way sh accepts")
        #expect(UpdateCheck.shellQuoted("") == "''")
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

    // MARK: - When the answer may be shown

    @Test("an answer that arrives mid-dictation waits, and gives up on a bound")
    func presentationWaitsForDictation() {
        #expect(UpdateCheck.presentation(dictating: false, waited: .zero) == .show)
        #expect(UpdateCheck.presentation(dictating: true, waited: .zero) == .waitForDictation,
                "the alert would take the focus and the ⌘V would land on it")
        #expect(UpdateCheck.presentation(dictating: true, waited: .seconds(89)) == .waitForDictation)
        #expect(UpdateCheck.presentation(dictating: true, waited: UpdateCheck.presentationWait) == .giveUp,
                "a transcription that never ends must not keep the check running for good")
        #expect(UpdateCheck.presentation(dictating: false, waited: .seconds(600)) == .show,
                "the bound only counts while the dictation lasts")
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

    @Test("a helper that outlives the process does not hold the timeout open")
    func timeoutWithSurvivingHelper() async {
        let clock = ContinuousClock()
        let start = clock.now

        // The shape of `git fetch` launching git-remote-https or ssh: a helper
        // that inherits the pipe and outlives the process that started it. What
        // the termination handler waits on is the pipe, not the process, so a
        // helper left alive would hold the read for as long as it lives — 25 s
        // in the probe, against a 0.3 s timeout. It does not, because `Process`
        // gives the child a process group of its own and `terminate()` signals
        // the group.
        let result = await UpdateCheck.run("/bin/sh", ["-c", "/bin/sleep 3 & exec /bin/sleep 5"],
                                           timeout: .milliseconds(300), environment: [:])

        let elapsed = clock.now - start
        #expect(result.status != 0)
        #expect(result.output.contains("timed out"), "got: \(result.output)")
        #expect(elapsed < .seconds(2), "took \(elapsed): the helper kept the pipe open past the timeout")
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

    @Test("git never waits for a credential prompt, and answers in one language")
    func gitEnvironment() {
        #expect(UpdateCheck.gitEnvironment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(UpdateCheck.gitEnvironment["LC_ALL"] == "C",
                "isNoUpstream reads one of git's fatal lines; translated, it would not match")
    }
}
