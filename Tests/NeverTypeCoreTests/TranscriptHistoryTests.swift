import Foundation
import Testing
@testable import NeverTypeCore

/// The history keeps what the user said. The tests cover the cap, survival
/// across app restarts, and deletion — which is the only way out for whoever no
/// longer wants that on disk.
@Suite("Transcription history")
struct TranscriptHistoryTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-hist-\(UUID().uuidString)")
            .appendingPathComponent("historico.json")
    }

    @Test("the most recent comes first")
    func mostRecentFirst() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        h.add("first")
        h.add("second")
        #expect(h.entries.map(\.text) == ["second", "first"])
        #expect(h.last?.text == "second")
    }

    @Test("empty or whitespace-only text does not go in")
    func emptyIsRejected() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        #expect(h.add("") == false)
        #expect(h.add("   \n  ") == false)
        #expect(h.entries.isEmpty)
    }

    @Test("the text is saved without surrounding whitespace")
    func trimsWhitespace() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        h.add("  dictated text \n")
        #expect(h.last?.text == "dictated text")
    }

    /// It is not "keep everything": going past the cap drops the oldest.
    @Test("the cap drops the oldest, not the newest")
    func limitDropsOldest() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        for i in 1...(TranscriptHistory.limit + 5) { h.add("dictation \(i)") }

        #expect(h.entries.count == TranscriptHistory.limit)
        #expect(h.last?.text == "dictation \(TranscriptHistory.limit + 5)")
        #expect(!h.entries.contains { $0.text == "dictation 1" }, "the oldest has to have dropped")
    }

    /// The reason the file exists: quitting the app cannot erase what was said.
    @Test("survives quitting and reopening the app")
    func survivesRestart() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let primeira = TranscriptHistory(url: url)
        primeira.add("what I said before quitting")

        let depois = TranscriptHistory(url: url)
        #expect(depois.last?.text == "what I said before quitting")
    }

    @Test("clearing deletes the file, not just the memory")
    func clearRemovesTheFile() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let h = TranscriptHistory(url: url)
        h.add("secret")
        #expect(FileManager.default.fileExists(atPath: url.path))

        h.clear()
        #expect(h.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "an empty file named like a history still says a history existed")
        #expect(TranscriptHistory(url: url).entries.isEmpty, "and it does not come back on reopen")
    }

    /// A corrupt file cannot crash the app nor prevent saving afterwards.
    @Test("unreadable JSON starts empty instead of breaking")
    func corruptFileStartsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: url)

        let h = TranscriptHistory(url: url)
        #expect(h.entries.isEmpty)
        h.add("after the corrupt file")
        #expect(h.last?.text == "after the corrupt file")
        #expect(TranscriptHistory(url: url).entries.count == 1, "the new save fixed the file")
    }
}
