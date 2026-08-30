import AppKit
import Carbon.HIToolbox
import Testing
@testable import NeverTypeCore

/// Passed by every test below that is not about the focus check.
///
/// The default of `insert` asks the Accessibility API what has the focus on the
/// machine running the suite, and the answer depends on which window happened to
/// be in front. The pasteboard is a named instance here for the same reason: a
/// test may not read the state of whoever is running it.
///
/// A free function, isolated to no actor, so it goes in as a plain function
/// reference the way `IsSecureEventInputEnabled` does in the code under test.
private func somewhereToPaste() -> PasteTarget.Decision { .editable("AXTextField") }

/// The central contract: we touch the user's pasteboard, so we give back what was
/// there — including when the insertion fails midway.
///
/// Uses its own named pasteboard, never `.general`: a test that hijacks the
/// clipboard of whoever is running the suite is hostile.
@Suite("Text insertion at the cursor")
@MainActor
struct TextInjectorTests {

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.nevertype.tests.\(UUID().uuidString)"))
    }

    @Test("the previous contents come back after the insertion")
    func restoresPreviousContent() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("what was there before", forType: .string)

        let outcome = TextInjector.insert("dictated text", pasteboard: pb, paste: { true },
                                          focus: somewhereToPaste)
        #expect(outcome == .inserted)
        #expect(pb.string(forType: .string) == "dictated text", "during the insertion the text is the dictation")

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "what was there before",
                "the previous contents have to come back")
    }

    /// The path that matters most: if the paste fails, the pasteboard cannot be
    /// left with the dictated text in place of what the user had copied.
    @Test("restores the contents even when the paste fails")
    func restoresEvenWhenPasteFails() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("important content", forType: .string)

        let outcome = TextInjector.insert("dictated text", pasteboard: pb, paste: { false },
                                          focus: somewhereToPaste)
        #expect(outcome == .failed("could not send ⌘V"))

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "important content",
                "failing to paste cannot cost the user their clipboard")
    }

    /// Keeping only the string would lose images, files, HTML — everything that
    /// is not plain text.
    @Test("preserves types that are not text")
    func preservesNonTextTypes() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        let html = "<b>bold</b>"
        pb.clearContents()
        let original = NSPasteboardItem()
        original.setString("plain text", forType: .string)
        original.setString(html, forType: .html)
        #expect(pb.writeObjects([original]))

        TextInjector.insert("dictation", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))

        #expect(pb.string(forType: .string) == "plain text")
        #expect(pb.string(forType: .html) == html, "the HTML has to survive")
    }

    @Test("a pasteboard empty before stays empty after")
    func emptyStaysEmpty() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        TextInjector.insert("dictation", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))

        #expect(pb.string(forType: .string) == nil, "the dictated text cannot be left over")
    }

    /// Well-behaved clipboard managers honor this mark and do not record the item
    /// in their history. Without it, every dictation would survive the
    /// restoration inside Raycast or Maccy.
    @Test("the item is marked as concealed for clipboard managers")
    func marksItemConcealed() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        TextInjector.insert("dictated secret", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        let types = pb.pasteboardItems?.first?.types ?? []
        #expect(types.contains(TextInjector.concealed))
    }

    /// The race the audit reproduced: two dictations less than the restore delay
    /// apart left the first one's text in place of the user's contents,
    /// permanently.
    @Test("two dictations in a row restore the original contents, not the first one's")
    func consecutiveInsertsRestoreTheOriginal() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("the user's original content", forType: .string)

        TextInjector.insert("first dictation", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        try await Task.sleep(for: .seconds(0.25))
        TextInjector.insert("second dictation", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        #expect(pb.string(forType: .string) == "second dictation")

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.6))
        #expect(pb.string(forType: .string) == "the user's original content",
                "got \(pb.string(forType: .string) ?? "nil") — the first dictation's text cannot be left over")
    }

    /// The restoration was unconditional: anything the user copied in the 600 ms
    /// after a dictation was reverted.
    @Test("does not undo what the user copied after the dictation")
    func doesNotClobberLaterCopy() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("old", forType: .string)

        TextInjector.insert("dictation", pasteboard: pb, paste: { true },
                            focus: somewhereToPaste)
        try await Task.sleep(for: .seconds(0.2))

        // The user copies something else before the restoration fires.
        pb.clearContents()
        pb.setString("just copied this", forType: .string)

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.6))
        #expect(pb.string(forType: .string) == "just copied this",
                "the restoration cannot run over a newer copy")
    }

    /// With secure input on the app does not paste — so the text has to stay on
    /// the pasteboard, which is what the spec asks for. The previous version
    /// returned before touching the pasteboard and left nothing.
    @Test("secure input leaves the text on the pasteboard instead of pasting")
    func secureInputLeavesTextBehind() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("previous content", forType: .string)

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          secureInput: { true })

        #expect(outcome == .blockedBySecureInput)
        #expect(!pasted, "with secure input on the app does not post the ⌘V")
        #expect(pb.string(forType: .string) == "dictated text",
                "the text has to stay available for the user to paste")

        // Without a paste there is no restoration: the text needs to remain.
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "dictated text",
                "without pasting, the text cannot be erased by a restoration")
    }

    // MARK: - How long the clipboard is held (backlog D1)

    /// 0.6 s is the behavior that has been in use, so an installation that never
    /// heard of the key keeps it.
    @Test("without a stored preference the delay is the 0.6 s already in use")
    func delayFallsBackToTheDefault() {
        #expect(TextInjector.resolvedRestoreDelay(nil) == 0.6)
        #expect(TextInjector.defaultRestoreDelay == 0.6)
    }

    @Test("a stored delay inside the range is used as given")
    func storedDelayIsUsed() {
        #expect(TextInjector.resolvedRestoreDelay(1.5) == 1.5)
        #expect(TextInjector.resolvedRestoreDelay(0.1) == 0.1)
        #expect(TextInjector.resolvedRestoreDelay(5.0) == 5.0)
    }

    /// Both ends cost the person something real. A zero restores in the same run
    /// loop turn and the paste lands with what they had copied before; a typo of
    /// 600 holds their clipboard for ten minutes.
    @Test("a delay outside the range is held to the ends")
    func delayIsClamped() {
        #expect(TextInjector.resolvedRestoreDelay(0) == TextInjector.restoreDelayRange.lowerBound)
        #expect(TextInjector.resolvedRestoreDelay(-3) == TextInjector.restoreDelayRange.lowerBound)
        #expect(TextInjector.resolvedRestoreDelay(600) == TextInjector.restoreDelayRange.upperBound)
    }

    /// `min`/`max` on a NaN answer whatever the argument order says, which would
    /// put a NaN into `asyncAfter` and schedule a restoration that never fires.
    @Test("a delay that is not a finite number falls back to the default")
    func nonFiniteDelayFallsBack() {
        #expect(TextInjector.resolvedRestoreDelay(Double.nan) == TextInjector.defaultRestoreDelay)
        #expect(TextInjector.resolvedRestoreDelay(Double.infinity) == TextInjector.defaultRestoreDelay)
    }

    // MARK: - Where the ⌘V is going (backlog D2)

    /// The defect: the ⌘V used to go out wherever the focus was, and on a button
    /// or an open menu that is an arbitrary shortcut in the app in front.
    @Test("with a focus that takes no text the ⌘V is not posted")
    func doesNotPasteIntoANonEditableFocus() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("previous content", forType: .string)

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          focus: { .notEditable("AXButton") })

        #expect(outcome == .noEditableField("AXButton"))
        #expect(!pasted, "there was nowhere for the text to land")
        #expect(pb.string(forType: .string) == "dictated text",
                "the text has to stay available for the person to paste")

        // No paste means no restoration was scheduled, the same as secure input.
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "dictated text",
                "without pasting, nothing may come along and erase the text")
    }

    @Test("with an editable focus the paste happens as before")
    func pastesIntoAnEditableFocus() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          focus: { .editable("AXTextField") })
        #expect(outcome == .inserted)
        #expect(pasted)
    }

    /// The rule that keeps this check from being worse than the defect: an
    /// Accessibility error, a missing permission and an element nobody
    /// recognizes all reach here as `unknown`, and `unknown` pastes.
    @Test("a focus the system could not classify still gets the paste")
    func pastesWhenTheFocusIsUnknown() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          focus: { .unknown("AXFocusedUIElement failed (-25204)") })
        #expect(outcome == .inserted)
        #expect(pasted, "an app that goes mute after a dictation looks broken")
    }

    // MARK: - The text reaches the clipboard before the ⌘V goes out

    /// The pasteboard was already cleared at this point, so a ⌘V posted after a
    /// write that did not land would paste whatever is sitting there, into the
    /// person's document. It is the damage of D1 arriving by another road.
    @Test("no ⌘V when the text did not come back from the clipboard")
    func doesNotPasteWhenTheWriteDidNotLand() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("important content", forType: .string)

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          focus: somewhereToPaste,
                                          readBack: { _ in nil })

        #expect(outcome == .failed("the text did not reach the clipboard"))
        #expect(!pasted, "posting the ⌘V here would paste the wrong thing")
        #expect(pb.string(forType: .string) == "important content",
                "the contents come back on this path too, with no waiting")
    }

    @Test("text that comes back different is treated as not having landed")
    func rejectsAMismatchedReadBack() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        var pasted = false
        let outcome = TextInjector.insert("dictated text", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          focus: somewhereToPaste,
                                          readBack: { _ in "something else entirely" })
        #expect(outcome == .failed("the text did not reach the clipboard"))
        #expect(!pasted)
    }

    @Test("empty text does not touch the pasteboard")
    func emptyTextIsNoop() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("untouched", forType: .string)

        #expect(TextInjector.insert("", pasteboard: pb, paste: { true }) == .failed("empty text"))
        #expect(pb.string(forType: .string) == "untouched")
    }
}
