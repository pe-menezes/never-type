import Foundation

/// Gera os tons curtos do retorno auditivo.
///
/// Os sons do sistema (`Tink`, `Pop`, `Glass`) foram desenhados para *serem
/// notados* — são alertas. Aqui o som é confirmação de uma ação que a pessoa
/// acabou de fazer de propósito, então ele precisa ser o contrário disso.
///
/// Gerar em vez de escolher dá controle sobre as duas coisas que fazem um som
/// ser tranquilo ou irritante: a frequência e, principalmente, o envelope. Um
/// tom que começa e termina de repente estala; a subida e a descida suaves
/// abaixo são o que tira o estalo.
public enum Tone {
    public static let sampleRate: Double = 44_100

    /// Sobe e desce em 25 ms.
    ///
    /// Sem isso, o corte abrupto na borda do buffer vira um clique audível —
    /// que é exatamente o "tec" seco que se está tentando evitar.
    private static let fade: Double = 0.025

    /// Uma ou mais notas em sequência, como WAV de 16 bits mono.
    ///
    /// Devolve WAV, e não amostras, porque quem toca é o `NSSound`, que aceita
    /// `Data` e dispensa arquivo temporário.
    public static func wav(_ frequencies: [Double],
                           seconds: Double = 0.07,
                           amplitude: Double = 0.14) -> Data {
        var samples: [Int16] = []
        for frequency in frequencies {
            let count = Int(sampleRate * seconds)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = min(1, min(t, seconds - t) / fade)
                let value = sin(2 * .pi * frequency * t) * amplitude * max(0, envelope)
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        return riff(samples)
    }

    /// Cabeçalho WAV canônico + as amostras.
    ///
    /// Escrito à mão porque a alternativa seria carregar o AVFoundation e um
    /// arquivo em disco para produzir uns poucos KB de áudio: 44 bytes de
    /// cabeçalho mais 2 bytes por amostra — ~6 KB no padrão de 0,07 s, ~7,5 KB
    /// e ~11,5 KB nos tons do app (ver `Feedback`, em main.swift).
    static func riff(_ samples: [Int16]) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var out = Data()

        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

        ascii("RIFF")
        u32(UInt32(36 + dataSize))
        ascii("WAVE")

        ascii("fmt ")
        u32(16)                                     // tamanho do bloco fmt
        u16(1)                                      // PCM sem compressão
        u16(1)                                      // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * UInt32(bytesPerSample))  // bytes por segundo
        u16(UInt16(bytesPerSample))                 // alinhamento de bloco
        u16(16)                                     // bits por amostra

        ascii("data")
        u32(UInt32(dataSize))
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }
}
