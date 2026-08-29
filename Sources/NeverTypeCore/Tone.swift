import Foundation

/// Generates the short tones of the audible feedback.
///
/// The system sounds (`Tink`, `Pop`, `Glass`) were designed to *be noticed* —
/// they are alerts. Here the sound is confirmation of an action the user just
/// took on purpose, so it needs to be the opposite of that.
///
/// Generating instead of choosing gives control over the two things that make a
/// sound calm or irritating: the frequency and, above all, the envelope. A tone
/// that starts and ends abruptly clicks; the gentle rise and fall below are what
/// removes the click.
public enum Tone {
    public static let sampleRate: Double = 44_100

    /// Rises and falls over 25 ms.
    ///
    /// Without it, the abrupt cut at the buffer's edge becomes an audible click —
    /// which is exactly the dry "tick" being avoided.
    private static let fade: Double = 0.025

    /// One or more notes in sequence, as a 16-bit mono WAV.
    ///
    /// Returns a WAV, not samples, because the player is `NSSound`, which accepts
    /// `Data` and needs no temporary file.
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

    /// Canonical WAV header + the samples.
    ///
    /// Hand-written because the alternative would be loading AVFoundation and a
    /// file on disk to produce a few KB of audio: 44 bytes of header plus 2 bytes
    /// per sample — ~6 KB at the default 0.07 s, ~7.5 KB and ~11.5 KB for the
    /// app's tones (see `Feedback`, in main.swift).
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
        u32(16)                                     // fmt chunk size
        u16(1)                                      // PCM, no compression
        u16(1)                                      // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * UInt32(bytesPerSample))  // bytes per second
        u16(UInt16(bytesPerSample))                 // block align
        u16(16)                                     // bits per sample

        ascii("data")
        u32(UInt32(dataSize))
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }
}
