import AppKit

/// Observa uma tecla modificadora global: pressiona começa, solta termina.
///
/// Usa um modificador puro de propósito. Segurar ⌘ direito sozinho não digita
/// caractere nem dispara ação do sistema, então não é preciso *engolir* o evento
/// — basta escutar. Isso dispensa um CGEventTap interceptador, que é mais código
/// e pode travar a entrada do sistema inteiro se algo der errado.
/// Vive na main actor. Os monitores do `NSEvent` são API do AppKit ligada ao
/// run loop principal, e o tipo passa a dizer isso em vez de deixar implícito.
@MainActor
public final class HotkeyMonitor {
    public enum Event {
        case pressed
        case released
        /// Uma tecla comum foi pressionada durante o hold. Sem isso, um ⌘V normal
        /// feito com a mão direita viraria um ditado fantasma.
        case cancelled
        /// Duplo toque: a gravação continua sem a tecla segurada.
        case latched
    }

    /// A regra do gatilho, separada do `NSEvent`.
    ///
    /// Pura de propósito: um ditado de 31 segundos apareceu no log de uso, e
    /// segurar a tecla esse tempo todo é o incômodo que o modo mãos-livres
    /// resolve. Toda a lógica de "isto foi um toque ou um hold?" mora aqui, para
    /// cada caminho ser exercitável sem teclado — inclusive os que só acontecem
    /// em milissegundos específicos.
    public struct Latch {
        /// Hold mais curto que isto é toque, não ditado.
        ///
        /// O preço: um toque curto tem a conclusão adiada em até `tapWindow`,
        /// esperando para ver se vem o segundo. Só afeta hold abaixo de 250 ms,
        /// que não tem áudio aproveitável de qualquer jeito — o ditado normal
        /// não paga nada.
        public static let tapThreshold: TimeInterval = 0.25
        /// Intervalo máximo entre os dois toques.
        public static let tapWindow: TimeInterval = 0.30

        public enum Input {
            case down(TimeInterval)
            case up(TimeInterval)
            /// Tecla comum, que durante o hold significa "isto era um atalho".
            case otherKey
            case escape
            case timeout
        }

        public enum Action: Equatable {
            case start
            case finish
            case cancel
            case latch
            case armTimeout(TimeInterval)
            case disarmTimeout
        }

        enum State: Equatable {
            case idle
            case holding(since: TimeInterval)
            /// Já soltou um toque curto; a gravação continua enquanto se espera
            /// o segundo toque.
            case awaitingSecondTap
            /// Mãos-livres: grava sem a tecla segurada.
            case latched
        }

        private(set) var state: State = .idle

        public init() {}

        public var isLatched: Bool { state == .latched }

        public mutating func handle(_ input: Input) -> [Action] {
            switch (state, input) {

            case (.idle, .down(let t)):
                state = .holding(since: t)
                return [.start]

            case (.holding(let since), .up(let t)):
                guard t - since < Self.tapThreshold else {
                    state = .idle
                    return [.finish]
                }
                state = .awaitingSecondTap
                return [.armTimeout(Self.tapWindow)]

            case (.holding, .otherKey), (.holding, .escape):
                state = .idle
                return [.cancel]

            // Segundo toque dentro da janela: trava.
            case (.awaitingSecondTap, .down):
                state = .latched
                return [.disarmTimeout, .latch]

            // A janela passou: era só um toque curto mesmo.
            case (.awaitingSecondTap, .timeout):
                state = .idle
                return [.finish]

            case (.awaitingSecondTap, .otherKey), (.awaitingSecondTap, .escape):
                state = .idle
                return [.disarmTimeout, .cancel]

            // Travado, um toque encerra. O `up` seguinte cai no `.idle` e é
            // ignorado lá.
            case (.latched, .down):
                state = .idle
                return [.finish]

            case (.latched, .escape):
                state = .idle
                return [.cancel]

            // Travado, tecla comum NÃO cancela.
            //
            // Segurando a tecla, uma tecla comum significa "isto era um atalho,
            // não um ditado". Em mãos-livres não há modificador segurado, então
            // teclar é só teclar — e cancelar um ditado longo por causa disso
            // seria perder justamente o que o modo existe para permitir.
            case (.latched, .otherKey):
                return []

            default:
                return []
            }
        }
    }

    /// ⌘ direito. O keyCode identifica a tecla; a máscara identifica o *lado*,
    /// já que `.command` fica ligada com qualquer um dos dois ⌘.
    public struct Trigger: Sendable {
        public let keyCode: UInt16
        public let deviceMask: UInt
        public let label: String

