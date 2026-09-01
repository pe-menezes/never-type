import CoreGraphics

/// Tells a press that moves the orb apart from a press that opens its menu.
///
/// The orb answers both gestures on the same button, so the only thing that
/// separates them is how far the pointer travelled. Anything under the slop is a
/// click: a press meant as a click still moves a pixel or two on the way down,
/// and without the slop every click would nudge the orb and be read as a drag.
///
/// The rule lives here and not in the view for the same reason as
/// `PasteTarget.decide(_:)`: it can then be exercised without a window, without
/// a mouse and without a clock.
public struct PointerGesture: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The orb never moved, so the press asks for the menu.
        case click
        /// The orb followed the pointer, so the press moved it.
        case drag
    }

    /// Travel, in points, that turns a press into a drag.
    ///
    /// 3 px is the customary number for this in a desktop interface. AppKit does
    /// not publish the value it uses for its own drag sessions, so this one is
    /// chosen, not measured.
    public static let defaultSlop: CGFloat = 3

    private let origin: CGPoint
    private let slop: CGFloat
    private var travelled = false

    public init(origin: CGPoint, slop: CGFloat = PointerGesture.defaultSlop) {
        self.origin = origin
        self.slop = slop
    }

    /// How far the orb should move, or `nil` while the press is still a click.
    ///
    /// Once the pointer has passed the slop the answer stays non-nil even if it
    /// comes back: a press that carried the orb across the screen and ended
    /// where it started still moved it, and opening a menu on top of that would
    /// be a second action nobody asked for.
    public mutating func translation(to point: CGPoint) -> CGVector? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        // Both sides squared, so the comparison never pays for a square root.
        // It also keeps the slop radial: 2 px right and 2 px up is 2.83 px of
        // travel, which is still a click, and comparing each axis on its own
        // would have called it a drag.
        if !travelled { travelled = dx * dx + dy * dy >= slop * slop }
        return travelled ? CGVector(dx: dx, dy: dy) : nil
    }

    /// What the press turned out to be. Read when the button comes back up.
    public var outcome: Outcome { travelled ? .drag : .click }
}
