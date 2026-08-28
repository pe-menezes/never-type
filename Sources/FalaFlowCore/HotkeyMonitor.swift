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

        public init(keyCode: UInt16, deviceMask: UInt, label: String) {
            self.keyCode = keyCode
            self.deviceMask = deviceMask
            self.label = label
        }
    }

    public let trigger: Trigger
    public var onEvent: (@MainActor (Event) -> Void)?

    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var isHolding = false

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
        isHolding = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard event.keyCode == trigger.keyCode else { return }
            let down = (event.modifierFlags.rawValue & trigger.deviceMask) != 0
            if down, !isHolding {
                isHolding = true
                onEvent?(.pressed)
            } else if !down, isHolding {
                isHolding = false
                onEvent?(.released)
            }
        case .keyDown:
            guard isHolding else { return }
            isHolding = false
            onEvent?(.cancelled)
        default:
            break
        }
    }

    // Sem `deinit { stop() }`: `deinit` é nonisolated e não pode tocar estado da
    // main actor. Quem cria o monitor chama `stop()`.
}