        public static let rightCommand = Trigger(keyCode: 54, deviceMask: 0x0010, label: "⌘ direito")
        public static let rightOption  = Trigger(keyCode: 61, deviceMask: 0x0040, label: "⌥ direito")
        public static let rightControl = Trigger(keyCode: 62, deviceMask: 0x2000, label: "⌃ direito")

        /// As opções oferecidas no menu.
        ///
        /// Só modificadores puros do lado direito. Um modificador sozinho não
        /// digita caractere nem dispara ação do sistema, que é o que dispensa o
        /// `CGEventTap` interceptador — e o lado direito é o que a mão que não
        /// está no mouse alcança sem sair da posição.
        public static let all: [Trigger] = [rightCommand, rightOption, rightControl]

        /// Identificador para guardar a escolha. O keyCode é estável entre
        /// versões do macOS; o rótulo não é, porque é texto de interface.
        public var id: String { String(keyCode) }

        public static func named(_ id: String?) -> Trigger? {
            guard let id else { return nil }
            return all.first { $0.id == id }
        }

        public init(keyCode: UInt16, deviceMask: UInt, label: String) {
            self.keyCode = keyCode
            self.deviceMask = deviceMask
            self.label = label
        }
    }

    /// Trocável em uso: a escolha vive no menu.
    ///
    /// Não precisa reinstalar os monitores — eles escutam `.flagsChanged` de
    /// qualquer tecla, e o filtro por keyCode acontece na leitura. O que precisa
    /// zerar é a máquina de estados: trocar a tecla no meio de um hold deixaria
    /// uma gravação órfã, sem tecla que a encerre.
    public var trigger: Trigger {
        didSet {
            guard trigger.keyCode != oldValue.keyCode else { return }
            tapTimer?.invalidate()
            tapTimer = nil
            latch = Latch()
        }
    }
    public var onEvent: (@MainActor (Event) -> Void)?

    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var latch = Latch()
    private var tapTimer: Timer?

    /// Verdadeiro enquanto a gravação segue sem a tecla segurada.
    public var isLatched: Bool { latch.isLatched }

    public init(trigger: Trigger = .rightCommand) {
        self.trigger = trigger
    }

    /// A concessão de Acessibilidade. Sem ela os monitores globais simplesmente
    /// não recebem eventos — e não avisam. O app pareceria quebrado em silêncio.
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        // A constante kAXTrustedCheckOptionPrompt é uma `var` global do
        // ApplicationServices, o que o Swift 6 rejeita por concorrência. O valor
        // é estável e documentado, então usamos a string diretamente.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        // `assumeIsolated`, e não `Task { @MainActor in }`, de propósito.
        //
        // O AppKit entrega estes eventos na main thread — os monitores são
        // instalados no run loop principal. E aqui a ordem importa mais que a
        // pureza: um salto assíncrono poderia processar o `keyDown` depois do
        // release, transformando um ditado válido em cancelamento. A chamada
        // síncrona preserva a ordem de chegada.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            globalMonitors.append(m)
        }

        // O monitor global não dispara quando o próprio app está em foco. Como
        // FalaFlow é acessório e quase nunca fica, isto é cinto de segurança —
        // mas sem ele o trigger morreria com o menu da bandeja aberto.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    public func stop() {
        for m in globalMonitors { NSEvent.removeMonitor(m) }
        globalMonitors.removeAll()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        tapTimer?.invalidate()
        tapTimer = nil
        latch = Latch()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard event.keyCode == trigger.keyCode else { return }
            let down = (event.modifierFlags.rawValue & trigger.deviceMask) != 0
            apply(latch.handle(down ? .down(event.timestamp) : .up(event.timestamp)))
        case .keyDown:
            // 53 é Escape. Em mãos-livres ele é a única saída sem transcrever.
            apply(latch.handle(event.keyCode == 53 ? .escape : .otherKey))
        default:
            break
        }
    }

    private func apply(_ actions: [Latch.Action]) {
        for action in actions {
            switch action {
            case .start:  onEvent?(.pressed)
            case .finish: onEvent?(.released)
            case .cancel: onEvent?(.cancelled)
            case .latch:  onEvent?(.latched)
            case .armTimeout(let after):
                tapTimer?.invalidate()
                // `assumeIsolated` é o caso legítimo: o Timer é agendado no run
                // loop principal por este método, que já é `@MainActor`.
                tapTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.apply(self.latch.handle(.timeout))
                    }
                }
            case .disarmTimeout:
                tapTimer?.invalidate()
                tapTimer = nil
            }
        }
    }

    // Sem `deinit { stop() }`: `deinit` é nonisolated e não pode tocar estado da
    // main actor. Quem cria o monitor chama `stop()`.
}
