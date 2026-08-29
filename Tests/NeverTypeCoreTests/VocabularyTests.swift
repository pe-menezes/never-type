import Foundation
import Testing
@testable import NeverTypeCore

/// The two lists solve different problems, and the tests treat them so: the
/// prompt is a hint, the replacement is a guarantee.
@Suite("Vocabulary and replacements")
struct VocabularyTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-vocab-\(UUID().uuidString)")
            .appendingPathComponent("vocabulario.json")
    }

    private func fresh() -> (Vocabulary, URL) {
        let url = tempURL()
        return (Vocabulary(url: url), url)
    }

    // MARK: - Prompt

    @Test("without terms there is no prompt, and whisper runs as always")
    func emptyMeansNoPrompt() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(v.prompt == nil, "an empty prompt would still be a prompt, and would bias the model for nothing")
    }

    @Test("the terms become a sentence, not a raw list")
    func promptReadsAsLanguage() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["NeverType", "whisper.cpp"])
        #expect(v.prompt == "NeverType, whisper.cpp.")
    }

    @Test("an empty or whitespace-only term does not enter the list")
    func blankTermsAreDropped() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["NeverType", "", "   ", "  Pix  "])
        #expect(v.terms == ["NeverType", "Pix"], "and what remains comes without surrounding whitespace")
    }

    // MARK: - Replacements

    // The sentences below stay in Portuguese on purpose: the app only transcribes
    // Portuguese, and these are the real cases (accented word boundary, "PIX"
    // casing, the "vibe flow" mishearing) that motivated the rules under test.

    @Test("the swap happens and respects the case requested in the target")
    func replacesWithRequestedCase() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "transcrição", to: "transação")])
        #expect(v.apply(to: "essa transcrição foi negada") == "essa transação foi negada")
    }

    @Test("the search ignores case, but writes the target exactly")
    func searchIsCaseInsensitive() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "pix", to: "Pix")])
        #expect(v.apply(to: "manda um PIX, um Pix ou um pix") == "manda um Pix, um Pix ou um Pix",
                "fixing a word's case is precisely one of the uses")
    }

    /// Without a word boundary, swapping "ia" for "IA" would wreck "família".
    @Test("only matches whole words")
    func matchesWholeWordsOnly() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "ia", to: "IA")])
        #expect(v.apply(to: "a família ia embora") == "a família IA embora")
    }

    @Test("a special character in the term is treated as text, not as regex")
    func specialCharactersAreLiteral() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "whisper.cpp", to: "whisper.cpp")])
        #expect(v.apply(to: "uses whisperXcpp here") == "uses whisperXcpp here",
                "the dot cannot become a wildcard and match the X")
    }

    @Test("a replacement with an empty source or target does not go in")
    func blankReplacementsAreDropped() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([
            Replacement(from: "", to: "something"),
            Replacement(from: "something", to: ""),
            Replacement(from: "good", to: "great"),
        ])
        #expect(v.replacements == [Replacement(from: "good", to: "great")],
                "an empty source would match everything")
    }

    @Test("several replacements apply in list order")
    func replacementsChain() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([
            Replacement(from: "vibe flow", to: "vibeflow"),
            Replacement(from: "fala flow", to: "NeverType"),
        ])
        #expect(v.apply(to: "o vibe flow e o fala flow") == "o vibeflow e o NeverType")
    }

    @Test("text with nothing to swap comes out identical")
    func untouchedTextIsIdentical() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "pix", to: "Pix")])
        #expect(v.apply(to: "nothing here changes") == "nothing here changes")
    }

    // MARK: - Disk

    @Test("both lists survive quitting and reopening")
    func survivesRestart() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["NeverType"])
        v.setReplacements([Replacement(from: "pix", to: "Pix")])

        let reopened = Vocabulary(url: url)
        #expect(reopened.terms == ["NeverType"])
        #expect(reopened.replacements == [Replacement(from: "pix", to: "Pix")])
    }

    @Test("a corrupt file starts empty instead of breaking")
    func corruptFileStartsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: url)

        let v = Vocabulary(url: url)
        #expect(v.terms.isEmpty)
        #expect(v.prompt == nil)
    }
}
