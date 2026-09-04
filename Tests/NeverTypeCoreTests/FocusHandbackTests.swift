import Foundation
import Testing
@testable import NeverTypeCore

/// Giving the focus back after one of this app's windows closes.
///
/// The windows live in the executable target, which a test cannot import. What
/// a test can see of them is the text of their source: the first test here
/// reads `VocabularyWindow.swift` and refuses `NSApp.hide`, the line that hid
/// the orb along with the window (hotfix of 2026-09-04). The behavior itself
/// was verified by hand; this is the oracle that keeps the line from coming
/// back.
@Suite("Focus hand-back")
struct FocusHandbackTests {

    private static var vocabularyWindowSource: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = root.appendingPathComponent("Sources/NeverType/VocabularyWindow.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    @Test("the vocabulary window hands the focus back without hiding the app")
    func vocabularyWindowDoesNotHideTheApp() {
        let source = Self.vocabularyWindowSource
        #expect(!source.isEmpty, "VocabularyWindow.swift was not found from \(#filePath)")
        #expect(!source.contains("NSApp.hide("),
                "NSApp.hide hides every window of the app, the orb included")
        #expect(source.contains("FocusHandback"),
                "the window has to give the focus back through FocusHandback")
    }

    // The rule itself, with the system calls replaced.

    @Test("gives the focus back to the app that was in front, and hides nothing")
    @MainActor
    func givesTheFocusBack() {
        var activated: [pid_t] = []
        var hidden = false
        let handback = FocusHandback(frontmost: { 4242 },
                                     activate: { activated.append($0); return true },
                                     hide: { hidden = true },
                                     own: 1)
        handback.remember()
        #expect(handback.giveBack())
        #expect(activated == [4242])
        #expect(!hidden, "hiding is what took the orb away")
    }

    @Test("hides only when nothing was in front, or the activation is refused")
    @MainActor
    func hidesAsTheFallback() {
        var hidden = 0
        let nothing = FocusHandback(frontmost: { nil }, activate: { _ in true }, hide: { hidden += 1 }, own: 1)
        nothing.remember()
        #expect(!nothing.giveBack())
        #expect(hidden == 1, "with nobody to give the focus to, hiding is still the way out")

        let refused = FocusHandback(frontmost: { 4242 }, activate: { _ in false }, hide: { hidden += 1 }, own: 1)
        refused.remember()
        #expect(!refused.giveBack())
        #expect(hidden == 2, "the system refused the activation, and the fallback took over")
    }

    @Test("never hands the focus to itself")
    @MainActor
    func neverActivatesItself() {
        var activated: [pid_t] = []
        var hidden = false
        let handback = FocusHandback(frontmost: { 7 },
                                     activate: { activated.append($0); return true },
                                     hide: { hidden = true },
                                     own: 7)
        handback.remember()
        #expect(!handback.giveBack())
        #expect(activated.isEmpty, "this app was in front when the window opened: nobody to give the focus back to")
        #expect(hidden)
    }

    @Test("forgets the app after giving the focus back")
    @MainActor
    func forgetsAfterGivingBack() {
        var activated: [pid_t] = []
        let handback = FocusHandback(frontmost: { 4242 },
                                     activate: { activated.append($0); return true },
                                     hide: {},
                                     own: 1)
        handback.remember()
        _ = handback.giveBack()
        _ = handback.giveBack()
        #expect(activated == [4242], "a second close without a new open has nothing remembered")
    }
}
