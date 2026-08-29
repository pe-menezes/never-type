import Foundation
import Testing
@testable import NeverTypeCore

/// O WAV é conferido por bytes e campos, não por "o NSSound aceitou".
///
/// Um cabeçalho errado costuma produzir som que toca — errado, com a velocidade
/// ou o volume trocados — em vez de erro. Aqui a verificação é estrutural.
@Suite("Tons do retorno auditivo")
struct ToneTests {

    private func ascii(_ data: Data, at offset: Int, _ length: Int = 4) -> String {
        String(decoding: data[offset..<(offset + length)], as: UTF8.self)
    }

    private func u32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func u16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<(offset + 2)].reversed().reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    @Test("o cabeçalho é um RIFF/WAVE de PCM 16 bits mono")
    func headerIsCanonical() {
        let wav = Tone.wav([440], seconds: 0.05)
        #expect(ascii(wav, at: 0) == "RIFF")
        #expect(ascii(wav, at: 8) == "WAVE")
        #expect(ascii(wav, at: 12) == "fmt ")
        #expect(u32(wav, at: 16) == 16, "bloco fmt de PCM tem 16 bytes")
        #expect(u16(wav, at: 20) == 1, "1 = PCM sem compressão")
        #expect(u16(wav, at: 22) == 1, "mono")
        #expect(u32(wav, at: 24) == UInt32(Tone.sampleRate))
        #expect(u16(wav, at: 34) == 16, "16 bits por amostra")
        #expect(ascii(wav, at: 36) == "data")
    }

    /// Campo de tamanho errado é o defeito clássico do WAV escrito à mão: o
    /// arquivo abre e toca lixo no fim, ou corta antes.
    @Test("os campos de tamanho batem com os bytes que existem de verdade")
    func sizesMatchReality() {
        let wav = Tone.wav([440], seconds: 0.05)
        let dataSize = u32(wav, at: 40)
        #expect(Int(dataSize) == wav.count - 44, "o bloco data promete o que existe depois dele")
        #expect(u32(wav, at: 4) == UInt32(wav.count - 8), "o RIFF promete o resto do arquivo")
    }

    @Test("a duração pedida vira a quantidade certa de amostras")
    func durationMatchesSampleCount() {
        let wav = Tone.wav([440], seconds: 0.05)
        let esperado = Int(Tone.sampleRate * 0.05) * 2  // 2 bytes por amostra
        #expect(Int(u32(wav, at: 40)) == esperado)
    }

    @Test("duas notas ocupam o dobro de uma")
    func twoNotesAreTwiceAsLong() {
        let uma = Tone.wav([440], seconds: 0.05)
        let duas = Tone.wav([440, 660], seconds: 0.05)
        #expect(duas.count == uma.count * 2 - 44, "o cabeçalho não é contado duas vezes")
    }

    /// O envelope é o que separa "tom" de "estalo": sem subida suave, a
    /// descontinuidade na primeira amostra vira um clique.
    @Test("o som começa e termina em silêncio, sem estalo")
    func envelopeRemovesTheClick() {
        let wav = Tone.wav([440], seconds: 0.06)
        let first = Int16(littleEndian: wav[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        let last = Int16(littleEndian: wav[(wav.count - 2)...].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        #expect(abs(Int(first)) < 200, "a primeira amostra tem que sair do zero, veio \(first)")
        #expect(abs(Int(last)) < 200, "a última tem que voltar ao zero, veio \(last)")
    }

    @Test("o pico respeita a amplitude pedida")
    func amplitudeIsRespected() {
        let wav = Tone.wav([440], seconds: 0.06, amplitude: 0.2)
        var peak: Int16 = 0
        for i in stride(from: 44, to: wav.count - 1, by: 2) {
            let s = Int16(littleEndian: wav[i..<(i + 2)].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
            peak = max(peak, abs(s))
        }
        let esperado = Double(Int16.max) * 0.2
        #expect(Double(peak) > esperado * 0.9 && Double(peak) <= esperado * 1.01,
                "pico \(peak), esperado ~\(Int(esperado))")
    }
}
