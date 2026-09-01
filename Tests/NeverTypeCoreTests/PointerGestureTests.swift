import CoreGraphics
import Testing
@testable import NeverTypeCore

/// The click against the drag, with no window, no mouse and no clock.
///
/// The orb has one button for two actions, and everything that separates them is
/// in this rule. What a test cannot do is press it: the coordinates here stand
/// for the pointer positions AppKit would report.
@Suite("Click against drag on the orb")
struct PointerGestureTests {

    @Test("a press that stays inside the slop is a click, and the orb never moves")
    func pressInsideTheSlopIsAClick() {
        var gesture = PointerGesture(origin: CGPoint(x: 100, y: 100))

        let moved = gesture.translation(to: CGPoint(x: 101, y: 102))

        #expect(moved == nil, "inside the slop the orb does not follow the pointer")
        #expect(gesture.outcome == .click)
    }

    /// The slop is a radius, not a budget per axis. 2 px on each axis is 2.83 px
    /// of travel, and comparing the axes one at a time would have called it a
    /// drag twice over.
    @Test("the slop is measured as distance, so 2 px on each axis is still a click")
    func slopIsRadial() {
        var gesture = PointerGesture(origin: .zero)

        let moved = gesture.translation(to: CGPoint(x: 2, y: 2))

        #expect(moved == nil)
        #expect(gesture.outcome == .click)
    }

    @Test("exactly the slop already drags, and one step short of it does not")
    func theBoundaryItself() {
        var atTheSlop = PointerGesture(origin: .zero)
        var justUnder = PointerGesture(origin: .zero)

        let atTheSlopMoved = atTheSlop.translation(to: CGPoint(x: PointerGesture.defaultSlop, y: 0))
        let justUnderMoved = justUnder.translation(to: CGPoint(x: PointerGesture.defaultSlop - 0.1, y: 0))

        #expect(atTheSlopMoved?.dx == PointerGesture.defaultSlop)
        #expect(atTheSlopMoved?.dy == 0)
        #expect(atTheSlop.outcome == .drag)
        #expect(justUnderMoved == nil)
        #expect(justUnder.outcome == .click)
    }

    @Test("past the slop the orb follows the pointer, by the distance travelled")
    func pastTheSlopTheOrbFollows() {
        var gesture = PointerGesture(origin: CGPoint(x: 100, y: 100))

        let moved = gesture.translation(to: CGPoint(x: 140, y: 70))

        #expect(moved?.dx == 40, "the orb moves the whole distance, not the part past the slop")
        #expect(moved?.dy == -30)
        #expect(gesture.outcome == .drag)
    }

    /// The one that decides what happens at the end of a gesture that carried the
    /// orb around and put it back. It moved the orb: opening a menu on top of
    /// that would be a second action nobody asked for.
    @Test("a drag that comes back to where it started is still a drag")
    func aDragThatReturnsStaysADrag() {
        var gesture = PointerGesture(origin: CGPoint(x: 100, y: 100))

        _ = gesture.translation(to: CGPoint(x: 300, y: 400))
        let backAtTheStart = gesture.translation(to: CGPoint(x: 100, y: 100))

        #expect(backAtTheStart?.dx == 0, "the orb follows all the way back, it does not stop at the slop")
        #expect(backAtTheStart?.dy == 0)
        #expect(gesture.outcome == .drag)
    }

    /// A press is only over when the button comes up, and until then the orb has
    /// to answer every intermediate position.
    @Test("the answer holds across a whole sequence of positions")
    func aSequenceOfPositions() {
        var gesture = PointerGesture(origin: .zero)
        var outcomes: [PointerGesture.Outcome] = []

        for x in [0, 1, 2, 5, 6] as [CGFloat] {
            _ = gesture.translation(to: CGPoint(x: x, y: 0))
            outcomes.append(gesture.outcome)
        }

        #expect(outcomes == [.click, .click, .click, .drag, .drag],
                "the press becomes a drag at the slop and never goes back, got \(outcomes)")
    }

    @Test("a press with no movement at all is a click")
    func noMovementAtAll() {
        var gesture = PointerGesture(origin: CGPoint(x: 42, y: 42))

        let moved = gesture.translation(to: CGPoint(x: 42, y: 42))

        #expect(moved == nil)
        #expect(gesture.outcome == .click)
    }
}
