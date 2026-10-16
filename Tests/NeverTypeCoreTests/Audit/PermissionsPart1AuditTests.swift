import AVFoundation
import Foundation
import Testing
@testable import NeverTypeCore

/// Audit probes for never-type-permissoes, part 1 (2026-10-15).
///
/// Each one holds a behavior the executor's tests leave open. The reasoning
/// (contract, regression that breaks it, why the existing test misses it) is in
/// `.vibeflow/audits/never-type-permissoes-1-audit.md`.
@Suite("Permissions, part 1 audit")
struct PermissionsPart1AuditTests {

    // MARK: - The system status mapping

    /// The executor's tests build `MicrophoneAccess` by its cases and never go
    /// through `init(_:)`, so a swapped arm here (not determined read as
    /// denied, the bug this part fixes) would reach the trigger and the log
    /// with every test green.
    @Test("each system microphone status maps to its own answer",
          arguments: [
            (AVAuthorizationStatus.authorized, MicrophoneAccess.authorized),
            (.notDetermined, .notDetermined),
            (.denied, .denied),
            (.restricted, .restricted),
          ])
    func systemStatusMapsOneToOne(status: AVAuthorizationStatus, expected: MicrophoneAccess) {
        #expect(MicrophoneAccess(status) == expected,
                "status \(status.rawValue): expected \(expected), got \(MicrophoneAccess(status))")
    }

    /// A status a future macOS adds must never start a recording, and must not
    /// be read as "ask again" either, which would leave the trigger silent.
    @Test("a microphone status this build does not know is treated as denied")
    func unknownStatusIsDenied() throws {
        let unknown = try #require(AVAuthorizationStatus(rawValue: 99))
        let access = MicrophoneAccess(unknown)

        #expect(access == .denied, "expected denied, got \(access)")
        #expect(DictationAttempt.decide(microphone: access, accessibilityAuthorized: true)
                == .showMicrophoneWarning)
    }

    // MARK: - Launch order, with the answer arriving off the main thread

    @MainActor
    private final class Calls {
        var steps: [String] = []
        var accessibilityOnMain: Bool?
    }

    /// The TCC answer arrives on a background queue (`docs/pitfalls.md`, "A
    /// closure inside a `@MainActor` method inherits the isolation"), and the
    /// path only runs while the microphone is not determined. The executor's
    /// test resumes the prompt from the main actor, so it cannot tell whether
    /// what comes after the answer still runs on main.
    @Test("an answer that arrives off the main thread still asks Accessibility on main, after it")
    @MainActor
    func answerFromBackgroundQueue() async {
        let calls = Calls()
        await LaunchPermissions.run(
            microphone: { .notDetermined },
            accessibilityGranted: {
                calls.steps.append("check accessibility")
                return false
            },
            requestMicrophone: {
                calls.steps.append("ask microphone")
                await withCheckedContinuation { (answer: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async { answer.resume() }
                }
                calls.steps.append("microphone answered")
            },
            requestAccessibility: {
                calls.accessibilityOnMain = Thread.isMainThread
                calls.steps.append("ask accessibility")
            })

        #expect(calls.steps == ["ask microphone", "microphone answered",
                                "check accessibility", "ask accessibility"],
                "got \(calls.steps)")
        #expect(calls.accessibilityOnMain == true,
                "Accessibility was asked off the main thread")
    }

    // MARK: - The log line

    /// A reading that goes back to an earlier value is a change, and the log has
    /// to say so. The executor's sequence never comes back to a value it already
    /// wrote, so a log that remembered every line ever written (instead of the
    /// last one) would pass it and hide "granted, then revoked, then granted".
    @Test("going back to an earlier reading writes it again")
    func returningReadingIsWritten() {
        var log = PermissionLog()

        let first = log.lineIfChanged(microphone: .authorized, accessibilityGranted: true)
        let revoked = log.lineIfChanged(microphone: .denied, accessibilityGranted: true)
        let back = log.lineIfChanged(microphone: .authorized, accessibilityGranted: true)

        #expect(first == "permissions: microphone=authorized accessibility=granted")
        #expect(revoked == "permissions: microphone=denied accessibility=granted")
        #expect(back == "permissions: microphone=authorized accessibility=granted",
                "the reading came back and was not written: \(back ?? "nil")")
    }

    // MARK: - verify-install.sh reads what the app writes

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Audit
        .deletingLastPathComponent() // NeverTypeCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    private struct Run {
        let status: Int32
        let output: String
    }

    /// Runs the script with a temporary HOME holding only `nevertype.log`.
    /// Everything else it checks (/Applications, the process, the model, which
    /// is never in the temporary HOME) depends on the machine, so the probes
    /// compare runs with each other and never against a fixed exit code.
    private static func verify(log: String?) throws -> Run {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let support = home.appendingPathComponent("Library/Application Support/NeverType")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if let log {
            try log.write(to: support.appendingPathComponent("nevertype.log"),
                          atomically: true, encoding: .utf8)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRoot.appendingPathComponent("scripts/verify-install.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let raw = String(decoding: data, as: UTF8.self)
        // Drop the color codes of info/ok/warn.
        let plain = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "",
                                             options: .regularExpression)
        return Run(status: process.terminationStatus, output: plain)
    }

    /// A log in the format `log(_:)` in `main.swift` writes: every line starts
    /// with `nevertype: ` (349 of 349 lines in the installed app's log,
    /// measured 2026-10-15). The permissions line itself comes from the Core
    /// formatter, so a word renamed on one side and not the other shows up here.
    private static func appLog(_ readings: [(MicrophoneAccess, Bool)]) -> String {
        var lines = ["nevertype: ready. trigger: Right ⌘ · hands-free: on"]
        for (mic, ax) in readings {
            lines.append("nevertype: " + PermissionLog.line(microphone: mic, accessibilityGranted: ax))
        }
        lines.append("nevertype: model: loaded")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The script reached its last decision, instead of dying under
    /// `set -euo pipefail` in the middle of the permissions section.
    private static func ranToTheEnd(_ run: Run) -> Bool {
        run.output.contains("structure verified") || run.output.contains("check(s) failed")
    }

    /// The script's closing verdict: "N check(s) failed" or "structure
    /// verified". The count is the sensitive part: with the model absent every
    /// run already fails, so a permission promoted to a problem shows up as one
    /// more check failed, not as a different exit code.
    private static func verdict(_ run: Run) -> String {
        run.output.split(separator: "\n")
            .last { $0.contains("check(s) failed") || $0.contains("structure verified") }
            .map(String.init) ?? ""
    }

    private static func permissionsSection(_ run: Run) -> String {
        guard let start = run.output.range(of: "Permissions (as NeverType last read them)") else { return "" }
        let rest = run.output[start.upperBound...]
        let end = rest.range(of: "==>")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// `update.sh` runs this script, so a permission still being granted must
    /// never turn an update into a failure. With the model absent from the
    /// temporary HOME every run fails the same way, which is why reaching the
    /// end is checked apart: a crash in the section would also exit 1.
    @Test("no permission reading changes the exit code or the count of problems, and every one reaches the end")
    func exitCodeIgnoresPermissions() throws {
        var logs: [(String, String?)] = [("no log", nil), ("no permissions line", Self.appLog([]))]
        for mic in MicrophoneAccess.allCases {
            for ax in [true, false] {
                logs.append(("\(mic) / \(ax)", Self.appLog([(mic, ax)])))
            }
        }

        let runs = try logs.map { ($0.0, try Self.verify(log: $0.1)) }
        let reference = runs[0].1
        for (name, run) in runs {
            #expect(run.status == reference.status,
                    "\(name): exit \(run.status), the run with no log exited \(reference.status)")
            #expect(Self.ranToTheEnd(run), "\(name): the script stopped early:\n\(run.output)")
            #expect(Self.verdict(run) == Self.verdict(reference),
                    "\(name): \"\(Self.verdict(run))\", the run with no log said \"\(Self.verdict(reference))\"")
        }
    }

    /// The words the script prints for each reading, from the line the Core
    /// formats. The executor proved the script by hand, once, with lines it
    /// typed; nothing in the suite ties the two sides.
    @Test("each reading of the app's line gets its own verdict in the script",
          arguments: [
            (MicrophoneAccess.authorized, true, ["ok microphone: authorized", "ok accessibility: granted"]),
            (.notDetermined, true, ["microphone: never answered", "about\n      10 seconds", "ok accessibility: granted"]),
            (.denied, false, ["microphone: denied", "accessibility: missing"]),
            (.restricted, true, ["microphone: restricted", "ok accessibility: granted"]),
          ])
    func scriptReadsTheCoreLine(mic: MicrophoneAccess, ax: Bool, expected: [String]) throws {
        let run = try Self.verify(log: Self.appLog([(mic, ax)]))
        let section = Self.permissionsSection(run)

        for phrase in expected {
            #expect(section.contains(phrase), "\(mic)/\(ax): missing \"\(phrase)\" in:\n\(section)")
        }
        #expect(!section.contains("unreadable"), "\(mic)/\(ax): the script could not read the line:\n\(section)")
        #expect(!section.contains("no permissions line"), "\(mic)/\(ax): the line was not found:\n\(section)")
    }

    /// The log keeps every reading of the session; only the newest one is the
    /// state. Granted after being denied must read as granted.
    @Test("the script reads the last permissions line, not the first")
    func lastLineWins() throws {
        let run = try Self.verify(log: Self.appLog([(.notDetermined, false), (.denied, false), (.authorized, true)]))
        let section = Self.permissionsSection(run)

        #expect(section.contains("ok microphone: authorized"), "got:\n\(section)")
        #expect(section.contains("ok accessibility: granted"), "got:\n\(section)")
        #expect(!section.contains("denied"), "an older line was read:\n\(section)")
    }
}
