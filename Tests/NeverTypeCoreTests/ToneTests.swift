import Foundation
import Testing
@testable import NeverTypeCore

/// The WAV is checked by bytes and fields, not by "NSSound accepted it".
///
/// A wrong header usually produces sound that plays — wrongly, with the speed or
/// the volume off — instead of an error. Here the verification is structural.
@Suite("Audible feedback tones")
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

    @Test("the header is a RIFF/WAVE of 16-bit mono PCM")
    func headerIsCanonical() {
        let wav = Tone.wav([440], seconds: 0.05)
        #expect(ascii(wav, at: 0) == "RIFF")
        #expect(ascii(wav, at: 8) == "WAVE")
        #expect(ascii(wav, at: 12) == "fmt ")
        #expect(u32(wav, at: 16) == 16, "a PCM fmt chunk has 16 bytes")
        #expect(u16(wav, at: 20) == 1, "1 = PCM, no compression")
        #expect(u16(wav, at: 22) == 1, "mono")
        #expect(u32(wav, at: 24) == UInt32(Tone.sampleRate))
        #expect(u16(wav, at: 34) == 16, "16 bits per sample")
        #expect(ascii(wav, at: 36) == "data")
    }

    /// A wrong size field is the classic defect of a hand-written WAV: the file
    /// opens and plays garbage at the end, or cuts off early.
    @Test("the size fields match the bytes that really exist")
    func sizesMatchReality() {
        let wav = Tone.wav([440], seconds: 0.05)
        let dataSize = u32(wav, at: 40)
        #expect(Int(dataSize) == wav.count - 44, "the data chunk promises what exists after it")
        #expect(u32(wav, at: 4) == UInt32(wav.count - 8), "the RIFF promises the rest of the file")
    }

    @Test("the requested duration becomes the right number of samples")
    func durationMatchesSampleCount() {
        let wav = Tone.wav([440], seconds: 0.05)
        let esperado = Int(Tone.sampleRate * 0.05) * 2  // 2 bytes per sample
        #expect(Int(u32(wav, at: 40)) == esperado)
    }

    @Test("two notes take up twice as much as one")
    func twoNotesAreTwiceAsLong() {
        let uma = Tone.wav([440], seconds: 0.05)
        let duas = Tone.wav([440, 660], seconds: 0.05)
        #expect(duas.count == uma.count * 2 - 44, "the header is not counted twice")
    }

    /// The envelope is what separates "tone" from "click": without a gentle
    /// rise, the discontinuity at the first sample becomes a click.
    @Test("the sound starts and ends in silence, with no click")
    func envelopeRemovesTheClick() {
        let wav = Tone.wav([440], seconds: 0.06)
        let first = Int16(littleEndian: wav[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        let last = Int16(littleEndian: wav[(wav.count - 2)...].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        #expect(abs(Int(first)) < 200, "the first sample has to start from zero, got \(first)")
        #expect(abs(Int(last)) < 200, "the last has to return to zero, got \(last)")
    }

    @Test("the peak respects the requested amplitude")
    func amplitudeIsRespected() {
        let wav = Tone.wav([440], seconds: 0.06, amplitude: 0.2)
        var peak: Int16 = 0
        for i in stride(from: 44, to: wav.count - 1, by: 2) {
            let s = Int16(littleEndian: wav[i..<(i + 2)].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
            peak = max(peak, abs(s))
        }
        let esperado = Double(Int16.max) * 0.2
        #expect(Double(peak) > esperado * 0.9 && Double(peak) <= esperado * 1.01,
                "peak \(peak), expected ~\(Int(esperado))")
    }
}
