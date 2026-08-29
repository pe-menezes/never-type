import AppKit
import FalaFlowCore

/// Barras que sobem com o que o microfone está ouvindo.
///
/// O ponto vermelho parado que existia aqui antes provava que o app estava
/// gravando, e não que havia som entrando. Com o microfone mudo ou na entrada
/// errada o desenho era idêntico ao de tudo funcionando, e o único sinal de
/// problema chegava depois, como transcrição vazia.
@MainActor
final class LevelMeter: NSView {
    private static let barCount = 18
    private var levels = [CGFloat](repeating: 0, count: barCount)

    /// Enquanto está parado o medidor não mede nada, e barras achatadas
    /// pareceriam microfone mudo. Em repouso ele mostra um traço neutro.
    var isLive = false { didSet { needsDisplay = true } }

    /// Empurra o nível novo e rola os anteriores para a esquerda, para o
    /// desenho virar a forma da fala em vez de um valor instantâneo piscando.
    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        needsDisplay = true
    }

    func reset() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
        needsDisplay = true
    }

    /// Transparente ao mouse: o medidor ocupa quase toda a pílula, e se ele
    /// engolisse o clique só a borda seria arrastável.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Verde escuro e saturado, não o `systemGreen`.
    ///
    /// Sobre a pílula escura o verde claro anterior brilhava demais e puxava
    /// atenção de quem estava escrevendo — o indicador precisa ser notado sem
    /// disputar o foco.
    private static let live = NSColor(srgbRed: 0.13, green: 0.68, blue: 0.40, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 2.5
        let gap: CGFloat = 1.9
        let maxHeight = bounds.height
        // Piso: barra de altura zero desapareceria, e um medidor que some no
        // silêncio não distingue "sem som" de "sem medidor".
        let minHeight: CGFloat = 2.5

        for (i, level) in levels.enumerated() {
            let height = max(minHeight, level * maxHeight)
            let rect = NSRect(x: CGFloat(i) * (barWidth + gap),
                              y: (maxHeight - height) / 2,
                              width: barWidth,
                              height: height)
            if isLive && level > 0 {
                // A intensidade acompanha o volume junto com a altura: fala
                // baixa fica visivelmente mais apagada, não só mais curta.
                Self.live.withAlphaComponent(0.6 + 0.4 * level).setFill()
            } else if isLive {
                // Gravando e em silêncio: verde apagado.
                //
                // Antes isto era cinza igual ao repouso, e segurar a tecla sem
                // falar era visualmente idêntico a não ter apertado nada — não
                // dava para saber se a gravação tinha começado.
                Self.live.withAlphaComponent(0.35).setFill()
            } else {
                // Em repouso, neutro. Silêncio durante a gravação e app parado
                // são estados diferentes e não podem ter o mesmo desenho.
                NSColor.white.withAlphaComponent(0.16).setFill()
            }
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}

/// O corpo da pílula: desenha o fundo e carrega o arrasto.
///
/// O painel não usa `isMovableByWindowBackground` porque com ele não há como
/// saber quando o arrasto terminou — e é no fim que a pílula gruda na borda e
/// a posição é guardada.
@MainActor
final class PillView: NSView {
    var onDragEnd: (() -> Void)?
    /// Segunda pista do estado de gravação, junto com a cor das barras: em
    /// silêncio absoluto as barras quase não aparecem, e a borda continua
    /// dizendo que a tecla está sendo segurada.
    var isLive = false { didSet { needsDisplay = true } }
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // Escura nos dois temas, de propósito.
        //
        // O material `.hudWindow` desenhava quase branco no modo claro, e o
        // painel ficava com cara de caixa de diálogo antiga. Uma pílula escura é
        // legível sobre qualquer conteúdo e não muda de personalidade conforme o
        // fundo.
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 0.92).setFill()
        path.fill()
        if isLive {
            NSColor(srgbRed: 0.13, green: 0.68, blue: 0.40, alpha: 0.85).setStroke()
            path.lineWidth = 1.5
        } else {
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

/// Indicador flutuante de gravação, sempre visível.
///
/// Existe porque o ícone da menu bar não basta: em tela cheia — o modo normal de
/// uso de Slack, VS Code e Chrome — a menu bar fica oculta, e com ela o único
/// sinal de que o app está ouvindo.
///
/// Fica na tela o tempo todo, e não só durante o ditado: um app acessório sem
/// janela não deixa rastro de ausência, então quando ele morre não há nada na
/// tela que mude. A pílula parada é a prova de que ele está vivo.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var meter: LevelMeter?
    private var pill: PillView?

    private static let originKey = "overlayOrigin"
    /// Distância em que a pílula gruda na borda ao soltar.
    private static let snapDistance: CGFloat = 48

    func showIdle() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        meter?.isLive = false
        pill?.isLive = false
        meter?.reset()
        panel.orderFrontRegardless()
    }

    func show() {
        showIdle()
        meter?.reset()
        meter?.isLive = true
        pill?.isLive = true
    }

    func hide() {
        // Não some da tela: volta ao repouso. Sumir era o que fazia "app morto"
        // e "app parado" terem a mesma aparência — nenhuma.
        meter?.isLive = false
        pill?.isLive = false
        meter?.reset()
    }

    /// Chamado a cada buffer do microfone, ~12 vezes por segundo.
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
        // Acima de apps em tela cheia. `.floating` ficaria por baixo delas.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let pill = PillView(frame: NSRect(origin: .zero, size: size))
        pill.autoresizingMask = [.width, .height]
        pill.onDragEnd = { [weak self] in self?.snapAndPersist() }
        self.pill = pill

        let meter = LevelMeter(frame: NSRect(x: 16, y: 7, width: 76, height: 18))
        // O medidor não intercepta o clique: quem arrasta é a pílula inteira.
        meter.autoresizingMask = [.minXMargin, .maxXMargin]
        self.meter = meter

        pill.addSubview(meter)
        panel.contentView = pill
        panel.setFrameOrigin(restoredOrigin(for: size))
        return panel
    }

    // MARK: - Posição

    /// Onde a pílula estava, ou o canto inferior direito na primeira vez.
    ///
    /// Sempre validada contra as telas atuais: guardar a posição e restaurá-la
    /// cegamente deixa a pílula fora da tela quando alguém desconecta o monitor
    /// em que ela estava — e uma pílula invisível não prova nada.
    private func restoredOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let physical = NSScreen.main?.frame ?? visible
        let candidate = saved ?? NSPoint(x: physical.maxX - size.width - 12, y: physical.minY + 12)
        let onScreen = NSScreen.screens.contains {
            $0.visibleFrame.intersects(NSRect(origin: candidate, size: size))
        }
        guard onScreen else {
            return NSPoint(x: physical.maxX - size.width - 12, y: physical.minY + 12)
        }
        return candidate
    }

    /// Ao soltar, gruda na borda mais próxima e guarda onde ficou.
    private func snapAndPersist() {
        guard let panel else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // Chão, laterais e teto vêm de fontes diferentes de propósito.
        //
        // `visibleFrame` exclui o Dock, então usá-lo embaixo fazia "o mais baixo
        // possível" ser a borda superior do Dock — e como em cima o limite é
        // logo abaixo da barra de menu, subir parecia funcionar e descer não.
        // A pílula flutua acima de tudo, então o chão e as laterais são a tela
        // física. Só o teto respeita `visibleFrame`, para não cobrir a barra de
        // menu nem sumir atrás dela.
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
