import AppKit
import NeverTypeCore

/// The three states the pill needs to tell apart.
///
/// There used to be two — idle and recording — and transcription happened inside
/// "idle": you released the key, everything went back to rest, and ~600 ms went
/// by with the app working and nothing on screen saying so.
enum OverlayState {
    case idle
    case recording
    case transcribing
}

/// Bars that rise with what the microphone is hearing.
///
/// The static red dot that used to be here proved the app was recording, not
/// that sound was coming in. With the microphone muted or on the wrong input the
/// drawing was identical to everything working, and the only sign of trouble
/// came later, as an empty transcription.
@MainActor
final class LevelMeter: NSView {
    private static let barCount = 18
    private var levels = [CGFloat](repeating: 0, count: barCount)

    /// Phase of the wave that runs during transcription. Only exists in that state.
    private var phase: CGFloat = 0
    private var pulse: Timer?

    var state: OverlayState = .idle {
        didSet {
            guard state != oldValue else { return }
            state == .transcribing ? startPulse() : stopPulse()
            needsDisplay = true
        }
    }

    /// Pushes the new level and scrolls the previous ones to the left, so the
    /// drawing becomes the shape of the speech instead of a flickering instant value.
    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        needsDisplay = true
    }

    func reset() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
        needsDisplay = true
    }

    /// Transparent to the mouse: the meter covers almost the whole pill, and if
    /// it swallowed the click only the border would be draggable.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Dark, saturated green, not `systemGreen`.
    ///
    /// On the dark pill the previous light green glowed too much and pulled
    /// attention from whoever was writing — the indicator needs to be noticed
    /// without competing for focus.
    static let live = NSColor(srgbRed: 0.13, green: 0.68, blue: 0.40, alpha: 1)

    /// Blue for transcribing: a different color, not a weaker green.
    ///
    /// "Recording in silence" and "transcribing" need to be distinguishable at a
    /// glance — if transcription were a dimmed green, it would look the same as
    /// silence during recording, which is precisely the pair the level meter
    /// exists to separate.
    static let working = NSColor(srgbRed: 0.36, green: 0.60, blue: 0.92, alpha: 1)

    private func startPulse() {
        stopPulse()
        phase = 0
        // 30 fps. The wave exists to say "I am working", and a stuttering
        // animation would say the opposite of what it exists to say.
        //
        // `assumeIsolated` here is the legitimate case: the Timer was scheduled
        // on the main run loop by this method, which is already `@MainActor`.
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
        let barWidth: CGFloat = 2.5
        let gap: CGFloat = 1.9
        let maxHeight = bounds.height
        // Floor: a zero-height bar would disappear, and a meter that vanishes in
        // silence does not distinguish "no sound" from "no meter".
        let minHeight: CGFloat = 2.5

        for i in 0..<Self.barCount {
            let height: CGFloat
            let color: NSColor

            switch state {
            case .transcribing:
                // Wave running left to right, unrelated to the audio: no more
                // sound comes in here, and showing frozen levels would suggest
                // it still does.
                let position = phase * CGFloat(Self.barCount + 6) - 3
                let distance = CGFloat(i) - position
                let bump = exp(-(distance * distance) / 6)
                height = max(minHeight, bump * maxHeight * 0.85)
                color = Self.working.withAlphaComponent(0.35 + 0.55 * bump)

            case .recording:
                let level = levels[i]
                height = max(minHeight, level * maxHeight)
                // Intensity follows volume along with height: quiet speech gets
                // visibly dimmer, not just shorter. In silence, dimmed green —
                // this used to be gray, same as idle, and holding the key without
                // speaking was identical to not having pressed anything.
                color = Self.live.withAlphaComponent(level > 0 ? 0.6 + 0.4 * level : 0.35)

            case .idle:
                height = minHeight
                color = NSColor.white.withAlphaComponent(0.16)
            }

            let rect = NSRect(x: CGFloat(i) * (barWidth + gap),
                              y: (maxHeight - height) / 2,
                              width: barWidth,
                              height: height)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    // No `deinit { stopPulse() }`: `deinit` is nonisolated and cannot touch
    // main-actor state. The meter lives as long as the app does.
}

/// The pill's body: draws the background and carries the drag.
///
/// The panel does not use `isMovableByWindowBackground` because with it there is
/// no way to know when the drag ended — and the end is when the pill snaps to the
/// edge and the position is saved.
@MainActor
final class PillView: NSView {
    var onDragEnd: (() -> Void)?

    /// Second cue of the state, along with the bars: in absolute silence the bars
    /// barely show, and the border keeps saying what is happening.
    var state: OverlayState = .idle { didSet { needsDisplay = true } }

    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // Dark in both themes, on purpose.
        //
        // The `.hudWindow` material drew almost white in light mode, and the
        // panel looked like an old dialog box. A dark pill is legible over any
        // content and does not change personality with the background.
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 0.92).setFill()
        path.fill()

        switch state {
        case .recording:
            LevelMeter.live.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1.5
        case .transcribing:
            LevelMeter.working.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1.5
        case .idle:
            NSColor.white.withAlphaComponent(0.09).setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let windowOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + (now.x - dragOrigin.x),
                                      y: windowOrigin.y + (now.y - dragOrigin.y)))
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        windowOrigin = nil
        onDragEnd?()
    }
}

