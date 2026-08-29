import AVFoundation
import Testing
@testable import NeverTypeCore

// XCTest vive dentro do Xcode, que esta máquina não tem — a Parte 2 decidiu
// construir sem ele. swift-testing vem no próprio toolchain do Swift 6 e roda
// sob `swift test` do mesmo jeito.
@Suite("Conversão de áudio")
struct AudioConversionTests {

    /// Gera um tom sintético no formato pedido, sem tocar no hardware.
    private func tone(format: AVAudioFormat, seconds: Double, hz: Double = 440) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try #require(buffer.floatChannelData)
        for ch in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) {
                let t = Double(frame) / format.sampleRate
                channels[ch][frame] = Float(sin(2 * .pi * hz * t) * 0.5)
            }
        }
        return buffer
    }

    private func frames(_ buffers: [AVAudioPCMBuffer]) -> Int {
        buffers.reduce(0) { $0 + Int($1.frameLength) }
    }

    private func hardware(_ rate: Double, _ channels: AVAudioChannelCount) throws -> AVAudioFormat {
        try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: rate,
                                   channels: channels,
                                   interleaved: false))
    }

    /// O caso real: o hardware entrega 48 kHz estéreo, o Whisper quer 16 kHz mono.
    @Test("48 kHz estéreo vira 16 kHz mono")
    func convertsFortyEightStereoToSixteenMono() throws {
        let input = try hardware(48_000, 2)
        let resampler = try Resampler(inputFormat: input)

        #expect(resampler.outputFormat.sampleRate == 16_000)
        #expect(resampler.outputFormat.channelCount == 1)

        let output = try resampler.convert(try tone(format: input, seconds: 1.0))
        let first = try #require(output.first)
        #expect(first.format.sampleRate == 16_000)
        #expect(first.format.channelCount == 1)

        // Um segundo entra, um segundo sai — contando o dreno. Sem ele o filtro
        // retém o fim da fala, que num ditado é a última palavra.
        let total = frames(output) + frames(try resampler.drain())
        #expect(abs(total - 16_000) <= 40, "1 s deveria virar ~16000 quadros, veio \(total)")
    }

    /// Se o hardware já entrega 16 kHz mono, a conversão é identidade: não pode
    /// perder nem inventar amostra.
    @Test("16 kHz mono passa intacto")
    func passesThroughWhenHardwareAlreadyMatches() throws {
        let input = try hardware(16_000, 1)
        let resampler = try Resampler(inputFormat: input)
        let output = try resampler.convert(try tone(format: input, seconds: 0.5))
        #expect(frames(output) + frames(try resampler.drain()) == 8_000)
    }

    /// Fone Bluetooth entra em HFP a 8 kHz quando o microfone abre. A Parte 2 não
    /// conserta a qualidade disso, mas a conversão não pode quebrar.
    @Test("8 kHz de fone Bluetooth sobe para 16 kHz")
    func upsamplesFromBluetoothHandsFreeRate() throws {
        let input = try hardware(8_000, 1)
        let resampler = try Resampler(inputFormat: input)
        let output = try resampler.convert(try tone(format: input, seconds: 1.0))
        #expect(try #require(output.first).format.sampleRate == 16_000)
        let total = frames(output) + frames(try resampler.drain())
        #expect(abs(total - 16_000) <= 40, "veio \(total)")
    }

    /// Blindagem do bug achado ao escrever estes testes: o dreno não pode devolver
    /// vazio depois de uma conversão que reteve amostras, senão o fim da fala some.
    @Test("o dreno devolve o que o filtro reteve")
    func drainReturnsTheHeldTail() throws {
        let input = try hardware(48_000, 2)
        let resampler = try Resampler(inputFormat: input)
        let body = try resampler.convert(try tone(format: input, seconds: 1.0))
        let tail = try resampler.drain()
        #expect(frames(tail) > 0, "o filtro reteve amostras e o dreno não devolveu nada")
        #expect(frames(body) < 16_000, "se nada foi retido, este teste perdeu o sentido")
    }

    /// O contrato com o whisper-cli. Se isto mudar, a Parte 3 quebra sem aviso.
    @Test("formato em disco é o que o Whisper espera")
    func fileSettingsMatchWhatWhisperExpects() {
        let s = AudioSpec.fileSettings
        #expect(s[AVSampleRateKey] as? Double == 16_000)
        #expect(s[AVNumberOfChannelsKey] as? AVAudioChannelCount == 1)
        #expect(s[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(s[AVLinearPCMIsFloatKey] as? Bool == false)
    }
}

@Suite("Trigger da hotkey")
struct HotkeyTriggerTests {
    /// O trigger precisa ser um modificador puro e identificado pelo lado: a
    /// máscara `.command` liga com qualquer um dos dois ⌘, então só o keyCode
    /// somado à máscara de dispositivo distingue o direito do esquerdo.
    @Test("⌘ direito tem keyCode e máscara de dispositivo distintos")
    func rightCommandIsIdentifiedByCodeAndMask() {
        let t = HotkeyMonitor.Trigger.rightCommand
        #expect(t.keyCode == 54)
        #expect(t.deviceMask == 0x0010)
        #expect(t.deviceMask != HotkeyMonitor.Trigger.rightOption.deviceMask)
        #expect(t.keyCode != HotkeyMonitor.Trigger.rightOption.keyCode)
    }

