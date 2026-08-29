import Foundation
import Testing
@testable import NeverTypeCore

@Suite("Localização e validação do modelo")
struct ModelStoreTests {

    @Test("o magic do ggml é validado pelos bytes, não pelo texto")
    func validatesByMagicBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // O magic 0x67676d6c gravado little-endian: os bytes saem "lmgg".
        // Procurar o texto "ggml" reprova todo modelo válido — erro já cometido
        // neste projeto, e este teste existe para ele não voltar.
        //
        // A regra é exercitada sem tocar o disco para não escrever 400 MB por
        // execução da suíte.
        let ok = Data([0x6c, 0x6d, 0x67, 0x67])
        #expect(ModelStore.isValid(magic: ok, size: ModelStore.minimumBytes))
        #expect(!ModelStore.isValid(magic: ok, size: ModelStore.minimumBytes - 1),
                "magic certo com tamanho de download truncado não pode passar")
        #expect(!ModelStore.isValid(magic: Data("ggml".utf8), size: ModelStore.minimumBytes),
                "\"ggml\" como texto não é o magic")

        // O que um proxy de filtragem devolve quando bloqueia o download.
        let html = dir.appendingPathComponent("bloqueado.bin")
        try Data("<html><body>403</body></html>".utf8).write(to: html)
        #expect(!ModelStore.isValid(html))

        let empty = dir.appendingPathComponent("vazio.bin")
        try Data().write(to: empty)
        #expect(!ModelStore.isValid(empty))

        #expect(!ModelStore.isValid(dir.appendingPathComponent("nao-existe.bin")))
    }

    /// Modelo truncado começa com o magic certo, o whisper.cpp o aceita como
    /// "modelo vazio", e a primeira inferência mata o processo com uma exceção
    /// de C++ que nenhum `try` do Swift intercepta. A auditoria da Parte 3
    /// reproduziu: 100 KB do modelo real no caminho de produção → exit 134, sem
    /// nenhum aviso na tela.
    @Test("modelo truncado com magic válido é recusado")
    func truncatedModelRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truncado-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // Magic correto, tamanho de um download interrompido.
        var bytes = Data([0x6c, 0x6d, 0x67, 0x67])
        bytes.append(Data(repeating: 0, count: 100 * 1024))
        try bytes.write(to: url)

        #expect(!ModelStore.isValid(url), "magic válido não pode bastar")
        #expect(throws: TranscriberError.self) { _ = try Transcriber(modelURL: url) }
    }

    /// O positivo do validador de disco. Até aqui `isValid(_:)` só tinha os
    /// negativos exercitados (HTML, vazio, truncado, ausente): um validador que
    /// recusasse tudo passaria na suíte. Arquivo esparso: `truncate` estende o
    /// tamanho lógico sem escrever os bytes, então o teste custa KB, não os
    /// 400 MB do piso — e é o tamanho lógico que `isValid` lê.
    @Test("no disco, o piso de tamanho separa modelo inteiro de download truncado")
    func diskFloorSeparatesWholeFromTruncated() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-piso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func sparseModel(named name: String, bytes: Int) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data([0x6c, 0x6d, 0x67, 0x67]).write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(bytes))
            return url
        }

        let whole = try sparseModel(named: "inteiro.bin", bytes: ModelStore.minimumBytes)
        let truncated = try sparseModel(named: "truncado.bin", bytes: ModelStore.minimumBytes - 1)

        let wholeAttributes = try FileManager.default.attributesOfItem(atPath: whole.path)
        let wholeSize = try #require(wholeAttributes[.size] as? Int)
        #expect(wholeSize == ModelStore.minimumBytes,
                "o arquivo esparso precisa reportar o tamanho lógico, veio \(wholeSize)")
        #expect(ModelStore.isValid(whole), "magic certo e tamanho no piso é modelo inteiro")
        #expect(!ModelStore.isValid(truncated), "um byte abaixo do piso é download truncado")
    }

    @Test("o modelo é procurado em Application Support, fora do repositório")
    func modelLivesOutsideTheRepo() {
        let path = ModelStore.modelURL.path
        #expect(path.contains("Application Support/NeverType/models"))
        #expect(path.hasSuffix("ggml-large-v3-turbo-q5_0.bin"))
    }

    @Test("modelo ausente falha com instrução, não com erro cru")
    func missingModelExplainsItself() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("nao-existe-\(UUID().uuidString).bin")
        #expect(throws: TranscriberError.self) {
            _ = try Transcriber(modelURL: absent)
        }
        let message = String(describing: TranscriberError.modelMissing(absent))
        #expect(message.contains("fetch-model.sh"), "o erro precisa dizer o que fazer")
    }

    @Test("arquivo inválido é recusado antes de tentar carregar")
    func invalidModelRejectedEarly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalido-\(UUID().uuidString).bin")
        try Data("<html>403</html>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: TranscriberError.self) {
            _ = try Transcriber(modelURL: url)
        }
    }
}


