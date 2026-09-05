import Foundation

/// How far a transcription got, as the overlay's ring reads it.
///
/// A type in Core and not a `var` on the view, because the rule it carries is
/// the part that can be wrong. Whisper's own numbers climb, and the hop does not
/// preserve that: each update crosses to the main actor in its own unstructured
/// task, and those have no ordering guarantee between them, so a 40 arriving
/// after a 50 would run the ring backwards. A view holding one of these cannot
/// walk it back by assigning to it.
///
/// The second thing it guards is lifetime. Clearing the ring only when the
/// overlay leaves the writing state let a late update land after the reset and
/// survive into the next dictation, whose ring then opened part filled, as if
/// transcription had started before the person stopped speaking.
public struct TranscriptionProgress: Equatable, Sendable {
    /// 0 to 1. Never decreases between resets.
    public private(set) var fraction: Double

    public init() { fraction = 0 }

    /// Takes whisper's own scale, 0 to 100.
    ///
    /// Answers whether anything moved, so the caller redraws only when there is
    /// something new to draw. Whisper reports the same number more than once on
    /// a long transcription.
    @discardableResult
    public mutating func advance(percent: Int) -> Bool {
        let next = min(1, max(0, Double(percent) / 100))
        guard next > fraction else { return false }
        fraction = next
        return true
    }

    /// Back to zero for the next dictation. Answers whether anything moved.
    @discardableResult
    public mutating func reset() -> Bool {
        guard fraction != 0 else { return false }
        fraction = 0
        return true
    }

    /// What a screen reader adds to the state's own word, or nil before the
    /// first update, when there is nothing to report yet.
    public var spoken: String? {
        guard fraction > 0 else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }
}