    /// A escolha é guardada pelo keyCode, e não pelo rótulo: rótulo é texto de
    /// interface e muda; keyCode é estável entre versões do macOS.
    @Test("a tecla escolhida sobrevive a ida e volta pelo identificador")
    func triggerRoundTripsThroughID() {
        for option in HotkeyMonitor.Trigger.all {
            #expect(HotkeyMonitor.Trigger.named(option.id)?.keyCode == option.keyCode)
        }
    }

    @Test("identificador desconhecido ou ausente não devolve trigger")
    func unknownTriggerIsNil() {
        #expect(HotkeyMonitor.Trigger.named(nil) == nil)
        #expect(HotkeyMonitor.Trigger.named("999") == nil, "keyCode que não oferecemos")
        #expect(HotkeyMonitor.Trigger.named("⌘ direito") == nil, "rótulo não é identificador")
    }

    /// Só modificador puro: qualquer outra coisa exigiria engolir o evento com
    /// um CGEventTap, que o projeto recusou.
    @Test("todas as opções são modificadores puros e distintas entre si")
    func optionsAreDistinctPureModifiers() {
        let codes = HotkeyMonitor.Trigger.all.map(\.keyCode)
        let masks = HotkeyMonitor.Trigger.all.map(\.deviceMask)
        #expect(Set(codes).count == codes.count, "keyCode repetido faria duas opções virarem uma")
        #expect(Set(masks).count == masks.count, "máscara repetida não distinguiria o lado")
    }
}


/// O ciclo de vida do arquivo — a parte que o DoD 4 manda garantir e que, até a
/// auditoria da Parte 2, só dava para exercitar falando no microfone.
@Suite("Ciclo do arquivo de gravação")
struct RecordingSinkTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevertype-test-\(UUID().uuidString)")
            .appendingPathComponent("last.wav")
    }

    private func hardware() throws -> AVAudioFormat {
        try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 48_000, channels: 2, interleaved: false))
    }

    private func buffer(_ format: AVAudioFormat, seconds: Double) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let b = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        b.frameLength = frames
        let ch = try #require(b.floatChannelData)
        for c in 0..<Int(format.channelCount) {
            for f in 0..<Int(frames) { ch[c][f] = Float(sin(Double(f) * 0.01) * 0.3) }
        }
        return b
    }

    @Test("gravação concluída deixa o arquivo no formato do Whisper")
    func finishKeepsFile() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        let result = try sink.finish()

        #expect(result == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let written = try AVAudioFile(forReading: url)
        #expect(written.fileFormat.sampleRate == 16_000)
        #expect(written.fileFormat.channelCount == 1)
        #expect(written.length > 7_000, "0,5 s deveria dar ~8000 quadros, deu \(written.length)")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// O check 4 do DoD: tecla comum durante o hold cancela **sem gerar arquivo**.
    @Test("cancelamento apaga o arquivo e não devolve URL")
    func discardRemovesFile() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        #expect(FileManager.default.fileExists(atPath: url.path), "o arquivo existe durante a gravação")

        sink.discard()
        let result = try sink.finish()

        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path), "cancelar tem que apagar o arquivo")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("finish duas vezes não quebra nem ressuscita o arquivo")
    func finishIsIdempotent() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))
        #expect(try sink.finish() == url)
        #expect(try sink.finish() == nil, "a segunda chamada não tem o que fechar")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("cancelar depois de fechar não apaga o que já foi salvo")
    func discardAfterFinishDoesNotDelete() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.2))
        _ = try sink.finish()
        sink.discard()
        _ = try sink.finish()
        #expect(FileManager.default.fileExists(atPath: url.path), "gravação já concluída não pode ser apagada depois")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// O áudio do ditado fica em memória para a Parte 3 transcrever. Cancelar
    /// tem que apagar isso também, não só o arquivo — e nenhum teste cobria,
    /// então inverter a ordem em `finish()` quebraria a limpeza em silêncio.
    @Test("cancelar limpa as amostras da memória, não só o arquivo")
    func discardClearsSamples() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        #expect(sink.samples.count > 0, "durante a gravação as amostras existem")

        sink.discard()
        _ = try sink.finish()
        #expect(sink.samples.isEmpty, "cancelar tem que descartar o áudio da memória")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("gravação concluída preserva as amostras para a transcrição")
    func finishKeepsSamples() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        let fmt = try hardware()
        try sink.begin(inputFormat: fmt)
        try sink.append(try buffer(fmt, seconds: 0.5))
        _ = try sink.finish()
        // 0,5 s a 16 kHz, com o dreno incluído.
        #expect(abs(sink.samples.count - 8_000) <= 40, "veio \(sink.samples.count)")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("append sem begin não escreve nem quebra")
    func appendWithoutBeginIsSafe() throws {
        let url = tempURL()
        let sink = RecordingSink(destination: url)
        try sink.append(try buffer(try hardware(), seconds: 0.1))
        #expect(!sink.isOpen)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

/// O medidor existe para responder uma pergunta: está entrando som? Então o que
/// se testa é justamente a distinção entre silêncio e som — não a aparência.
@Suite("Nível de entrada do microfone")
struct AudioLevelTests {

    @Test("silêncio absoluto dá zero")
    func silenceIsZero() {
        #expect(AudioLevel.rms([Float](repeating: 0, count: 1024)) == 0)
        #expect(AudioLevel.normalized(rms: 0) == 0)
    }

    /// O caso que motiva o item: microfone mudo entrega amostras quase nulas, e
    /// isso tem que aparecer como silêncio, não como um tremor de barra.
    @Test("ruído abaixo do piso de -50 dBFS conta como silêncio")
    func noiseFloorIsSilence() {
        // -60 dBFS: ruído de sala num microfone de laptop.
        let quiet = AudioLevel.normalized(rms: 0.001)
        #expect(quiet == 0, "veio \(quiet) — abaixo do piso não pode mexer a barra")
    }

    @Test("fala normal fica no meio da escala, não colada no chão")
    func speechIsVisible() {
        // ~0,05 de RMS é fala em volume de conversa.
        let level = AudioLevel.normalized(rms: 0.05)
        #expect(level > 0.3 && level < 0.9,
                "veio \(level) — escala linear deixaria a fala quase invisível")
    }

    @Test("saturação satura em 1, não passa")
    func clippingClamps() {
        #expect(AudioLevel.normalized(rms: 1.0) == 1)
        #expect(AudioLevel.normalized(rms: 4.0) == 1, "acima de 0 dBFS continua 1")
    }

    @Test("o RMS acompanha a energia do sinal")
    func rmsFollowsEnergy() {
        let baixo = AudioLevel.rms([Float](repeating: 0.1, count: 512))
        let alto = AudioLevel.rms([Float](repeating: 0.5, count: 512))
        #expect(alto > baixo)
        #expect(abs(baixo - 0.1) < 0.0001, "sinal constante: RMS é o próprio valor")
    }

    @Test("array vazio não quebra")
    func emptyIsSafe() {
        #expect(AudioLevel.rms([]) == 0)
    }
}


