import AppKit
import NeverTypeCore

/// The moments the overlay must distinguish through shape and motion.
enum OverlayState: Equatable {
    case idle
    case recording
    case latched
    case transcribing

    var size: NSSize {
        NSSize(width: 34, height: 34)
    }

    var accessibilityValue: String {
        switch self {
        case .idle:          "Ready"
        case .recording:     "Listening"
        case .latched:       "Hands-free recording"
        case .transcribing:  "Writing"
        }
    }
}

/// The NeverType mark and its compact menu bar states.
///
/// Rounded voice bars resolve into a text cursor. The same geometry is used by
/// the app icon, menu bar and resting overlay so the product has one mark at
/// every scale.
@MainActor
enum BrandMark {
    private static let designSize = NSSize(width: 53, height: 49)
    private static let stroke: CGFloat = 6
    // Every shape is vertically centered at 27. The I-beam carries more area
    // than the bars, moving the filled-area centroid to 30.69 on the x axis.
    private static let opticalCenter = NSPoint(x: 30.69, y: 27)

    private struct Geometry {
        let origin: NSPoint
        let scale: CGFloat

        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: origin.x + x * scale,
                   y: origin.y + y * scale,
                   width: width * scale,
                   height: height * scale)
        }
    }

    enum StatusStyle {
        case idle
        case recording
        case blocked

        var logName: String {
            switch self {
            case .idle:      "brand"
            case .recording: "waveform"
            case .blocked:   "brand.slash"
            }
        }
    }

    static func draw(in rect: NSRect, color: NSColor) {
        drawWaveform(in: rect, heights: [12, 27, 44], levels: nil, color: color)
        drawCursor(in: rect, color: color)
    }

    /// The live waveform uses the logo's three bar positions and exact stroke
    /// width. A transition changes only their height and opacity.
    static func drawWaveform(in rect: NSRect, levels: [CGFloat], color: NSColor) {
        let heights = levels.map { 12 + max(0, min(1, $0)) * 32 }
        drawWaveform(in: rect, heights: heights, levels: levels, color: color)
    }

    /// Draws the same cursor as the resting mark, including its cap proportions.
    static func drawCursor(in rect: NSRect, color: NSColor) {
        let geometry = geometry(in: rect)
        color.setFill()
        let cursor = [
            geometry.rect(42.5, 5, stroke, 44),
            geometry.rect(38, 5, 15, stroke),
            geometry.rect(38, 43, 15, stroke),
        ]
        for shape in cursor {
            let radius = min(shape.width, shape.height) / 2
            NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius).fill()
        }
    }

    /// The processing dots occupy the former bar centers. The bars collapse in
    /// place while the cursor remains unchanged.
    static func drawWriting(in rect: NSRect, phase: CGFloat, color: NSColor) {
        let geometry = geometry(in: rect)
        let progress = phase * 4
        for index in 0..<3 {
            let distance = CGFloat(index + 1) - progress
            let emphasis = exp(-(distance * distance) / 0.48)
            color.withAlphaComponent(0.28 + 0.72 * emphasis).setFill()
            let dot = geometry.rect(CGFloat(index) * 12, 24, stroke, stroke)
            NSBezierPath(ovalIn: dot).fill()
        }
        drawCursor(in: rect, color: color)
    }

    private static func geometry(in rect: NSRect) -> Geometry {
        let scale = min(rect.width / designSize.width, rect.height / designSize.height)
        return Geometry(
            origin: NSPoint(x: rect.midX - opticalCenter.x * scale,
                            y: rect.midY - opticalCenter.y * scale),
            scale: scale)
    }

    private static func drawWaveform(in rect: NSRect,
                                     heights: [CGFloat],
                                     levels: [CGFloat]?,
                                     color: NSColor) {
        let geometry = geometry(in: rect)
        let centerY: CGFloat = 27
        for (index, height) in heights.prefix(3).enumerated() {
            let alpha: CGFloat
            if let levels, index < levels.count {
                let level = max(0, min(1, levels[index]))
                alpha = level > 0 ? 0.72 + 0.28 * level : 0.42
            } else {
                alpha = 1
            }
            color.withAlphaComponent(alpha).setFill()
            let shape = geometry.rect(CGFloat(index) * 12,
                                      centerY - height / 2,
                                      stroke,
                                      height)
            NSBezierPath(roundedRect: shape,
                         xRadius: stroke * geometry.scale / 2,
                         yRadius: stroke * geometry.scale / 2).fill()
        }
    }

    static func statusImage(_ style: StatusStyle) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            switch style {
            case .idle:
                draw(in: rect.insetBy(dx: 1.5, dy: 1.5), color: .black)

            case .recording:
                NSBezierPath(ovalIn: NSRect(x: 0.5, y: 7.5, width: 3, height: 3)).fill()
                let heights: [CGFloat] = [5, 11, 16, 10, 6]
                for (index, height) in heights.enumerated() {
                    let bar = NSRect(x: 5 + CGFloat(index) * 2.7,
                                     y: (rect.height - height) / 2,
                                     width: 1.8,
                                     height: height)
                    NSBezierPath(roundedRect: bar, xRadius: 0.9, yRadius: 0.9).fill()
                }

            case .blocked:
                draw(in: rect.insetBy(dx: 2.5, dy: 2.5), color: .black)
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2, y: 2))
                slash.line(to: NSPoint(x: 16, y: 16))
                slash.lineWidth = 2.4
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Draws the content that changes inside the orb.
///
/// Audio levels are historical, not one flickering instant. Writing has its
/// own synthetic motion because no microphone samples arrive in that state.
@MainActor
final class OverlayActivityView: NSView {
    private static let levelCount = 3
    private static let restingLevels: [CGFloat] = [0, 15.0 / 32.0, 1]
    private var levels = restingLevels
    private var phase: CGFloat = 0
    private var pulse: Timer?

