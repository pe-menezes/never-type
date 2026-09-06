import Foundation

/// Owns the active inference so late callbacks cannot update a later dictation.
public struct TranscriptionSession: Sendable {
    private var active: UUID?

    public init() {}

    /// Recording must wait until the current result has been delivered.
    public var isTranscribing: Bool { active != nil }

    /// Returns a token only when no inference is already active.
    public mutating func begin() -> UUID? {
        guard active == nil else { return nil }
        let token = UUID()
        active = token
        return token
    }

    /// Progress crosses to the main actor asynchronously and can arrive late.
    public func accepts(_ token: UUID) -> Bool { active == token }

    /// A stale completion must leave the active inference intact.
    @discardableResult
    public mutating func finish(_ token: UUID) -> Bool {
        guard accepts(token) else { return false }
        active = nil
        return true
    }
}
