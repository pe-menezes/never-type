import AppKit
import Carbon.HIToolbox
import Testing
@testable import NeverTypeCore

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

        let outcome = TextInjector.insert("dictated text", pasteboard: pb, paste: { true })
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

        let outcome = TextInjector.insert("dictated text", pasteboard: pb, paste: { false })
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

        TextInjector.insert("dictation", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))

        #expect(pb.string(forType: .string) == "plain text")
        #expect(pb.string(forType: .html) == html, "the HTML has to survive")
    }

    @Test("a pasteboard empty before stays empty after")
    func emptyStaysEmpty() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        TextInjector.insert("dictation", pasteboard: pb, paste: { true })
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

        TextInjector.insert("dictated secret", pasteboard: pb, paste: { true })
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

        TextInjector.insert("first dictation", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(0.25))
        TextInjector.insert("second dictation", pasteboard: pb, paste: { true })
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

        TextInjector.insert("dictation", pasteboard: pb, paste: { true })
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
