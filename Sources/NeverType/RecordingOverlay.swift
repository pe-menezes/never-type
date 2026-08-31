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
            origin: NSPoint(x: rect.midX - designSize.width * scale / 2,
                            y: rect.midY - designSize.height * scale / 2),
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

    /// Every state uses the resting logo's exact 20 × 22 drawing box. The orb
    /// never changes shape; only the contents of the mark move.
    private var markRect: NSRect {
        NSRect(x: 7, y: 6, width: 20, height: 22)
    }

    // The timer is owned for the process lifetime with this view. A deinitializer
    // cannot touch main-actor state, so state transitions stop it explicitly.
}

/// The floating body's background and drag surface.
@MainActor
final class PillView: NSView {
    var onDragEnd: (() -> Void)?
    let activity = OverlayActivityView(frame: .zero)

    var state: OverlayState = .idle {
        didSet {
            activity.state = state
            setAccessibilityValue(state.accessibilityValue)
            needsDisplay = true
        }
    }

    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?

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

    /// Every visible pixel is a drag surface, including the animated content.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: dragOrigin == nil ? .openHand : .closedHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let drawingBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = drawingBounds.height / 2
        let path = NSBezierPath(roundedRect: drawingBounds, xRadius: radius, yRadius: radius)

        let background = dragOrigin == nil
            ? NSColor(srgbRed: 0.065, green: 0.065, blue: 0.065, alpha: 0.96)
            : NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 0.98)
        background.setFill()
        path.fill()

        NSColor.white.withAlphaComponent(state == .idle ? 0.10 : 0.17).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
        NSCursor.closedHand.set()
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let windowOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + now.x - dragOrigin.x,
                                      y: windowOrigin.y + now.y - dragOrigin.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        windowOrigin = nil
        NSCursor.openHand.set()
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        onDragEnd?()
    }
}

/// Always-visible dictation status that survives full-screen applications.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var pill: PillView?

    private static let originKey = "overlayOrigin"
    private static let snapDistance: CGFloat = 48

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
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let pill = PillView(frame: NSRect(origin: .zero, size: size))
        pill.autoresizingMask = [.width, .height]
        pill.onDragEnd = { [weak self] in self?.snapAndPersist() }
        self.pill = pill

        panel.contentView = pill
        panel.setFrameOrigin(restoredOrigin(for: size))
        return panel
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
