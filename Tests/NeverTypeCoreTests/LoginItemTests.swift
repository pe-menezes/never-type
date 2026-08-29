import Foundation
import ServiceManagement
import Testing
@testable import NeverTypeCore

/// A guarda que impede registrar a cópia errada, e os caminhos de falha do
/// registro.
///
/// Nenhum teste aqui toca o `SMAppService` de verdade: registrar login item
/// mexe no BTM do macOS, que é estado da máquina de quem está rodando a suíte —
/// e a baixa nem sempre é imediata. Todas as chamadas de sistema entram pelos
/// parâmetros injetados.
@Suite("Abrir com o sistema")
struct LoginItemTests {

    private func erroFalso(_ mensagem: String) -> NSError {
        NSError(domain: "com.nevertype.tests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: mensagem])
    }

    // MARK: - O que o sistema responde

    @Test("os quatro estados do SMAppService viram os três que a interface usa")
    func mapeiaTodosOsStatus() {
        #expect(LoginItem.state(from: .enabled) == .on)
        #expect(LoginItem.state(from: .requiresApproval) == .needsApproval,
                "desativado nos Ajustes exige ação fora do app, não colapsa em off")
        #expect(LoginItem.state(from: .notRegistered) == .off)
        #expect(LoginItem.state(from: .notFound) == .off,
                "notFound e notRegistered são distintos no sistema e iguais para a interface")
    }

    @Test("o estado atual é lido do sistema, não de cache")
    func leOEstadoDoSistema() {
        var consultas = 0
        let ler: () -> SMAppService.Status = { consultas += 1; return .enabled }

        #expect(LoginItem.current(status: ler) == .on)
        #expect(LoginItem.current(status: ler) == .on)
        #expect(consultas == 2, "cada consulta pergunta ao sistema de novo")
    }

    // MARK: - A guarda de caminho

    @Test("aceita os dois locais instalados e recusa o resto")
    func reconheceOLocalInstalado() {
        let home = "/Users/alguem"

        #expect(LoginItem.isInstalledLocation(bundlePath: "/Applications/NeverType.app", home: home))
        #expect(LoginItem.isInstalledLocation(bundlePath: "/Users/alguem/Applications/NeverType.app", home: home),
                "o install.sh documenta ~/Applications como fallback para máquina gerida")
        #expect(LoginItem.isInstalledLocation(bundlePath: "/Applications/NeverType.app/", home: home),
                "barra no fim é o mesmo lugar")

        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Users/alguem/repo/build/NeverType.app", home: home),
                "a cópia de build/ é apagada a cada compilação")
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/private/tmp/NeverType.app", home: home))
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Applications/Outro.app", home: home))
        #expect(!LoginItem.isInstalledLocation(bundlePath: "/Users/outra-pessoa/Applications/NeverType.app", home: home),
                "o ~/Applications que vale é o de quem está rodando")
    }

    /// O ponto do DoD: a recusa acontece **antes** de falar com o sistema.
    /// Registrar e depois arrepender-se não desfaz — o BTM já gravou.
    @Test("fora do local instalado, recusa sem chamar o registrador")
    func recusaSemRegistrar() {
        var chamou = false
        let outcome = LoginItem.enable(
            bundlePath: "/Users/alguem/repo/build/NeverType.app",
            home: "/Users/alguem",
            register: { chamou = true })

        #expect(!chamou, "o registrador não pode ser chamado fora do local instalado")
        guard case .refused(let razao) = outcome else {
            Issue.record("esperava recusa, veio \(outcome)")
            return
        }
        #expect(razao.contains("build/NeverType.app"), "a mensagem diz onde a cópia está")
        #expect(razao.contains("scripts/install.sh"), "a mensagem nomeia a ação de saída")
    }

    @Test("no local instalado, registra e devolve o estado novo")
    func registraNoLocalCerto() {
        var chamou = false
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/alguem",
            register: { chamou = true },
            status: { .enabled })

        #expect(chamou)
        #expect(outcome == .changed(.on))
    }

    /// O estado vem de perguntar de novo, não de assumir que deu certo.
    @Test("register que passa mas não liga devolve o estado real")
    func naoAssumeQueRegistrouLigou() {
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/alguem",
            register: {},
            status: { .requiresApproval })

        #expect(outcome == .changed(.needsApproval),
                "register() sem erro não prova que ligou — quem responde é o status")
    }

    // MARK: - Os caminhos de falha

    @Test("register que lança vira recusa com a razão do sistema")
    func registroQueLanca() {
        let outcome = LoginItem.enable(
            bundlePath: "/Applications/NeverType.app",
            home: "/Users/alguem",
            register: { throw self.erroFalso("Operation not permitted") })

        #expect(outcome == .refused("o macOS recusou o registro: Operation not permitted"))
    }

    @Test("unregister que lança vira recusa com a razão do sistema")
    func baixaQueLanca() {
        let outcome = LoginItem.disable(
            unregister: { throw self.erroFalso("Operation not permitted") })

        #expect(outcome == .refused("o macOS recusou a baixa do registro: Operation not permitted"))
    }

    /// Desligar não tem guarda de caminho de propósito: o BTM indexa por bundle
    /// ID, a baixa de qualquer cópia limpa todas, e travar o desligamento
    /// prenderia a pessoa num estado que ela quer sair.
    @Test("desligar funciona de qualquer cópia")
    func desligaDeQualquerLugar() {
        var chamou = false
        let outcome = LoginItem.disable(
            unregister: { chamou = true },
            status: { .notRegistered })

        #expect(chamou)
        #expect(outcome == .changed(.off))
    }
}
