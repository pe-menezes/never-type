import Testing
@testable import NeverTypeCore

/// Audit probe for never-type-permissoes, part 2b (2026-11-05).
///
/// The reasoning (contract, regression that breaks it, why the existing test
/// misses it) is in `.vibeflow/audits/never-type-permissoes-2b-audit.md`.
/// No clock and no TCC: the reading and the interval are the test's.
@Suite("Permissions, part 2b audit")
@MainActor
struct PermissionsPart2bAuditTests {

    private static let granted = PermissionReading(microphone: .authorized, accessibilityGranted: true)
    private static let noAccessibility = PermissionReading(microphone: .authorized, accessibilityGranted: false)

    /// The reading and the interval in the test's hands. Each interval stays
    /// open until the test ends it.
    @MainActor
    private final class Clockless {
        var reading: PermissionReading
        var changes: [PermissionReading] = []
        var pending: CheckedContinuation<Void, Never>?

        init(_ reading: PermissionReading) { self.reading = reading }

        func interval() async {
            await withCheckedContinuation { pending = $0 }
        }

        func elapse() -> Bool {
            guard let open = pending else { return false }
            pending = nil
            open.resume()
            return true
        }
    }

    /// Yields until `condition` holds, bounded by turns, never by time.
    private func turns(until condition: () -> Bool) async {
        var n = 0
        while !condition() && n < 10_000 {
            await Task.yield()
            n += 1
        }
    }

    /// The end of a dictation slashes the icon and starts the watch, and only
    /// the grant the watch hands over takes the slash away. A person can lose
    /// and get back a permission more than once in one run of the app, and the
    /// grant before it must not swallow this one: the icon would stay slashed
    /// with both granted, with the watch already stopped.
    @Test("each time a permission comes back, the watch hands over the grant, on the first re-read",
          .timeLimit(.minutes(1)))
    func everyReturnIsDelivered() async throws {
        let c = Clockless(Self.noAccessibility)
        let w = PermissionWatch(read: { c.reading },
                                interval: { await c.interval() },
                                onChange: { c.changes.append($0) })

        for cycle in 1...3 {
            c.reading = Self.noAccessibility
            w.start()
            await turns { c.pending != nil }
            try #require(w.isRunning, "cycle \(cycle): with Accessibility missing the watch has to run")
            #expect(c.changes.count == cycle - 1, "cycle \(cycle): starting delivered something: \(c.changes)")

            c.reading = Self.granted
            try #require(c.elapse(), "cycle \(cycle): no interval was open to end")
            await turns { !w.isRunning }

            #expect(!w.isRunning, "cycle \(cycle): both granted and the watch kept running")
            #expect(c.changes.count == cycle, "cycle \(cycle): the grant was swallowed: \(c.changes)")
            #expect(c.changes.last == Self.granted, "cycle \(cycle): \(c.changes)")
        }
    }
}
