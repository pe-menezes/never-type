import Foundation
import ServiceManagement
import Testing
@testable import NeverTypeCore

/// The guard that prevents registering the wrong copy, and the registration's
/// failure paths.
///
/// No test here touches the real `SMAppService`: registering a login item
/// changes the macOS BTM, which is machine state of whoever is running the suite
/// — and unregistering is not always immediate. Every system call comes in
/// through the injected parameters.
@Suite("Open at Login")
struct LoginItemTests {

    private func fakeError(_ message: String) -> NSError {
        NSError(domain: "com.nevertype.tests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - What the system answers

    @Test("the four SMAppService states become the three the interface uses")
    func mapsEveryStatus() {
        #expect(LoginItem.state(from: .enabled) == .on)
        #expect(LoginItem.state(from: .requiresApproval) == .needsApproval,
                "turned off in Settings requires action outside the app, does not collapse into off")
        #expect(LoginItem.state(from: .notRegistered) == .off)
        #expect(LoginItem.state(from: .notFound) == .off,
                "notFound and notRegistered are distinct in the system and the same for the interface")
    }

    @Test("the current state is read from the system, not from a cache")
    func readsStateFromTheSystem() {
        var queries = 0
        let readStatus: () -> SMAppService.Status = { queries += 1; return .enabled }

        #expect(LoginItem.current(status: readStatus) == .on)
        #expect(LoginItem.current(status: readStatus) == .on)
        #expect(queries == 2, "each query asks the system again")
    }

    // MARK: - The path guard

    @Test("accepts the two installed locations and refuses the rest")
    func recognizesTheInstalledLocation() {
        let home = "/Users/someone"

        #expect(LoginItem.isInstalledLocation(bundlePath: "/Applications/NeverType.app", home: home))
        #expect(LoginItem.isInstalledLocation(bundlePath: "/Users/someone/Applications/NeverType.app", home: home),
                "install.sh documents ~/Applications as the fallback for managed machines")
        #expect(LoginItem.isInstalledLocation(bundlePath: "/Applications/NeverType.app/", home: home),
                "a trailing slash is the same place")

        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Users/someone/repo/build/NeverType.app", home: home),
                "the build/ copy is deleted on every build")
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/private/tmp/NeverType.app", home: home))
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Applications/Other.app", home: home))
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Users/someone-else/Applications/NeverType.app", home: home),
                "the ~/Applications that counts is the one of whoever is running")
    }

    /// The point of the DoD: the refusal happens **before** talking to the system.
    /// Registering and then regretting it does not undo — BTM has already recorded it.
    @Test("outside the installed location, refuses without calling the registrar")
    func refusesWithoutRegistering() {
        var called = false
        let outcome = LoginItem.enable(
            bundlePath: "/Users/someone/repo/build/NeverType.app",
            home: "/Users/someone",
            register: { called = true })

        #expect(!called, "the registrar cannot be called outside the installed location")
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains("build/NeverType.app"), "the message says where the copy is")
        #expect(reason.contains("scripts/install.sh"), "the message names the way out")
    }

    @Test("in the installed location, registers and returns the new state")
    func registersInTheRightPlace() {
        var called = false
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/someone",
            register: { called = true },
            status: { .enabled })

        #expect(called)
        #expect(outcome == .changed(.on))
    }

    /// The state comes from asking again, not from assuming it worked.
    @Test("a register that passes but does not turn on returns the real state")
    func doesNotAssumeRegisteringTurnedItOn() {
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/someone",
            register: {},
            status: { .requiresApproval })

        #expect(outcome == .changed(.needsApproval),
                "register() without an error does not prove it turned on — the status answers")
    }

    // MARK: - The failure paths

    @Test("a register that throws becomes a refusal with the system's reason")
    func registerThatThrows() {
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/someone",
            register: { throw self.fakeError("Operation not permitted") })

        #expect(outcome == .refused("macOS refused to register: Operation not permitted"))
    }

    @Test("an unregister that throws becomes a refusal with the system's reason")
    func unregisterThatThrows() {
        let outcome = LoginItem.disable(
            unregister: { throw self.fakeError("Operation not permitted") })

        #expect(outcome == .refused("macOS refused to unregister: Operation not permitted"))
    }

    /// Turning off has no path guard on purpose: BTM indexes by bundle ID,
    /// unregistering from any copy clears them all, and blocking the turn-off
    /// would trap the user in a state they want out of.
    @Test("turning off works from any copy")
    func turnsOffFromAnywhere() {
        var called = false
        let outcome = LoginItem.disable(
            unregister: { called = true },
            status: { .notRegistered })

        #expect(called)
        #expect(outcome == .changed(.off))
    }
}