/// Floating indicator, always visible.
///
/// Exists because the menu bar icon is not enough: in full screen — the normal
/// mode for Slack, VS Code and Chrome — the menu bar is hidden, and with it the
/// only sign that the app is listening.
///
/// Stays on screen the whole time, not just during dictation: an accessory app
/// with no window leaves no trace of absence, so when it dies nothing on screen
/// changes. The idle pill is the proof that it is alive.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var meter: LevelMeter?
    private var pill: PillView?

    private static let originKey = "overlayOrigin"
    /// Distance at which the pill snaps to the edge on release.
    private static let snapDistance: CGFloat = 48

    func showIdle() {
        apply(.idle)
        panel?.orderFrontRegardless()
    }

    /// Recording: the key was pressed.
    func show() {
        meter?.reset()
        apply(.recording)
        panel?.orderFrontRegardless()
    }

    /// Transcribing: the key was released and the model is working.
    ///
    /// Without this state, releasing the key returned everything to rest and the
    /// app spent ~600 ms working with nothing on screen saying so — and on a
    /// long dictation the dead zone is bigger.
    func transcribing() {
        apply(.transcribing)
    }

    /// Back to rest. Does not leave the screen: leaving was what made "dead app"
    /// and "idle app" look the same — like nothing.
    func hide() {
        meter?.reset()
        apply(.idle)
    }

    private func apply(_ state: OverlayState) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        meter?.state = state
        pill?.state = state
    }

    /// Called for every slice of the microphone buffer.
    func push(level: Float) {
        meter?.push(level)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 108, height: 32)
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
        // Above full-screen apps. `.floating` would sit below them.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let pill = PillView(frame: NSRect(origin: .zero, size: size))
        pill.autoresizingMask = [.width, .height]
        pill.onDragEnd = { [weak self] in self?.snapAndPersist() }
        self.pill = pill

        let meter = LevelMeter(frame: NSRect(x: 16, y: 7, width: 76, height: 18))
        meter.autoresizingMask = [.minXMargin, .maxXMargin]
        self.meter = meter

        pill.addSubview(meter)
        panel.contentView = pill
        panel.setFrameOrigin(restoredOrigin(for: size))
        return panel
    }

    // MARK: - Position

    /// Where the pill was, or the bottom-right corner the first time.
    ///
    /// Always validated against the current screens: saving the position and
    /// restoring it blindly leaves the pill off screen when someone unplugs the
    /// monitor it was on — and an invisible pill proves nothing.
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

    /// On release, snaps to the nearest edge and saves where it ended up.
    private func snapAndPersist() {
        guard let panel else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // Floor, sides and ceiling come from different sources on purpose.
        //
        // `visibleFrame` excludes the Dock, so using it at the bottom made "as low
        // as possible" mean the top edge of the Dock — and since at the top the
        // limit is just below the menu bar, going up seemed to work and going
        // down did not. The pill floats above everything, so the floor and the
        // sides are the physical screen. Only the ceiling respects
        // `visibleFrame`, so as not to cover the menu bar or vanish behind it.
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