    var state: OverlayState = .idle {
        didSet {
            guard state != oldValue else { return }
            state == .transcribing ? startPulse() : stopPulse()
            needsDisplay = true
        }
    }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        needsDisplay = true
    }

    func reset() {
        levels = Self.restingLevels
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func startPulse() {
        stopPulse()
        phase = 0
        // The panel runs at 30 fps. This is enough for a small status motion and
        // keeps the animation smooth during the roughly 600 ms transcription.
        pulse = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += 0.045
                if self.phase > 1 { self.phase -= 1 }
                self.needsDisplay = true
            }
        }
    }

    private func stopPulse() {
        pulse?.invalidate()
        pulse = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        ink.setFill()
        ink.setStroke()

        switch state {
        case .idle:
            BrandMark.draw(in: markRect, color: ink)

        case .recording, .latched:
            BrandMark.drawWaveform(in: markRect, levels: levels, color: ink)
            BrandMark.drawCursor(in: markRect, color: ink)

        case .transcribing:
            BrandMark.drawWriting(in: markRect, phase: phase, color: ink)
        }
    }

    /// Every state uses the same 20 × 22 scaling box and optical center. The
    /// orb never changes shape; only the contents of the mark move.
    private var markRect: NSRect {
        NSRect(x: 7, y: 6, width: 20, height: 22)
    }

    // The timer is owned for the process lifetime with this view. A deinitializer
    // cannot touch main-actor state, so state transitions stop it explicitly.
}

/// The floating body's background, drag surface and menu button.
@MainActor
final class PillView: NSView {
    var onDragEnd: (() -> Void)?
    var onClick: (() -> Void)?
    let activity = OverlayActivityView(frame: .zero)

    var state: OverlayState = .idle {
        didSet {
            activity.state = state
            setAccessibilityValue(state.accessibilityValue)
            needsDisplay = true
        }
    }

