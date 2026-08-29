import Foundation
import Testing
@testable import NeverTypeCore

/// O histórico guarda o que a pessoa falou. Os testes cobrem o teto, a
/// sobrevivência ao fechar o app, e o apagar — que é a única saída de quem não
/// quer mais aquilo no disco.
@Suite("Histórico de transcrições")
struct TranscriptHistoryTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-hist-\(UUID().uuidString)")
            .appendingPathComponent("historico.json")
    }

    @Test("a mais recente fica em primeiro")
    func mostRecentFirst() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        h.add("primeira")
        h.add("segunda")
        #expect(h.entries.map(\.text) == ["segunda", "primeira"])
        #expect(h.last?.text == "segunda")
    }

    @Test("texto vazio ou só espaço não entra")
    func emptyIsRejected() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        #expect(h.add("") == false)
        #expect(h.add("   \n  ") == false)
        #expect(h.entries.isEmpty)
    }

    @Test("o texto é guardado sem espaço sobrando nas pontas")
    func trimsWhitespace() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        h.add("  texto ditado \n")
        #expect(h.last?.text == "texto ditado")
    }

    /// Não é "guardar tudo": passar do teto derruba a mais antiga.
    @Test("o teto derruba a mais antiga, não a mais nova")
    func limitDropsOldest() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let h = TranscriptHistory(url: url)

        for i in 1...(TranscriptHistory.limit + 5) { h.add("ditado \(i)") }

        #expect(h.entries.count == TranscriptHistory.limit)
        #expect(h.last?.text == "ditado \(TranscriptHistory.limit + 5)")
        #expect(!h.entries.contains { $0.text == "ditado 1" }, "a mais antiga tem que ter caído")
    }

    /// O motivo de existir arquivo: fechar o app não pode apagar o que foi dito.
    @Test("sobrevive ao fechar e reabrir o app")
    func survivesRestart() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let primeira = TranscriptHistory(url: url)
        primeira.add("o que eu falei antes de fechar")

        let depois = TranscriptHistory(url: url)
        #expect(depois.last?.text == "o que eu falei antes de fechar")
    }

    @Test("limpar apaga o arquivo, não só a memória")
    func clearRemovesTheFile() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let h = TranscriptHistory(url: url)
        h.add("segredo")
        #expect(FileManager.default.fileExists(atPath: url.path))

        h.clear()
        #expect(h.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "arquivo vazio com nome de histórico ainda diz que existiu histórico")
        #expect(TranscriptHistory(url: url).entries.isEmpty, "e não volta ao reabrir")
    }

    /// Arquivo corrompido não pode derrubar o app nem impedir gravar depois.
    @Test("JSON ilegível começa vazio em vez de quebrar")
    func corruptFileStartsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("isto não é json".utf8).write(to: url)

        let h = TranscriptHistory(url: url)
        #expect(h.entries.isEmpty)
        h.add("depois do arquivo corrompido")
        #expect(h.last?.text == "depois do arquivo corrompido")
        #expect(TranscriptHistory(url: url).entries.count == 1, "a gravação nova consertou o arquivo")
    }
}
