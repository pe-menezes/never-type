import AppKit
import Carbon.HIToolbox
import Testing
@testable import FalaFlowCore

/// O contrato central: mexemos no pasteboard da pessoa, então devolvemos o que
/// estava lá — inclusive quando a inserção falha no meio.
///
/// Usa um pasteboard nomeado próprio, nunca o `.general`: um teste que sequestra
/// a área de transferência de quem está rodando a suíte é hostil.
@Suite("Inserção de texto no cursor")
@MainActor
struct TextInjectorTests {

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.falaflow.tests.\(UUID().uuidString)"))
    }

    @Test("o conteúdo anterior volta depois da inserção")
    func restoresPreviousContent() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("o que estava lá antes", forType: .string)

        let outcome = TextInjector.insert("texto ditado", pasteboard: pb, paste: { true })
        #expect(outcome == .inserted)
        #expect(pb.string(forType: .string) == "texto ditado", "durante a inserção o texto é o ditado")

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "o que estava lá antes",
                "o conteúdo anterior tem que voltar")
    }

    /// O caminho que mais importa: se a colagem falha, o pasteboard não pode
    /// ficar com o texto ditado no lugar do que a pessoa tinha copiado.
    @Test("devolve o conteúdo mesmo quando a colagem falha")
    func restoresEvenWhenPasteFails() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("conteúdo importante", forType: .string)

        let outcome = TextInjector.insert("texto ditado", pasteboard: pb, paste: { false })
        #expect(outcome == .failed("não consegui enviar ⌘V"))

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "conteúdo importante",
                "falhar em colar não pode custar o clipboard da pessoa")
    }

    /// Guardar só a string perderia imagem, arquivo, HTML — tudo que não fosse
    /// texto simples.
    @Test("preserva tipos que não são texto")
    func preservesNonTextTypes() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        let html = "<b>negrito</b>"
        pb.clearContents()
        let original = NSPasteboardItem()
        original.setString("texto simples", forType: .string)
        original.setString(html, forType: .html)
        #expect(pb.writeObjects([original]))

        TextInjector.insert("ditado", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))

        #expect(pb.string(forType: .string) == "texto simples")
        #expect(pb.string(forType: .html) == html, "o HTML tem que sobreviver")
    }

    @Test("pasteboard vazio antes continua vazio depois")
    func emptyStaysEmpty() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        TextInjector.insert("ditado", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))

        #expect(pb.string(forType: .string) == nil, "não pode sobrar o texto ditado")
    }

    /// Gestores de clipboard bem-comportados respeitam esta marca e não gravam o
    /// item no histórico. Sem ela, cada ditado sobreviveria à restauração dentro
    /// do Raycast ou do Maccy.
    @Test("o item é marcado como oculto para gestores de clipboard")
    func marksItemConcealed() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        TextInjector.insert("segredo ditado", pasteboard: pb, paste: { true })
        let types = pb.pasteboardItems?.first?.types ?? []
        #expect(types.contains(TextInjector.concealed))
    }

    /// A corrida que a auditoria reproduziu: dois ditados em menos que o atraso
    /// de restauração deixavam o texto do primeiro no lugar do conteúdo da
    /// pessoa, permanentemente.
    @Test("dois ditados seguidos devolvem o conteúdo original, não o do primeiro")
    func consecutiveInsertsRestoreTheOriginal() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("conteúdo original da pessoa", forType: .string)

        TextInjector.insert("primeiro ditado", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(0.25))
        TextInjector.insert("segundo ditado", pasteboard: pb, paste: { true })
        #expect(pb.string(forType: .string) == "segundo ditado")

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.6))
        #expect(pb.string(forType: .string) == "conteúdo original da pessoa",
                "veio \(pb.string(forType: .string) ?? "nil") — o texto do primeiro ditado não pode sobrar")
    }

    /// A restauração era incondicional: qualquer coisa que a pessoa copiasse nos
    /// 600 ms seguintes a um ditado era revertida.
    @Test("não desfaz o que a pessoa copiou depois do ditado")
    func doesNotClobberLaterCopy() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("antigo", forType: .string)

        TextInjector.insert("ditado", pasteboard: pb, paste: { true })
        try await Task.sleep(for: .seconds(0.2))

        // A pessoa copia outra coisa antes de a restauração disparar.
        pb.clearContents()
        pb.setString("acabei de copiar isto", forType: .string)

        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.6))
        #expect(pb.string(forType: .string) == "acabei de copiar isto",
                "a restauração não pode atropelar uma cópia mais nova")
    }

    /// Com entrada segura ativa não há colagem — então o texto tem que ficar no
    /// pasteboard, que é o que a spec pede. A versão anterior retornava antes de
    /// tocar no pasteboard e não deixava nada.
    @Test("entrada segura deixa o texto no pasteboard em vez de colar")
    func secureInputLeavesTextBehind() async throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("conteúdo anterior", forType: .string)

        var pasted = false
        let outcome = TextInjector.insert("texto ditado", pasteboard: pb,
                                          paste: { pasted = true; return true },
                                          secureInput: { true })

        #expect(outcome == .blockedBySecureInput)
        #expect(!pasted, "com entrada segura não se tenta colar — o macOS descartaria o evento")
        #expect(pb.string(forType: .string) == "texto ditado",
                "o texto tem que ficar disponível para a pessoa colar")

        // Sem colagem não há restauração: o texto precisa permanecer.
        try await Task.sleep(for: .seconds(TextInjector.restoreDelay + 0.4))
        #expect(pb.string(forType: .string) == "texto ditado",
                "sem colar, o texto não pode ser apagado por uma restauração")
    }

    @Test("texto vazio não mexe no pasteboard")
    func emptyTextIsNoop() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("intacto", forType: .string)

        #expect(TextInjector.insert("", pasteboard: pb, paste: { true }) == .failed("texto vazio"))
        #expect(pb.string(forType: .string) == "intacto")
    }
}
