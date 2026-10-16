import Foundation
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

    // MARK: - What the app draws

    /// Audit A1 of part 1b, sabotage M1: the mapping inverted in the app drew
    /// the slash over a working app and nothing caught it.
    @Test("the normal icon draws the brand, and the slashed one the slashed brand")
    func restingVisual() {
        #expect(StatusIcon.normal.visual == .idle)
        #expect(StatusIcon.slashed.visual == .blocked)
    }

    /// Audit A1 of part 1b, sabotage M5: `.ready` and `.noMetal` swapped in
    /// the app recorded a CPU run as ready, and granting a permission then
    /// cleared the Metal slash.
    @Test("a finished load is ready only with the model loaded and Metal active",
          arguments: [(true, true, ModelState.ready), (true, false, .noMetal),
                      (false, false, .notLoaded), (false, true, .notLoaded)])
    func modelStateFromTheLoad(loaded: Bool, metalActive: Bool, expected: ModelState) {
        #expect(ModelState(loaded: loaded, metalActive: metalActive) == expected,
                "loaded \(loaded), Metal \(metalActive)")
    }

    /// The app's reads at the end of the load, in the test's hands: how many
    /// times each one was made, and the log lines.
    @MainActor
    private final class Load {
        let loaded: Bool
        let metal: Bool
        var loadedReads = 0
        var deviceReads = 0
        var metalReads = 0
        var lines: [String] = []

        init(loaded: Bool, metal: Bool) {
            self.loaded = loaded
            self.metal = metal
        }

        func finish() async -> ModelState {
            await ModelState.afterLoad(
                loaded: { self.loadedReads += 1; return self.loaded },
                devices: { self.deviceReads += 1; return "MTL0, BLAS, CPU" },
                metalActive: { self.metalReads += 1; return self.metal },
                log: { self.lines.append($0) })
        }
    }

    /// Audit A2 of part 1b, sabotages M14 and M15: the condition that keeps
    /// Metal out of a failed load lived in the app, where `if !loaded {` slashed
    /// every working Mac and `metalActive = loaded` hid a CPU run, both green.
    @Test("a model that did not load ends not loaded, and Metal is never asked",
          arguments: [true, false])
    @MainActor
    func afterLoadNotLoaded(metal: Bool) async {
        let load = Load(loaded: false, metal: metal)
        #expect(await load.finish() == .notLoaded)
        #expect(load.loadedReads == 1)
        #expect(load.metalReads == 0, "Metal asked with no model")
        #expect(load.deviceReads == 0)
        #expect(load.lines.isEmpty, "\(load.lines)")
    }

    @Test("a loaded model with Metal is ready, and the log names the devices")
    @MainActor
    func afterLoadReady() async {
        let load = Load(loaded: true, metal: true)
        #expect(await load.finish() == .ready)
        #expect(load.loadedReads == 1 && load.metalReads == 1 && load.deviceReads == 1)
        #expect(load.lines == ["ggml devices: MTL0, BLAS, CPU"])
    }

    @Test("a loaded model without Metal keeps the slash, and the log warns")
    @MainActor
    func afterLoadNoMetal() async {
        let load = Load(loaded: true, metal: false)
        #expect(await load.finish() == .noMetal)
        #expect(load.loadedReads == 1 && load.metalReads == 1 && load.deviceReads == 1)
        #expect(load.lines == [
            "ggml devices: MTL0, BLAS, CPU",
            "WARNING: without Metal, transcription runs on the CPU and is ~11x slower.",
        ])
    }

    /// The watch reads the system through `PermissionReading.current`, which
    /// no test runs (TCC stays out of tests). A constant in either read would
    /// leave the icon as it is forever with every behavior test green, so its
    /// text is held here, as `MenuLayoutTests` holds the executable target.
    @Test("the reading the app watches is the system's, both permissions")
    func currentReadsTheSystem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/NeverTypeCore/StatusIcon.swift"),
                                encoding: .utf8)
        let lines = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        let start = try #require(lines.firstIndex(of: "public static var current: PermissionReading {"))
        #expect(Array(lines[start...].prefix(4)) == [
            "public static var current: PermissionReading {",
            "PermissionReading(microphone: .current,",
            "accessibilityGranted: HotkeyMonitor.hasAccessibilityPermission)",
            "}",
        ])
    }

    /// The case of 2026-10-16 08:28, as the app sees it when the watch hands
    /// over the reading with both granted: the normal icon, drawn now.
    /// Audit A1 of part 1b, sabotages M8 and M2: an early exit on the complete
    /// reading, or the dictation guard inverted, left the slash in place.
    @Test("a reading at rest is drawn by the rule, the grant included")
    func redrawAtRest() {
        #expect(StatusIcon.redraw(permissions: Self.granted, recording: false, transcribing: false,
                                  model: .ready) == .idle)
        #expect(StatusIcon.redraw(permissions: Self.granted, recording: false, transcribing: false,
                                  model: .loading) == .idle)
        #expect(StatusIcon.redraw(permissions: Self.granted, recording: false, transcribing: false,
                                  model: .noMetal) == .blocked)
        #expect(StatusIcon.redraw(permissions: Self.granted, recording: false, transcribing: false,
                                  model: .notLoaded) == .blocked)
        let missing = PermissionReading(microphone: .authorized, accessibilityGranted: false)
        #expect(StatusIcon.redraw(permissions: missing, recording: false, transcribing: false,
                                  model: .ready) == .blocked)
    }

    /// While dictating the icon says recording or transcribing, and the end of
    /// the dictation redraws it; a reading arriving then draws nothing.
    @Test("nothing is drawn while recording or transcribing",
          arguments: [(true, false), (false, true), (true, true)])
    func noRedrawWhileDictating(recording: Bool, transcribing: Bool) {
        for permissions in [Self.granted, PermissionReading(microphone: .denied, accessibilityGranted: false)] {
            for model in [ModelState.loading, .ready, .notLoaded, .noMetal] {
                #expect(StatusIcon.redraw(permissions: permissions, recording: recording,
                                          transcribing: transcribing, model: model) == nil,
                        "\(permissions) with \(model) drew over a dictation")
            }
        }
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
