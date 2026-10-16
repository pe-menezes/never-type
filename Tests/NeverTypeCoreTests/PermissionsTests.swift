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

        init(microphone: MicrophoneAccess, accessibility: Bool) {
            self.microphone = microphone
            self.accessibility = accessibility
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
                await withCheckedContinuation { journal.pendingAnswer = $0 }
                journal.steps.append("microphone answered")
            },
            requestAccessibility: { journal.steps.append("ask accessibility") })
    }

    /// The race this replaced: the microphone prompt was started and left
    /// running while the Accessibility one opened on top of it. Here the
    /// microphone prompt is held open by the test, and while it is open the
    /// rule must not even look at Accessibility.
    @Test("with the microphone unanswered, Accessibility waits for the answer")
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

    @Test("a microphone already answered is not asked again at launch",
          arguments: [MicrophoneAccess.authorized, .denied, .restricted])
    @MainActor
    func answeredMicrophoneIsNotAsked(access: MicrophoneAccess) async {
        let journal = Journal(microphone: access, accessibility: false)
        await launch(journal)

        #expect(journal.steps == ["check accessibility", "ask accessibility"],
                "\(access): got \(journal.steps)")
    }

    @Test("Accessibility already granted is not asked for")
    @MainActor
    func grantedAccessibilityIsNotAsked() async {
        let journal = Journal(microphone: .authorized, accessibility: true)
        await launch(journal)

        #expect(journal.steps == ["check accessibility"])
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
