import Foundation

/// A literal swap applied after transcription.
public struct Replacement: Codable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The two lists that correct what the model writes — and there are two on
/// purpose, because they solve different problems.
///
/// **Terms** become whisper's `initial_prompt`: a recognition hint, which helps
/// the model *hear* the word. It is probabilistic and guarantees nothing, but it
/// also influences punctuation and formatting.
///
/// **Replacements** run afterwards, on the finished text. They are deterministic:
/// "X came out, I wanted Y" always becomes Y. This is what solves the case of a
/// word the model consistently swaps for a similar one.
///
/// Mixing the two into one list would promise a guarantee where none exists.
public final class Vocabulary {
    private let url: URL

    public private(set) var terms: [String] = []
    public private(set) var replacements: [Replacement] = []

    public init(url: URL) {
        self.url = url
        load()
    }

    // MARK: - Editing

    public func setTerms(_ value: [String]) {
        terms = value.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        save()
    }

    public func setReplacements(_ value: [Replacement]) {
        replacements = value
            .map { Replacement(from: $0.from.trimmingCharacters(in: .whitespaces),
                               to: $0.to.trimmingCharacters(in: .whitespaces)) }
            // An empty source would match everything; an empty target is
            // deleting a word, and whoever wants that writes out the whole replacement.
            .filter { !$0.from.isEmpty && !$0.to.isEmpty }
        save()
    }

    // MARK: - Use

    /// Whisper's `initial_prompt`, or `nil` when there are no terms.
    ///
    /// A sentence with commas, not a raw list: the prompt is interpreted as text
    /// that *precedes* the speech, so it works better when it looks like language.
    public var prompt: String? {
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ") + "."
    }

    /// Applies the replacements to the transcribed text.
    ///
    /// Matches whole words and ignores case when searching, but writes exactly
    /// what was asked for in the target — swapping "pix" for "Pix" is precisely
    /// one of the uses. Without the word boundary, swapping "ia" for "IA" would
    /// wreck "família".
    public func apply(to text: String) -> String {
        var output = text
        for replacement in replacements {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: replacement.from) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.to))
        }
        return output
    }

    // MARK: - Disk

    private struct Stored: Codable {
        var terms: [String]
        var replacements: [Replacement]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        terms = stored.terms
        replacements = stored.replacements
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Stored(terms: terms, replacements: replacements)) else { return }
        // Atomic: an interrupted write would leave a truncated JSON, and the
        // whole list would vanish on the next launch.
        try? data.write(to: url, options: .atomic)
    }
}
