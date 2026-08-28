import AppKit

/// Indicador flutuante de gravação.
///
/// Existe porque o ícone da menu bar não basta: em tela cheia — o modo normal de
/// uso de Slack, VS Code e Chrome — a menu bar fica oculta, e com ela o único
/// sinal de que o app está ouvindo. A auditoria da Parte 2 pegou isso.
///
/// O painel não rouba foco, não aparece no Dock, ignora o mouse e acompanha
/// qualquer espaço, inclusive apps em tela cheia.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        // `orderFrontRegardless` e não `makeKeyAndOrderFront`: mostrar sem tirar
        // o foco de onde a pessoa está digitando.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 148, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Acima de apps em tela cheia. `.floating` ficaria por baixo delas.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]

        let dot = NSView(frame: NSRect(x: 22, y: 16, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4

        let label = NSTextField(labelWithString: "ouvindo…")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 40, y: 11, width: 90, height: 18)

        blur.addSubview(dot)
        blur.addSubview(label)
        panel.contentView = blur
        return panel
    }

    /// Rente à base da tela em que está o cursor, logo acima do Dock. Segue o
    /// monitor ativo em vez de assumir o principal.
    ///
    /// A primeira versão ficava 96pt acima da base e o usuário descreveu como
    /// "no meio da tela" — alto demais para um indicador que deve ser notado
    /// sem disputar atenção com o que se está escrevendo.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 28))
    }
}
