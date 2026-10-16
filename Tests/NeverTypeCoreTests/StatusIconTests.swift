import Testing
@testable import NeverTypeCore

/// The resting icon and the watch that re-reads the permissions.
///
/// The case behind both, 2026-10-16 08:28: Accessibility was turned on in
/// System Settings and the menu bar icon stayed slashed, both permissions
/// granted, until the first trigger. Nothing read the permissions again after
/// launch, so only a key press redrew the icon.
@Suite("Status icon")
struct StatusIconTests {

    private static let granted = PermissionReading(microphone: .authorized, accessibilityGranted: true)

    // MARK: - The resting icon

    @Test("both permissions granted and the model loaded or loading draw the normal icon",
          arguments: [ModelState.ready, .loading])
    func grantedAndModelFine(model: ModelState) {
        #expect(StatusIcon.resting(permissions: Self.granted, model: model) == .normal)
    }

    /// The slash that does not come from a permission stays: granting both
    /// must not hide a model that failed to load or a missing Metal device
    /// (audit L6 of part 1, where asking again drew the normal icon over it).
    @Test("a model that failed to load, or no Metal, keeps the slash with both granted",
          arguments: [ModelState.notLoaded, .noMetal])
    func modelFailureKeepsTheSlash(model: ModelState) {
        #expect(StatusIcon.resting(permissions: Self.granted, model: model) == .slashed)
    }

    @Test("any permission missing slashes the icon, whatever the model",
          arguments: [
            PermissionReading(microphone: .authorized, accessibilityGranted: false),
            PermissionReading(microphone: .notDetermined, accessibilityGranted: true),
            PermissionReading(microphone: .denied, accessibilityGranted: true),
            PermissionReading(microphone: .restricted, accessibilityGranted: true),
            PermissionReading(microphone: .denied, accessibilityGranted: false),
          ],
          [ModelState.ready, .loading, .notLoaded, .noMetal])
    func missingPermissionSlashes(permissions: PermissionReading, model: ModelState) {
        #expect(StatusIcon.resting(permissions: permissions, model: model) == .slashed,
                "\(permissions) with \(model) drew the normal icon")
    }

    @Test("a reading is complete only with the microphone authorized and Accessibility granted")
    func completeReading() {
        #expect(Self.granted.isComplete)
        for microphone in MicrophoneAccess.allCases where microphone != .authorized {
            #expect(!PermissionReading(microphone: microphone, accessibilityGranted: true).isComplete)
        }
        #expect(!PermissionReading(microphone: .authorized, accessibilityGranted: false).isComplete)
    }

    // MARK: - The watch

    /// The system reading and the interval, both in the test's hands. Each
    /// interval is held open until the test ends it, so the re-reads advance
    /// one at a time and no clock is read.
    @MainActor
    private final class Ticks {
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

        /// Ends the open interval. Returns whether there was one.
        @discardableResult
        func elapse() -> Bool {
            guard let open = pending else { return false }
            pending = nil
            open.resume()
            return true
        }
    }

    @MainActor
    private func watch(_ ticks: Ticks) -> PermissionWatch {
        PermissionWatch(read: { ticks.read() },
                        interval: { await ticks.interval() },
                        onChange: { ticks.changes.append($0) })
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

    /// One re-read: ends the open interval and waits until the watch is in
    /// the next one or has stopped.
    @MainActor
    private func advance(_ ticks: Ticks, _ watch: PermissionWatch) async throws {
        let before = ticks.intervals
        try #require(ticks.elapse(), "no interval was open to end")
        await turns { ticks.intervals > before || !watch.isRunning }
    }

    /// A test that leaves the watch running ends its interval with nothing
    /// missing, so no continuation is left waiting (audit L4 of part 1: a
    /// `.timeLimit` does not end a test stuck on one).
    @MainActor
    private func finish(_ ticks: Ticks, _ watch: PermissionWatch) async {
        ticks.reading = Self.granted
        ticks.elapse()
        await turns { !watch.isRunning }
    }

    @Test("the watch stops once both permissions are granted", .timeLimit(.minutes(1)))
    @MainActor
    func stopsWhenGranted() async throws {
        let ticks = Ticks(PermissionReading(microphone: .authorized, accessibilityGranted: false))
        let watch = watch(ticks)
        watch.start()
        await turns { ticks.pending != nil }
        try #require(watch.isRunning, "with Accessibility missing the watch has to run")
        try #require(ticks.pending != nil, "the first interval never started")

        try await advance(ticks, watch)
        #expect(watch.isRunning)
        #expect(ticks.changes.isEmpty, "nothing changed and a change came: \(ticks.changes)")

        ticks.reading = Self.granted
        try await advance(ticks, watch)
        #expect(!watch.isRunning, "both granted and the watch kept running")
        #expect(ticks.changes == [Self.granted], "the grant has to arrive: \(ticks.changes)")

        let intervals = ticks.intervals
        for _ in 0..<100 { await Task.yield() }
        #expect(ticks.intervals == intervals, "a stopped watch started another interval")
        #expect(ticks.pending == nil)
    }

    @Test("the watch does not start with nothing missing", .timeLimit(.minutes(1)))
    @MainActor
    func doesNotStartWhenGranted() async {
        let ticks = Ticks(Self.granted)
        let watch = watch(ticks)
        watch.start()
        for _ in 0..<100 { await Task.yield() }
        #expect(!watch.isRunning)
        #expect(ticks.intervals == 0, "an interval started with both granted")
        #expect(ticks.changes.isEmpty)
    }

    @Test("each change in the reading arrives once, and an unchanged one never",
          .timeLimit(.minutes(1)))
    @MainActor
    func eachChangeOnce() async throws {
        let ticks = Ticks(PermissionReading(microphone: .notDetermined, accessibilityGranted: false))
        let watch = watch(ticks)
        watch.start()
        watch.start()
        await turns { ticks.pending != nil }
        for _ in 0..<100 { await Task.yield() }
        #expect(ticks.intervals == 1, "starting twice runs two loops: \(ticks.intervals) intervals")

        let denied = PermissionReading(microphone: .denied, accessibilityGranted: false)
        ticks.reading = denied
        try await advance(ticks, watch)
        try await advance(ticks, watch)
        #expect(ticks.changes == [denied], "expected the change once: \(ticks.changes)")

        let deniedWithAX = PermissionReading(microphone: .denied, accessibilityGranted: true)
        ticks.reading = deniedWithAX
        try await advance(ticks, watch)
        try await advance(ticks, watch)
        try await advance(ticks, watch)
        #expect(ticks.changes == [denied, deniedWithAX], "expected each change once: \(ticks.changes)")
        #expect(watch.isRunning, "the microphone is still denied")

        await finish(ticks, watch)
        #expect(ticks.changes == [denied, deniedWithAX, Self.granted])
    }

    /// A permission taken away in System Settings after the watch stopped:
    /// the next start has to watch again, so the slash goes away once it is
    /// turned back on.
    @Test("a stopped watch starts again when a permission goes missing", .timeLimit(.minutes(1)))
    @MainActor
    func startsAgainAfterStopping() async throws {
        let ticks = Ticks(PermissionReading(microphone: .authorized, accessibilityGranted: false))
        let watch = watch(ticks)
        watch.start()
        await turns { ticks.pending != nil }
        await finish(ticks, watch)
        try #require(!watch.isRunning)

        ticks.reading = PermissionReading(microphone: .authorized, accessibilityGranted: false)
        watch.start()
        await turns { ticks.pending != nil }
        #expect(watch.isRunning)
        await finish(ticks, watch)
        #expect(!watch.isRunning)
    }
}