/// A trava de mãos-livres. Cada caminho aqui é um que, sem a máquina de estados
/// separada, só daria para exercitar apertando teclas em milissegundos exatos.
@Suite("Trava de mãos-livres")
struct LatchTests {
    private typealias L = HotkeyMonitor.Latch

    @Test("hold normal continua sendo apertar e soltar")
    func normalHold() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(L.tapThreshold + 0.1)) == [.finish])
        #expect(!latch.isLatched)
    }

    /// Um toque curto não conclui na hora: ele espera para ver se vem o segundo.
    @Test("toque curto adia a conclusão e conclui no timeout")
    func shortTapWaitsThenFinishes() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(0.05)) == [.armTimeout(L.tapWindow)],
                "toque curto não pode concluir antes da janela do segundo toque")
        #expect(latch.handle(.timeout) == [.finish])
    }

    @Test("duplo toque trava, e a gravação segue sem a tecla")
    func doubleTapLatches() {
        var latch = L()
        _ = latch.handle(.down(0))
        _ = latch.handle(.up(0.05))
        #expect(latch.handle(.down(0.15)) == [.disarmTimeout, .latch])
        #expect(latch.isLatched)
        // O `up` do segundo toque não pode encerrar nada.
        #expect(latch.handle(.up(0.2)) == [])
        #expect(latch.isLatched)
    }

    @Test("travado, um toque encerra e transcreve")
    func tapStopsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.down(5)) == [.finish])
        #expect(!latch.isLatched)
        #expect(latch.handle(.up(5.05)) == [], "o up seguinte é ignorado")
    }

    @Test("travado, Esc descarta")
    func escapeCancelsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.escape) == [.cancel])
        #expect(!latch.isLatched)
    }

    /// A diferença deliberada entre os dois modos: segurando, tecla comum
    /// significa "isto era um atalho"; em mãos-livres, teclar é só teclar.
    @Test("travado, tecla comum NÃO cancela")
    func otherKeyDoesNotCancelLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.otherKey) == [])
        #expect(latch.isLatched, "cancelar um ditado longo por causa de uma tecla mata o modo")
    }

    @Test("segurando, tecla comum cancela como antes")
    func otherKeyCancelsHold() {
        var latch = L()
        _ = latch.handle(.down(0))
        #expect(latch.handle(.otherKey) == [.cancel])
    }

    @Test("tecla comum na janela do segundo toque também cancela")
    func otherKeyCancelsWhileWaiting() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05))
        #expect(latch.handle(.otherKey) == [.disarmTimeout, .cancel])
    }

    @Test("evento fora de ordem não faz nada")
    func strayEventsAreIgnored() {
        var latch = L()
        #expect(latch.handle(.up(0)) == [], "soltar sem ter apertado")
        #expect(latch.handle(.timeout) == [], "timeout sem janela armada")
        #expect(latch.handle(.otherKey) == [], "tecla comum com nada em curso")
    }
}
