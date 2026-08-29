import Foundation
import Testing
@testable import FalaFlowCore

/// As duas listas resolvem problemas diferentes, e os testes tratam disso: o
/// prompt é dica, a substituição é garantia.
@Suite("Vocabulário e substituições")
struct VocabularyTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("falaflow-vocab-\(UUID().uuidString)")
            .appendingPathComponent("vocabulario.json")
    }

    private func fresh() -> (Vocabulary, URL) {
        let url = tempURL()
        return (Vocabulary(url: url), url)
    }

    // MARK: - Prompt

    @Test("sem termos não há prompt, e o whisper roda como sempre")
    func emptyMeansNoPrompt() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(v.prompt == nil, "prompt vazio ainda seria um prompt, e enviesaria o modelo à toa")
    }

    @Test("os termos viram uma frase, não uma lista crua")
    func promptReadsAsLanguage() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["FalaFlow", "whisper.cpp"])
        #expect(v.prompt == "FalaFlow, whisper.cpp.")
    }

    @Test("termo vazio ou só espaço não entra na lista")
    func blankTermsAreDropped() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["FalaFlow", "", "   ", "  Pix  "])
        #expect(v.terms == ["FalaFlow", "Pix"], "e o que sobra vem sem espaço nas pontas")
    }

    // MARK: - Substituições

    @Test("a troca acontece e respeita a caixa que foi pedida no destino")
    func replacesWithRequestedCase() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "transcrição", to: "transação")])
        #expect(v.apply(to: "essa transcrição foi negada") == "essa transação foi negada")
    }

    @Test("busca ignora maiúsculas, mas escreve exatamente o destino")
    func searchIsCaseInsensitive() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "pix", to: "Pix")])
        #expect(v.apply(to: "manda um PIX, um Pix ou um pix") == "manda um Pix, um Pix ou um Pix",
                "corrigir a caixa de uma palavra é justamente um dos usos")
    }

    /// Sem fronteira de palavra, trocar "ia" por "IA" estragaria "família".
    @Test("só casa palavra inteira")
    func matchesWholeWordsOnly() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "ia", to: "IA")])
        #expect(v.apply(to: "a família ia embora") == "a família IA embora")
    }

    @Test("caractere especial no termo é tratado como texto, não como regex")
    func specialCharactersAreLiteral() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "whisper.cpp", to: "whisper.cpp")])
        #expect(v.apply(to: "usa o whisperXcpp aqui") == "usa o whisperXcpp aqui",
                "o ponto não pode virar coringa e casar com o X")
    }

    @Test("substituição com origem ou destino vazio não entra")
    func blankReplacementsAreDropped() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([
            Replacement(from: "", to: "algo"),
            Replacement(from: "algo", to: ""),
            Replacement(from: "bom", to: "ótimo"),
        ])
        #expect(v.replacements == [Replacement(from: "bom", to: "ótimo")],
                "origem vazia casaria com tudo")
    }

    @Test("várias substituições se aplicam na ordem da lista")
    func replacementsChain() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([
            Replacement(from: "vibe flow", to: "vibeflow"),
            Replacement(from: "fala flow", to: "FalaFlow"),
        ])
        #expect(v.apply(to: "o vibe flow e o fala flow") == "o vibeflow e o FalaFlow")
    }

    @Test("texto sem nada para trocar sai idêntico")
    func untouchedTextIsIdentical() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setReplacements([Replacement(from: "pix", to: "Pix")])
        #expect(v.apply(to: "nada aqui muda") == "nada aqui muda")
    }

    // MARK: - Disco

    @Test("as duas listas sobrevivem ao fechar e reabrir")
    func survivesRestart() {
        let (v, url) = fresh()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        v.setTerms(["FalaFlow"])
        v.setReplacements([Replacement(from: "pix", to: "Pix")])

        let depois = Vocabulary(url: url)
        #expect(depois.terms == ["FalaFlow"])
        #expect(depois.replacements == [Replacement(from: "pix", to: "Pix")])
    }

    @Test("arquivo corrompido começa vazio em vez de quebrar")
    func corruptFileStartsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("isto não é json".utf8).write(to: url)

        let v = Vocabulary(url: url)
        #expect(v.terms.isEmpty)
        #expect(v.prompt == nil)
    }
}
