import AVFoundation

/// Formato que o Whisper consome: 16 kHz, mono.
public enum AudioSpec {
    public static let sampleRate: Double = 16_000
    public static let channels: AVAudioChannelCount = 1

    /// Formato de processamento em memória: float32, o que o AVAudioConverter produz.
    public static var processing: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: sampleRate,
                      channels: channels,
                      interleaved: false)!
    }

    /// Formato em disco: PCM 16-bit little-endian. O AVAudioFile converte de
    /// float32 para inteiro ao escrever.
    public static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }
}

// Os casos guardam texto, e não os objetos do AVFoundation: `Error` implica
// `Sendable` no Swift 6, e AVAudioFormat não é. O texto é tudo que a mensagem usa.
public enum AudioError: Error, CustomStringConvertible {
    case converterUnavailable(from: String)
    case bufferAllocationFailed
    case conversionFailed(String)

    public var description: String {
        switch self {
        case .converterUnavailable(let f):
            return "não consegui converter de \(f) para 16 kHz mono"
        case .bufferAllocationFailed:
            return "falha ao alocar buffer de áudio"
        case .conversionFailed(let e):
            return "conversão de áudio falhou: \(e)"
        }
    }
}

extension AVAudioFormat {
    /// Descrição curta para mensagem de erro: "48000 Hz / 2 canais".
    var shortDescription: String {
        "\(Int(sampleRate)) Hz / \(channelCount) canal(is)"
    }
}

/// Converte áudio do formato do hardware para 16 kHz mono.
///
/// É uma unidade separada do gravador de propósito: é a parte que dá para testar
/// sem microfone, e é onde mora o erro fácil de cometer.
public final class Resampler {
    public let inputFormat: AVAudioFormat
    public let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    public init(inputFormat: AVAudioFormat) throws {
        let output = AudioSpec.processing
        guard let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw AudioError.converterUnavailable(from: inputFormat.shortDescription)
        }
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.converter = converter
    }

    /// Converte um buffer, devolvendo tudo que o conversor produziu.
    ///
    /// Devolve uma lista porque uma única chamada de `convert` não esgota o
    /// conversor: ele preenche até a capacidade do buffer de saída e guarda o
    /// resto. Ao subir de 8 kHz para 16 kHz isso transbordava e o excedente era
    /// perdido em silêncio.
    public func convert(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
        var supplied = false
        return try pump { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
    }

    /// Esvazia o filtro no fim da gravação.
    ///
    /// O conversor segura amostras dentro do filtro de reamostragem entre
    /// chamadas. Durante a gravação isso não importa: o resíduo sai na chamada
    /// seguinte. No fim, importa — sem esvaziar, o último pedaço da fala é
    /// descartado, e é aí que costuma estar o fim da frase.
    ///
    /// Depois do dreno o conversor não serve mais; a instância morre com a gravação.
    public func drain() throws -> [AVAudioPCMBuffer] {
        try pump { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    /// Chama o conversor até ele parar de produzir.
    private func pump(_ block: @escaping AVAudioConverterInputBlock) throws -> [AVAudioPCMBuffer] {
        var produced: [AVAudioPCMBuffer] = []
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192) else {
                throw AudioError.bufferAllocationFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: out, error: &conversionError, withInputFrom: block)
            if let conversionError {
                throw AudioError.conversionFailed(conversionError.localizedDescription)
            }
            if out.frameLength > 0 { produced.append(out) }
            // .haveData com buffer cheio significa que ainda há saída represada.
            guard status == .haveData, out.frameLength > 0 else { break }
        }
        return produced
    }
}

extension AVAudioPCMBuffer {
    /// Cópia independente do conteúdo.
    ///
    /// O buffer entregue ao tap é reaproveitado pelo AVAudioEngine assim que o
    /// callback retorna. Levar ele para outra fila sem copiar é ler memória que
    /// já foi reescrita.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatFloat32,
              let source = floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let destination = copy.floatChannelData else { return nil }
        copy.frameLength = frameLength
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(frameLength))
        }
        return copy
    }
}

/// Escreve o WAV: conversão, dreno e descarte.
///
/// Separado do `AudioRecorder` de propósito. A parte que decide se o arquivo
/// sobrevive ou é apagado é exatamente a que o DoD manda garantir, e ela não
/// precisa de microfone para ser exercitada. Antes só dava para testá-la falando.
///
/// Não é seguro para uso concorrente: quem usa serializa o acesso.
public final class RecordingSink {
    public let destination: URL
    private var file: AVAudioFile?
    private var resampler: Resampler?
    private var discarded = false

    /// As amostras já convertidas, acumuladas em memória.
    ///
    /// A Parte 3 transcreve a partir daqui, não relendo o WAV: o arquivo em
    /// disco continua existindo como artefato de depuração, não como canal
    /// entre os módulos. Um ditado de 30 s são ~1,9 MB.
    public private(set) var samples: [Float] = []

    public init(destination: URL) { self.destination = destination }

    public var isOpen: Bool { file != nil }

