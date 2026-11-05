import Testing
@testable import NeverTypeCore

/// Audit probes for never-type-permissoes, part 2 (2026-11-05).
///
/// Each one holds a behavior of `MicrophoneRequest.askAgain` that the executor's
/// tests leave open: all of those use one `askAgain` per object, and the mark
/// and the timer are about what one request leaves behind for the next. The
/// reasoning (contract, regression that breaks it, why the existing test misses
/// it) is in `.vibeflow/audits/never-type-permissoes-2-audit.md`. No clock and
/// no TCC: the request, the wait and the reading are the test's.
@Suite("Permissions, part 2 audit")
@MainActor
struct PermissionsPart2AuditTests {

    /// Every request and every wait stays open until the test ends it, each
    /// kept apart so one run's wait can end while the next run is open.
    @MainActor
    private final class Scene {
        var microphone = MicrophoneAccess.notDetermined
        var asked = 0
        var alerts = 0
        var finished = 0
        var answers: [CheckedContinuation<Void, Never>] = []
        var waits: [CheckedContinuation<Void, Never>] = []
        var pendingAtEachAlert: [Bool] = []

        func request() async {
            asked += 1
            await withCheckedContinuation { answers.append($0) }
        }

        func wait() async {
            await withCheckedContinuation { waits.append($0) }
        }
    }

    /// Yields until `condition` holds. A bound on turns, never on time.
    private func turns(until condition: () -> Bool) async {
        var n = 0
        while !condition() && n < 10_000 {
            await Task.yield()
            n += 1
        }
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private func start(_ request: MicrophoneRequest, _ scene: Scene) {
        Task { @MainActor in
            await request.askAgain(
                request: { await scene.request() },
                wait: { await scene.wait() },
                microphone: { scene.microphone },
                onNoAnswer: {
                    scene.alerts += 1
                    scene.pendingAtEachAlert.append(request.isPending)
                })
            scene.finished += 1
        }
    }

    /// Leaves no continuation waiting, on any path.
    private func release(_ scene: Scene) async {
        for _ in 0..<4 {
            let open = scene.answers + scene.waits
            scene.answers = []
            scene.waits = []
            for continuation in open { continuation.resume() }
            await settle()
        }
    }

    /// "No second alert" is about one request. The alert of a wait that ran
    /// out says nothing about the next request, which can come back unanswered
    /// by itself: that person has to hear about it too. The mark lives on the
    /// object, which lives as long as the app.
    @Test("an alert from the wait of one request does not silence the next one",
          .timeLimit(.minutes(1)))
    func earlierWaitDoesNotSilenceTheNextRequest() async throws {
        let request = MicrophoneRequest()
        let scene = Scene()

        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)
        scene.waits.removeFirst().resume()
        await turns { scene.alerts == 1 }
        #expect(scene.alerts == 1, "the wait ran out with no answer: \(scene.alerts)")
        scene.answers.removeFirst().resume()
        await turns { scene.finished == 1 }
        #expect(scene.alerts == 1, "same request, no second alert: \(scene.alerts)")

        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)
        #expect(scene.alerts == 1, "nothing yet about the second request: \(scene.alerts)")
        scene.answers.removeFirst().resume()
        await turns { scene.finished == 2 }
        #expect(scene.alerts == 2,
                "the second request came back unanswered and nobody was told: \(scene.alerts)")
        await release(scene)
    }

    /// A trigger that finds the request open alerts and goes away. It must not
    /// touch what the open request remembers: the person already got the alert
    /// from its wait, so its return adds nothing.
    @Test("asking again with a request open does not make that request alert a second time",
          .timeLimit(.minutes(1)))
    func askingWhilePendingKeepsTheMarkOfTheOpenRequest() async throws {
        let request = MicrophoneRequest()
        let scene = Scene()

        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)
        scene.waits.removeFirst().resume()
        await turns { scene.alerts == 1 }
        #expect(scene.alerts == 1)

        start(request, scene)
        await turns { scene.finished == 1 }
        #expect(scene.finished == 1, "with a request open, asking again returns at once")
        #expect(scene.alerts == 2, "it says so at once: \(scene.alerts)")
        #expect(scene.asked == 1, "and asks nothing: \(scene.asked)")

        scene.answers.removeFirst().resume()
        await turns { scene.finished == 2 }
        #expect(scene.alerts == 2,
                "the open request came back and alerted again, after the wait had: \(scene.alerts)")
        await release(scene)
    }

    /// The wait of a request that already came back belongs to nobody. If it
    /// spoke while a later request is open, it would alert over that prompt
    /// and mark that request as already told, which swallows the alert that
    /// request is owed when it comes back.
    @Test("the wait of a finished request says nothing about the one open now",
          .timeLimit(.minutes(1)))
    func staleWaitDoesNotSpeakForTheOpenRequest() async throws {
        let request = MicrophoneRequest()
        let scene = Scene()

        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)
        let firstWait = scene.waits.removeFirst()
        scene.microphone = .denied
        scene.answers.removeFirst().resume()
        await turns { scene.finished == 1 }
        #expect(scene.alerts == 0, "answered, nothing to say: \(scene.alerts)")

        scene.microphone = .notDetermined
        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)

        firstWait.resume()
        await settle()
        #expect(scene.alerts == 0,
                "the first request's wait alerted over the second one: \(scene.alerts)")

        scene.answers.removeFirst().resume()
        await turns { scene.finished == 2 }
        #expect(scene.alerts == 1,
                "the second request came back unanswered, one alert and from its own return: \(scene.alerts)")
        await release(scene)
    }

    /// The alert blocks until OK, so whatever is true when it opens stays true
    /// for as long as the person takes. The request has returned: nothing may
    /// still read as in flight, or a trigger during the alert gets the waiting
    /// branch instead of a new request.
    @Test("the alert for a request that came back finds no request in flight",
          .timeLimit(.minutes(1)))
    func alertAfterTheReturnFindsNothingPending() async throws {
        let request = MicrophoneRequest()
        let scene = Scene()

        start(request, scene)
        await turns { scene.answers.count == 1 && scene.waits.count == 1 }
        try #require(scene.answers.count == 1 && scene.waits.count == 1)
        scene.answers.removeFirst().resume()
        await turns { scene.finished == 1 }

        #expect(scene.pendingAtEachAlert == [false],
                "in flight when each alert opened: \(scene.pendingAtEachAlert)")
        await release(scene)
    }
}