    /// Reborn on every press. Outside a press its answer is not read.
    private var gesture = PointerGesture(origin: .zero)
    private var windowOrigin: NSPoint?
    private var isPressed = false
    private var isDragging: Bool { isPressed && gesture.outcome == .drag }
    private var hover: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        activity.frame = bounds
        activity.autoresizingMask = [.width, .height]
        addSubview(activity)
        setAccessibilityElement(true)
        setAccessibilityLabel("NeverType")
        setAccessibilityValue(state.accessibilityValue)
    }

    /// Every visible pixel answers the mouse, including the animated content.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    /// Tracking of its own, so the tooltip has a chance in this window.
    ///
    /// `NSView.toolTip` installs tracking by itself, and AppKit's default
    /// follows the mouse while the application is the active one. NeverType is
    /// accessory and is almost never active, which is exactly the moment
    /// somebody rests the pointer on the orb wondering what it is. `.activeAlways`
    /// is the option that keeps the hover arriving in that state, and
    /// `.inVisibleRect` keeps the area on the bounds as the panel is dragged
    /// around the screen.
    ///
    /// Not watched happening: the app was not run for this change. The hint on
    /// the menu bar button is the trodden path. This one puts the same string
    /// in a borderless non-activating panel, and that is where the doubt is.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hover = area
    }

    /// The plain arrow at rest, and the closed hand only while the orb is really
    /// being moved.
    ///
    /// It was the open hand until a click started opening the menu. A hand over
    /// something clickable promises one thing, dragging, and the orb now does
    /// two. The closed hand still marks the drag, and it appears when the press
    /// passes the slop instead of when the button goes down.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        let drawingBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = drawingBounds.height / 2
        let path = NSBezierPath(roundedRect: drawingBounds, xRadius: radius, yRadius: radius)

        let background = isPressed
            ? NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 0.98)
            : NSColor(srgbRed: 0.065, green: 0.065, blue: 0.065, alpha: 0.96)
        background.setFill()
        path.fill()

        NSColor.white.withAlphaComponent(state == .idle ? 0.10 : 0.17).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        gesture = PointerGesture(origin: NSEvent.mouseLocation)
        windowOrigin = window?.frame.origin
        isPressed = true
        needsDisplay = true
    }

    /// The orb does not follow the pointer inside the slop.
    ///
    /// Moving it there and calling the press a click afterwards would leave the
    /// orb a couple of pixels from where the saved origin says it is, and the
    /// next launch would put it back in the other place.
    override func mouseDragged(with event: NSEvent) {
        let wasDragging = isDragging
        guard let moved = gesture.translation(to: NSEvent.mouseLocation),
              let windowOrigin, let window else { return }
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + moved.dx,
                                      y: windowOrigin.y + moved.dy))
        if !wasDragging { refreshCursor() }
    }

    override func mouseUp(with event: NSEvent) {
        let outcome = gesture.outcome
        isPressed = false
        windowOrigin = nil
        refreshCursor()
        needsDisplay = true
        switch outcome {
        // A click never moved the orb, so there is no position to snap or to
        // save: the two gestures end in different places on purpose.
        case .click: onClick?()
        case .drag:  onDragEnd?()
        }
    }

    private func refreshCursor() {
        (isDragging ? NSCursor.closedHand : NSCursor.arrow).set()
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
    }
}

