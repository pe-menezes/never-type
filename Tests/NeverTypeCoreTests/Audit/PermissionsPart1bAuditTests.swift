import Testing
@testable import NeverTypeCore

/// Audit probes for never-type-permissoes, part 1b (2026-10-16).
///
/// Each one holds a behavior of `PermissionWatch` the executor's tests leave
/// open. The reasoning (contract, regression that breaks it, why the existing
/// test misses it) is in `.vibeflow/audits/never-type-permissoes-1b-audit.md`.
/// No clock and no TCC: the reading and the interval are the test's.
@Suite("Permissions, part 1b audit")
@MainActor
struct PermissionsPart1bAuditTests {

    private static let granted = PermissionReading(microphone: .authorized, accessibilityGranted: true)

    /// The reading and the interval in the test's hands. Each interval stays
    /// open until the test ends it.
    @MainActor
    private final class Clockless {
        var reading: PermissionReading
        var reads = 0
        var intervals = 0
        var changes: [PermissionReading] = []
        var pending: CheckedContinuation<Void, Never>?

        init(_ reading: PermissionReading) { self.reading = reading }

        func read() -> PermissionReading {
            reads += 1
            return reading
        }

        func interval() async {
            intervals += 1
            await withCheckedContinuation { pending = $0 }
        }

        func elapse() -> Bool {
            guard let open = pending else { return false }
            pending = nil
            open.resume()
            return true
        }
    }

    private func watch(_ c: Clockless) -> PermissionWatch {
        PermissionWatch(read: { c.read() },
                        interval: { await c.interval() },
                        onChange: { c.changes.append($0) })
    }

    /// Yields until `condition` holds, bounded by turns, never by time.
    private func turns(until condition: () -> Bool) async {
        var n = 0
        while !condition() && n < 10_000 {
            await Task.yield()
            n += 1
        }
    }

    /// Ends the open interval and waits for the next one, or for the stop.
    private func tick(_ c: Clockless, _ w: PermissionWatch) async throws {
        let before = c.intervals
        try #require(c.elapse(), "no interval was open to end")
        await turns { c.intervals > before || !w.isRunning }
    }

    /// Leaves no continuation waiting: the last interval ends with both granted.
    private func finish(_ c: Clockless, _ w: PermissionWatch) async {
        c.reading = Self.granted
        _ = c.elapse()
        await turns { !w.isRunning }
    }

    /// Accessibility turned on and off again while the microphone stays
    /// denied: the reading goes back to one it already delivered. That one is
    /// a change too, and has to arrive, so the `permissions:` line and the
    /// icon follow it.
    @Test("a reading that goes back to an earlier one is delivered again",
          .timeLimit(.minutes(1)))
    func goingBackIsAChange() async throws {
        let off = PermissionReading(microphone: .denied, accessibilityGranted: false)
        let on = PermissionReading(microphone: .denied, accessibilityGranted: true)
        let c = Clockless(off)
        let w = watch(c)
        w.start()
        await turns { c.pending != nil }

        c.reading = on
        try await tick(c, w)
        c.reading = off
        try await tick(c, w)
        try await tick(c, w)

        #expect(c.changes == [on, off], "going back to the first reading was swallowed: \(c.changes)")
        #expect(w.isRunning, "the microphone is still denied")
        await finish(c, w)
        #expect(c.changes == [on, off, Self.granted])
    }

    /// The microphone denied and never turned on: the watch keeps looking,
    /// once per interval, however long it takes, so the day it is granted the
    /// slash still goes away by itself.
    @Test("a permission missing for many intervals is still watched, one read per interval",
          .timeLimit(.minutes(1)))
    func missingForLongIsStillWatched() async throws {
        let denied = PermissionReading(microphone: .denied, accessibilityGranted: true)
        let c = Clockless(denied)
        let w = watch(c)
        w.start()
        await turns { c.pending != nil }
        let startReads = c.reads

        for _ in 0..<60 { try await tick(c, w) }

        #expect(w.isRunning, "the watch gave up with the microphone still denied")
        #expect(c.changes.isEmpty, "an unchanged reading was delivered: \(c.changes)")
        #expect(c.reads - startReads == 60, "expected one read per interval, got \(c.reads - startReads) in 60")

        await finish(c, w)
        #expect(c.changes == [Self.granted], "the grant after a long wait has to arrive: \(c.changes)")
        #expect(!w.isRunning)
    }
}