    public func begin(inputFormat: AVAudioFormat) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        resampler = try Resampler(inputFormat: inputFormat)
        file = try AVAudioFile(forWriting: destination, settings: AudioSpec.fileSettings)
        discarded = false
        samples.removeAll(keepingCapacity: true)
    }

    public func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let resampler, let file else { return }
        for chunk in try resampler.convert(buffer) where chunk.frameLength > 0 {
            try file.write(from: chunk)
            collect(chunk)
        }
    }

    private func collect(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    public func discard() { discarded = true }

    /// Fecha e devolve o arquivo, ou nil se foi descartado. Idempotente.
    @discardableResult
    public func finish() throws -> URL? {
        guard let resampler, let file else { return nil }
        defer { self.resampler = nil; self.file = nil }
        if !discarded {
            for chunk in try resampler.drain() where chunk.frameLength > 0 {
                try file.write(from: chunk)
                collect(chunk)
            }
            return destination
        }
        self.file = nil
        samples.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: destination)
        return nil
    }
}

/// Grava do microfone e escreve um WAV de 16 kHz mono.
public final class AudioRecorder {
    public let destination: URL

    // O motor nasce e morre com cada ditado, em vez de viver junto com o app.
    // Um AVAudioEngine parado mas vivo mantém o nó de entrada configurado, e o
    // macOS continua contando o app como usuário do microfone — o indicador
    // laranja da menu bar fica aceso o tempo todo. Num app cujo argumento é
    // privacidade, isso é inaceitável mesmo sendo só um indicador.
    private var engine: AVAudioEngine?

    /// Fila serial que possui `file`, `resampler` e `discarded`.
    ///
    /// O tap roda na thread de áudio em tempo real e o encerramento roda na main.
    /// Antes, os dois tocavam o mesmo arquivo e o mesmo conversor sem
    /// sincronização — e o compilador não acusava, porque `AVAudioNodeTapBlock`
    /// não é marcado como `Sendable`. Concentrar toda mutação nesta fila resolve
    /// a corrida sem travar a thread de áudio: o tap só copia e despacha.
    private let io = DispatchQueue(label: "com.falaflow.audio-io")
    private let sink: RecordingSink

    public private(set) var isRecording = false

    /// Amostras do último ditado concluído, em 16 kHz mono. Vazio se cancelado.
    public private(set) var lastSamples: [Float] = []

    /// Chamado quando a gravação falha no meio. Sem isto, o erro morria num
    /// stderr que não vai a lugar nenhum quando o app é aberto pelo Finder: o
    /// ícone seguia vermelho e `stop()` devolvia a URL como se tivesse dado certo.
    /// Definido uma vez, antes da primeira gravação.
    public var onError: (@MainActor @Sendable (String) -> Void)?

    public init(destination: URL) {
        self.destination = destination
        self.sink = RecordingSink(destination: destination)
    }

    public func start() throws {
        guard !isRecording else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // O formato de entrada é lido agora, e não na inicialização: trocar de
        // microfone no meio do dia (fone Bluetooth) muda o formato do inputNode,
        // e um conversor cacheado passaria a converter do formato errado.
        let engine = AVAudioEngine()
        self.engine = engine
        // Se qualquer coisa abaixo lançar, `isRecording` fica falso e `stop()`
        // sai pelo guard sem soltar nada — o motor ficaria vivo em repouso, com
        // o indicador de microfone aceso, que é exatamente o que a criação por
        // ditado existe para evitar.
        var started = false
        defer { if !started { self.engine?.reset(); self.engine = nil } }

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        try io.sync { try self.sink.begin(inputFormat: hardwareFormat) }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            // Na thread de áudio, só copiar e sair. Converter e escrever acontece
            // na fila de E/S.
            guard let self, let copy = buffer.deepCopy() else { return }
            self.io.async { self.append(copy) }
        }

        engine.prepare()
        try engine.start()
        started = true
        isRecording = true
    }

    /// Converte e escreve. Sempre na fila de E/S.
    private func append(_ buffer: AVAudioPCMBuffer) {
        do { try sink.append(buffer) } catch { report("gravação interrompida: \(error)") }
    }

    private func report(_ message: String) {
        FileHandle.standardError.write(Data("falaflow: \(message)\n".utf8))
        // `Task { @MainActor in }` em vez de assumir isolamento: o salto é
        // verificado pelo compilador, não afirmado por mim.
        if let onError { Task { @MainActor in onError(message) } }
    }

    /// Encerra e devolve o arquivo. Devolve nil se a gravação foi cancelada.
    @discardableResult
    public func stop() -> URL? {
        guard isRecording else { return nil }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        // Soltar a instância é o que faz o macOS liberar o microfone de verdade.
        engine = nil
        isRecording = false

        // `sync` funciona como barreira: espera qualquer append em voo terminar
        // antes de drenar e fechar. `removeTap` não garante que não haja callback
        // em execução.
        var result: URL?
        io.sync {
            do { result = try self.sink.finish() }
            catch { self.report("fim da gravação perdido: \(error)") }
            self.lastSamples = self.sink.samples
        }
        return result
    }

    /// Cancela: encerra e apaga o arquivo, sem deixar rastro.
    public func cancel() {
        guard isRecording else { return }
        io.sync { self.sink.discard() }
        stop()
    }
}