/// Primeiro fixture disponível, se houver algum.
///
/// Os fixtures são gravações de voz de quem desenvolve e não são versionados, então
/// num clone limpo não existe nenhum. Sem esta checagem a suíte inteira **falhava**
/// em vez de ser pulada — `#require` reprova o teste, não o suspende.
func firstFixture() -> URL? {
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("fixtures")
    let wavs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "wav" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return wavs?.first
}

func transcriptionTestsRunnable() -> Bool {
    FileManager.default.fileExists(atPath: ModelStore.modelURL.path) && firstFixture() != nil
}

/// Transcrição de verdade. Precisa do modelo instalado **e** de pelo menos um
/// fixture gravado — os dois ficam fora do repositório.
@Suite("Transcrição local", .enabled(if: transcriptionTestsRunnable()))
struct TranscriberTests {

    @Test("transcreve um fixture gravado")
    func transcribesRealAudio() throws {
        let fixture = try #require(firstFixture())
        let samples = try readSamples(fixture)
        #expect(samples.count > 16_000, "o fixture precisa ter pelo menos 1 s de áudio")

        let transcriber = try Transcriber()
        let text = try transcriber.transcribe(samples)

        // A assertiva é sobre o mecanismo, não sobre palavras específicas: o
        // conteúdo depende do que quem clonou gravou.
        #expect(!text.isEmpty, "a transcrição não pode voltar vazia")
        #expect(text.count < samples.count / 40,
                "texto desproporcional ao áudio sugere alucinação: \(text.count) caracteres")
    }

    /// O aquecimento existe para a primeira transcrição real não ser a mais
    /// lenta. Aqui só se garante que ele roda e não quebra.
    @Test("aquecimento não lança nem invalida o contexto")
    func warmUpKeepsContextUsable() throws {
        let transcriber = try Transcriber()
        transcriber.warmUp()
        let text = try transcriber.transcribe([Float](repeating: 0, count: 16_000))
        #expect(text.count < 200, "silêncio não deveria virar parágrafo: \(text)")
    }

    /// Percorre os chunks RIFF até achar o `data`, em vez de assumir 44 bytes.
    ///
    /// Os fixtures do ffmpeg têm o `data` em exatamente 44 bytes, mas o WAV que o
    /// próprio app grava (via `AVAudioFile`) tem em **4096** — há um chunk JUNK
    /// de padding. Com o offset fixo, apontar o teste para um arquivo do app
    /// engoliria 4052 bytes de padding como áudio e o teste **passaria** lendo
    /// entrada errada. A premissa antiga era verdadeira por acidente da
    /// ferramenta de gravação, não por propriedade do formato.
    private func readSamples(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var offset = 12   // "RIFF" + tamanho + "WAVE"
        var dataRange: Range<Int>?

        func u32(_ at: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) }
        }

        while offset + 8 <= data.count {
            let id = String(decoding: data[(data.startIndex + offset)..<(data.startIndex + offset + 4)], as: UTF8.self)
            let size = u32(offset + 4)
            if id == "data" {
                dataRange = (offset + 8)..<min(offset + 8 + size, data.count)
                break
            }
            offset += 8 + size + (size % 2)   // chunks têm padding para tamanho par
        }

        let range = try #require(dataRange, "chunk 'data' não encontrado em \(url.lastPathComponent)")
        let pcm = Array(data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)])
        return stride(from: 0, to: pcm.count - 1, by: 2).map { i in
            Float(Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i + 1]) << 8)) / 32768.0
        }
    }
}
