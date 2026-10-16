import Testing
@testable import NeverTypeCore

/// The order of the launch prompts and the log line that reports both
/// permissions.
///
/// The case behind both, 2026-10-15: a person installed through an agent and
/// macOS showed the Accessibility prompt and never the microphone one. The app
/// asked for the two back to back, the first without waiting for an answer, and
/// nothing in the log said which permission was missing.
@Suite("Permissions")
struct PermissionsTests {

    /// What the launch did, in order. A class on the main actor because the
    /// rule runs there and the test reads it between two of its steps.
    @MainActor
    private final class Journal {
        var steps: [String] = []
        var microphone: MicrophoneAccess
        var accessibility: Bool
        var pendingAnswer: CheckedContinuation<Void, Never>?
        /// Whether a microphone request waits for the test to answer it. Off,
        /// it is answered at once: a test that expects no request then fails
        /// on the steps instead of hanging on a continuation nobody resumes
        /// (audit L4, where the suite hung 10 minutes; a `.timeLimit` alone
        /// does not end a test stuck on a continuation, measured 16/10).
        let holdsAnswer: Bool

        init(microphone: MicrophoneAccess, accessibility: Bool, holdsAnswer: Bool = true) {
            self.microphone = microphone
            self.accessibility = accessibility
            self.holdsAnswer = holdsAnswer
        }
    }

    @MainActor
    private func launch(_ journal: Journal) async {
        await LaunchPermissions.run(
            microphone: { journal.microphone },
            accessibilityGranted: {
                journal.steps.append("check accessibility")
                return journal.accessibility
            },
            requestMicrophone: {
                journal.steps.append("ask microphone")
                // A second request returns at once, for the same reason.
                if journal.holdsAnswer && journal.pendingAnswer == nil {
                    await withCheckedContinuation { journal.pendingAnswer = $0 }
                }
                journal.steps.append("microphone answered")
            },
            requestAccessibility: { journal.steps.append("ask accessibility") })
    }

    /// The race this replaced: the microphone prompt was started and left
    /// running while the Accessibility one opened on top of it. Here the
    /// microphone prompt is held open by the test, and while it is open the
    /// rule must not even look at Accessibility.
    @Test("with the microphone unanswered, Accessibility waits for the answer",
          .timeLimit(.minutes(1)))
    @MainActor
    func accessibilityWaitsForTheMicrophone() async throws {
        let journal = Journal(microphone: .notDetermined, accessibility: false)
        let running = Task { @MainActor in await launch(journal) }

        // Until the prompt is up. A bound on turns, never on time.
        var turns = 0
        while journal.pendingAnswer == nil && turns < 10_000 {
            await Task.yield()
            turns += 1
        }
        try #require(journal.pendingAnswer != nil, "the microphone prompt never started")

        for _ in 0..<100 { await Task.yield() }
        #expect(journal.steps == ["ask microphone"],
                "with the prompt still open, expected nothing else; got \(journal.steps)")

        journal.pendingAnswer?.resume()
        await running.value

