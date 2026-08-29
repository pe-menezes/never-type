import Foundation
import ServiceManagement

/// Liga e desliga o NeverType como login item do macOS.
///
/// O `SMAppService` registra **o bundle que está rodando**, e o BTM indexa esse
/// registro por bundle ID, não por caminho. Medido em 2026-08-28 (macOS 26.2)
/// com um app-proxy assinado com a mesma identidade e o mesmo hardened runtime:
/// registrado a partir de `/private/tmp/...`, a cópia em `/Applications` — outro
/// caminho, mesmo bundle ID — respondeu `status == .enabled`. E o `register()`
/// do bundle temporário não lançou erro nenhum.
///
/// Ou seja: os dois únicos sinais que a API oferece dizem "tudo certo" sobre um
/// bundle numa pasta temporária. É por isso que a guarda de caminho roda
/// **antes** de registrar — depois não existe pergunta que devolva a resposta.
public enum LoginItem {

    /// O que o sistema responde sobre abrir o app na inicialização.
    public enum State: Equatable, CustomStringConvertible {
        /// Abre com o sistema.
        case on
        /// Não abre. Colapsa `notRegistered` (nunca registrado) e `notFound`
        /// (registrado e depois some do BTM): são casos distintos do
        /// `SMAppService`, mas a interface não tem o que fazer de diferente com
        /// eles — os dois significam "não abre".
        case off
        /// Registrado, e desligado pela pessoa nos Ajustes do Sistema. Não
        /// colapsa em `off` porque a saída é diferente: nenhum clique aqui
        /// resolve, a ação está fora do app.
        case needsApproval

        public var description: String {
            switch self {
            case .on:            return "ligado"
            case .off:           return "desligado"
            case .needsApproval: return "desativado nos Ajustes do Sistema"
            }
        }
    }

    /// O resultado de tentar mudar o estado.
    ///
    /// `refused` carrega o motivo já redigido para o usuário, com a ação de
    /// saída dentro — o app é acessório e não tem janela onde explicar depois.
    public enum Outcome: Equatable {
        case changed(State)
        case refused(String)
    }

    /// Os dois lugares de onde vale registrar.
    ///
    /// `~/Applications` não é capricho: o `install.sh` documenta esse fallback
    /// para máquina gerida ou usuário sem direitos de administrador, onde
    /// `/Applications` não é gravável. Uma guarda que só aceitasse
    /// `/Applications` deixaria essa pessoa sem como ligar a opção.
    private static let bundleName = "NeverType.app"

    /// A regra em si, separada de qualquer consulta ao sistema.
    ///
    /// Pura de propósito, como `ModelStore.isValid(magic:size:)`: dá para
    /// exercitar todos os ramos sem montar bundle nenhum em disco.
    public static func isInstalledLocation(bundlePath: String, home: String) -> Bool {
        let path = withoutTrailingSlash(bundlePath)
        let home = withoutTrailingSlash(home)
        return path == "/Applications/\(bundleName)"
            || path == "\(home)/Applications/\(bundleName)"
    }

    /// Traduz a resposta do sistema para o que a interface precisa saber.
    public static func state(from status: SMAppService.Status) -> State {
        switch status {
        case .enabled:                  return .on
        case .requiresApproval:         return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default:               return .off
        }
    }

    /// O estado atual, consultado ao sistema.
    ///
    /// Chamado toda vez que o menu se remonta, nunca guardado: a pessoa desliga
    /// o app nos Ajustes do Sistema sem avisar ninguém, e um checkmark guardado
    /// em variável passaria a mentir a partir daí.
    public static func current(status: (() -> SMAppService.Status)? = nil) -> State {
        state(from: (status ?? systemStatus)())
    }

    /// Registra o app para abrir com o sistema.
    ///
    /// Recusa fora do local instalado. Sem essa recusa, ligar a opção rodando
    /// `build/NeverType.app` registraria a cópia do repositório — que o
    /// `build-app.sh` reconstrói do zero a cada compilação — e nem o `status`
    /// nem o `register()` acusariam nada.
    public static func enable(
        bundlePath: String = Bundle.main.bundlePath,
        home: String = NSHomeDirectory(),
        register: (() throws -> Void)? = nil,
        status: (() -> SMAppService.Status)? = nil
    ) -> Outcome {
        guard isInstalledLocation(bundlePath: bundlePath, home: home) else {
            return .refused("""
                esta cópia está em \(bundlePath), e só a instalada abre com o sistema. \
                Rode: bash scripts/install.sh
                """)
        }
        do {
            try (register ?? systemRegister)()
        } catch {
            return .refused("o macOS recusou o registro: \(error.localizedDescription)")
        }
        return .changed(state(from: (status ?? systemStatus)()))
    }

    /// Tira o app da inicialização.
    ///
    /// Sem guarda de caminho, ao contrário de `enable`. Como o BTM indexa por
    /// bundle ID, a baixa feita de qualquer cópia limpa o registro de todas
    /// (medido no mesmo spike) — e travar o desligamento porque a pessoa está
    /// rodando a cópia errada seria prendê-la num estado que ela quer sair.
    public static func disable(
        unregister: (() throws -> Void)? = nil,
        status: (() -> SMAppService.Status)? = nil
    ) -> Outcome {
        do {
            try (unregister ?? systemUnregister)()
        } catch {
            return .refused("o macOS recusou a baixa do registro: \(error.localizedDescription)")
        }
        return .changed(state(from: (status ?? systemStatus)()))
    }

    /// Abre o painel de Itens de Início de Sessão.
    ///
    /// Pela API, e não por uma `x-apple.systempreferences:` montada à mão: o
    /// identificador desse painel já mudou entre versões do macOS, e uma URL
    /// errada não abre nada nem reclama.
    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - As chamadas de sistema, isoladas para o teste poder trocá-las

    private static func systemStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    private static func systemRegister() throws {
        try SMAppService.mainApp.register()
    }

    private static func systemUnregister() throws {
        try SMAppService.mainApp.unregister()
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
