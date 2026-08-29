import Foundation

/// A saved transcription.
public struct TranscriptEntry: Codable, Equatable, Sendable {
    public let text: String
    public let date: Date

    public init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

/// The history of the last transcriptions.
///
/// There used to be only the last one, in an `ultima-transcricao.txt`, and it
/// served as a safety net for when the paste landed nowhere. One dictation after
/// another erased the previous one.
///
/// This is a record of what the user said, so three decisions are deliberate and
/// not inherited defaults:
///
/// - **Cap of 30.** It is not "keep everything": past 30, the oldest drops off.
/// - **Stays in plain text on disk**, inside the app's own Application Support.
///   Encrypting would require a key, and the key would live next to the file on
///   the same machine — ceremony with no gain. Whoever has local access to the
///   account already reads `last.wav`, which is the whole recording.
/// - **Can be deleted**, from the menu, without hunting for a file.
public final class TranscriptHistory {
    /// How many entries survive. Above this, the oldest goes.
    public static let limit = 30

    private let url: URL
    /// Most recent first: it is the order the menu shows and the one "the last"
    /// is read in.
    public private(set) var entries: [TranscriptEntry] = []

    public init(url: URL) {
        self.url = url
        load()
    }

    public var last: TranscriptEntry? { entries.first }

    /// Saves a new transcription. Empty text does not go in.
    @discardableResult
    public func add(_ text: String, at date: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        entries.insert(TranscriptEntry(text: trimmed, date: date), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
        return true
    }

    public func clear() {
        entries.removeAll()
        // Removes the file, not just the contents: an empty file named like a
        // history still says a history existed.
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        // An unreadable history cannot crash the app nor erase what comes after:
        // it starts empty and the first save overwrites it.
        guard let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else { return }
        entries = Array(decoded.prefix(Self.limit))
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        // Atomic: a write interrupted midway would leave a truncated JSON, and
        // the whole history would be discarded on the next launch.
        try? data.write(to: url, options: .atomic)
    }
}