/// Always-visible dictation status that survives full-screen applications.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var pill: PillView?

    /// The status item's menu, which a click on the orb opens as well.
    ///
    /// The same object, never a copy. The menu rebuilds itself from the state of
    /// the moment in `menuNeedsUpdate` (`main.swift`), so whatever opens it gets
    /// the same rebuilt menu. A second menu would be a second path to keep in
    /// step, and it would be the one used in full screen, where the menu bar is
    /// hidden and nobody would see it drifting from the other.
    var menu: NSMenu?

    /// What the pointer gets for standing still on the orb, the same line the
    /// menu bar icon carries. Kept here as well as on the view, because the
    /// panel is built on the first state change and the hint may be set before
    /// or after that.
    var hint: String? {
        didSet { pill?.toolTip = hint }
    }

    private static let originKey = "overlayOrigin"
    private static let snapDistance: CGFloat = 48

    /// Above every window, including a full-screen application's own.
    private static let restingLevel: NSWindow.Level = .screenSaver

    /// Where the panel waits while a menu is on screen.
    ///
    /// AppKit draws menus in a window at `.popUpMenu`, which is level 101, and
    /// this panel rests at `.screenSaver`, which is 1000: a menu opened over the
    /// orb comes out underneath it. `.statusBar` is 25, still above the windows
    /// of the application in front and above a full-screen one, so the orb stays
    /// visible while the menu covers it. This follows from the three constants
    /// and was not watched happening: the app was not run for this change.
    private static let menuOpenLevel: NSWindow.Level = .statusBar

    /// Called from the menu's delegate, for the menu opened from either place.
    func menuOpened() { panel?.level = Self.menuOpenLevel }
    func menuClosed() { panel?.level = Self.restingLevel }

    func showIdle() {
        apply(.idle)
        panel?.orderFrontRegardless()
    }

    func show() {
        pill?.activity.reset()
        apply(.recording)
        panel?.orderFrontRegardless()
    }

    func latch() {
        apply(.latched)
    }

    func transcribing() {
        apply(.transcribing)
    }

    func hide() {
        pill?.activity.reset()
        apply(.idle)
    }

    func push(level: Float) {
        pill?.activity.push(level)
    }

    private func apply(_ state: OverlayState) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        pill?.state = state
    }

    private func makePanel() -> NSPanel {
        let size = OverlayState.idle.size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = Self.restingLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The tooltip timer is fed by mouse-moved events, and a borderless
        // panel does not receive them unless it is asked to. Nothing else in
        // the orb reads them: the drag runs on mouse-dragged, which arrives
        // either way.
        panel.acceptsMouseMovedEvents = true

        let pill = PillView(frame: NSRect(origin: .zero, size: size))
        pill.autoresizingMask = [.width, .height]
        pill.toolTip = hint
        pill.onDragEnd = { [weak self] in self?.snapAndPersist() }
        pill.onClick = { [weak self] in self?.presentMenu() }
        self.pill = pill

        panel.contentView = pill
        panel.setFrameOrigin(restoredOrigin(for: size))
        return panel
    }

    /// Opens the menu against the orb itself.
    ///
    /// `popUp(positioning:at:in:)` and not `statusItem.button?.performClick(nil)`
    /// because in full screen macOS hides the menu bar, and the orb exists for
    /// that case (`docs/pitfalls.md`, "In full screen there is no menu bar"). A
    /// menu anchored to an icon that is not on screen would fail in the one
    /// scenario where the orb is the whole interface.
    ///
    /// The anchor is the orb's bottom left corner, so the menu hangs under it.
    /// The orb is born in the bottom right corner of the screen, where the menu
    /// does not fit downwards, and there AppKit flips it upwards on its own and
    /// it covers the orb. Nothing was done about that: it is what any context
    /// menu near an edge does, and the level above keeps the orb from being
    /// drawn on top of the menu when they overlap.
    private func presentMenu() {
        guard let menu, let pill else { return }
        // Out of the mouse handler before the menu's own tracking loop starts.
        // Entering a nested AppKit loop from inside an event handler is what the
        // Accessibility alert had to stop doing (`main.swift`), and the click is
        // finished by then anyway.
        Task { @MainActor in
            // The answer says whether an item was chosen. Every item carries its
            // own target and acts on its own, so nothing here reads it.
            _ = menu.popUp(positioning: nil,
                           at: NSPoint(x: pill.bounds.minX, y: pill.bounds.minY - 4),
                           in: pill)
        }
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let physical = NSScreen.main?.frame ?? visible
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let candidate = saved ?? NSPoint(x: physical.maxX - size.width - 12, y: physical.minY + 12)
        let onScreen = NSScreen.screens.contains {
            $0.visibleFrame.intersects(NSRect(origin: candidate, size: size))
        }
        guard onScreen else {
            return NSPoint(x: physical.maxX - size.width - 12, y: physical.minY + 12)
        }
        return candidate
    }

    private func snapAndPersist() {
        guard let panel else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // The pill can cover the Dock, so the floor and sides use the physical
        // display. The ceiling uses visibleFrame to keep it below the menu bar.
        let physical = screen?.frame ?? visible
        var origin = frame.origin
        let margin: CGFloat = 12
        if origin.x - physical.minX < Self.snapDistance { origin.x = physical.minX + margin }
        if physical.maxX - frame.maxX < Self.snapDistance { origin.x = physical.maxX - frame.width - margin }
        if origin.y - physical.minY < Self.snapDistance { origin.y = physical.minY + margin }
        if visible.maxY - frame.maxY < Self.snapDistance { origin.y = visible.maxY - frame.height - margin }

        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }
}