        #expect(journal.steps == [
            "ask microphone", "microphone answered",
            "check accessibility", "ask accessibility",
        ])
    }

    /// The time limit is audit L4: when the rule asked again for an answered
    /// microphone, the continuation was never resumed and the suite hung for
    /// 10 minutes instead of failing.
    @Test("a microphone already answered is not asked again at launch",
          .timeLimit(.minutes(1)),
          arguments: [MicrophoneAccess.authorized, .denied, .restricted])
    @MainActor
    func answeredMicrophoneIsNotAsked(access: MicrophoneAccess) async {
        let journal = Journal(microphone: access, accessibility: false, holdsAnswer: false)
        await launch(journal)

        #expect(journal.steps == ["check accessibility", "ask accessibility"],
                "\(access): got \(journal.steps)")
    }

    @Test("Accessibility already granted is not asked for", .timeLimit(.minutes(1)))
    @MainActor
    func grantedAccessibilityIsNotAsked() async {
        let journal = Journal(microphone: .authorized, accessibility: true, holdsAnswer: false)
        await launch(journal)

        #expect(journal.steps == ["check accessibility"])
    }

    // MARK: - The request in flight (audit D1)

    /// A system request and a wait, each held open by the test and released
    /// by it. The wait stands in for the 10 seconds: no clock is read.
    @MainActor
    private final class Prompt {
        var asked = 0
        var alerts = 0
        var waits = 0
        var answer: CheckedContinuation<Void, Never>?
        var waitOver: CheckedContinuation<Void, Never>?
        /// Set when `askAgain` returns, so a test waits for it by turns and
        /// a regression fails instead of hanging (audit L4).
        var returned = false

        /// Held open until the test answers. A second request while the first
        /// is held returns at once, so a regression that asks again fails on
        /// `asked` instead of hanging.
        func request() async {
            asked += 1
            guard answer == nil else { return }
            await withCheckedContinuation { answer = $0 }
        }

        func wait() async {
            await withCheckedContinuation { waitOver = $0 }
        }
    }

    /// Yields until `condition` holds. A bound on turns, never on time.
    @MainActor
    private func turns(until condition: () -> Bool) async {
        var turns = 0
        while !condition() && turns < 10_000 {
            await Task.yield()
            turns += 1
        }
    }

    /// The launch request is the one a trigger finds in flight: while it is
    /// open the app knows, and once answered it no longer is.
    @Test("the launch request is in flight until it is answered", .timeLimit(.minutes(1)))
    @MainActor
    func launchRequestIsInFlight() async throws {
        let request = MicrophoneRequest()
        let prompt = Prompt()
        #expect(!request.isPending)

        Task { @MainActor in
            await request.ask { await prompt.request() }
            prompt.returned = true
        }
        await turns { prompt.answer != nil }
        try #require(prompt.answer != nil, "the request never started")
        #expect(request.isPending)

        prompt.answer?.resume()
        await turns { prompt.returned }
        #expect(prompt.returned)
        #expect(!request.isPending)
    }

    /// The first path of D1: a second request would join the open one and
    /// show nothing, so the alert comes at once and nothing is asked again.
    @Test("with a request in flight, asking again shows the alert at once and asks nothing",
          .timeLimit(.minutes(1)))
    @MainActor
    func askingAgainWhilePendingAlertsAtOnce() async throws {
        let request = MicrophoneRequest()
        let prompt = Prompt()
        Task { @MainActor in await request.ask { await prompt.request() } }
        await turns { prompt.answer != nil }
        try #require(prompt.answer != nil)

        Task { @MainActor in
            await request.askAgain(
                request: { await prompt.request() },
                wait: { prompt.waits += 1 },
                onNoAnswer: { prompt.alerts += 1 })
            prompt.returned = true
        }
        await turns { prompt.returned }
        #expect(prompt.returned, "asking again with a request in flight has to return at once")

        #expect(prompt.alerts == 1, "expected the alert at once, got \(prompt.alerts)")
        #expect(prompt.asked == 1, "a second request joins the first and shows nothing")
        #expect(prompt.waits == 0, "with the alert already up there is nothing to wait for")

        prompt.answer?.resume()
    }

    /// The second path of D1: the prompt that never appears. The request stays
    /// open, the wait ends, and the alert comes once.
    @Test("a request with no answer when the wait ends shows the alert, once",
          .timeLimit(.minutes(1)))
    @MainActor
    func noAnswerWithinTheWaitAlerts() async throws {
        let request = MicrophoneRequest()
        let prompt = Prompt()
        Task { @MainActor in
            await request.askAgain(
                request: { await prompt.request() },
                wait: { await prompt.wait() },
                onNoAnswer: { prompt.alerts += 1 })
            prompt.returned = true
        }
        await turns { prompt.answer != nil && prompt.waitOver != nil }
        try #require(prompt.answer != nil, "the request never started")
        try #require(prompt.waitOver != nil, "the wait never started")
        #expect(request.isPending)
        #expect(prompt.alerts == 0, "no alert before the wait ends")

        prompt.waitOver?.resume()
        await turns { prompt.alerts > 0 }
        #expect(prompt.alerts == 1)

        prompt.answer?.resume()
        await turns { prompt.returned }
        #expect(prompt.returned, "the answer has to end the request")
        #expect(prompt.alerts == 1, "the answer after the alert adds no second one")
        #expect(!request.isPending)
    }

    /// An answer inside the wait is the normal case and shows nothing, even
    /// when the wait ends afterwards.
    @Test("an answer before the wait ends shows no alert", .timeLimit(.minutes(1)))
    @MainActor
    func answerWithinTheWaitIsSilent() async throws {
        let request = MicrophoneRequest()
        let prompt = Prompt()
        Task { @MainActor in
            await request.askAgain(
                request: { await prompt.request() },
                wait: { await prompt.wait() },
                onNoAnswer: { prompt.alerts += 1 })
            prompt.returned = true
        }
        await turns { prompt.answer != nil && prompt.waitOver != nil }
        try #require(prompt.answer != nil)
        try #require(prompt.waitOver != nil, "the wait never started, so the test proves nothing")

        prompt.answer?.resume()
        await turns { prompt.returned }
        #expect(prompt.returned, "the answer has to end the request, without waiting out the wait")
        #expect(!request.isPending)

        prompt.waitOver?.resume()
        for _ in 0..<100 { await Task.yield() }
        #expect(prompt.alerts == 0, "answered in time and still alerted")
    }

    // MARK: - The log line

    /// The line `scripts/verify-install.sh` reads. Its format is a contract
    /// with the script, so it is compared whole.
    @Test("the permissions line names both, with the system's four microphone answers",
          arguments: [
            (MicrophoneAccess.authorized, true,
             "permissions: microphone=authorized accessibility=granted"),
            (.notDetermined, true,
             "permissions: microphone=notDetermined accessibility=granted"),
            (.denied, false,
             "permissions: microphone=denied accessibility=missing"),
            (.restricted, false,
             "permissions: microphone=restricted accessibility=missing"),
          ])
    func lineFormat(microphone: MicrophoneAccess, accessibility: Bool, expected: String) {
        #expect(PermissionLog.line(microphone: microphone, accessibilityGranted: accessibility) == expected)
    }

    @Test("the first reading is always written, the same one again is not, a change is")
    func writesOnChange() {
        var log = PermissionLog()

        let first = log.lineIfChanged(microphone: .notDetermined, accessibilityGranted: false)
        let same = log.lineIfChanged(microphone: .notDetermined, accessibilityGranted: false)
        let micChanged = log.lineIfChanged(microphone: .authorized, accessibilityGranted: false)
        let axChanged = log.lineIfChanged(microphone: .authorized, accessibilityGranted: true)
        let back = log.lineIfChanged(microphone: .denied, accessibilityGranted: true)

        #expect(first == "permissions: microphone=notDetermined accessibility=missing")
        #expect(same == nil, "an unchanged reading wrote \(same ?? "")")
        #expect(micChanged == "permissions: microphone=authorized accessibility=missing")
        #expect(axChanged == "permissions: microphone=authorized accessibility=granted")
        #expect(back == "permissions: microphone=denied accessibility=granted")
    }
}
