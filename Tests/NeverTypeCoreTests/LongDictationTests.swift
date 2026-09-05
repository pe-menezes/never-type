import AVFoundation
import Foundation
import Testing
@testable import NeverTypeCore

// Dictation that crosses whisper's 30 s window many times.
//
// Its own file because the gate is different from `TranscriberTests`: this one
// needs the model and a pt-BR voice for `say`, not a recording made by whoever
// cloned. And it is the slow test of the suite, ~15 s, which is the price of
// the only thing that catches this class of defect.
//
// It exists because nothing exercised more than two windows, and that is where
// the app was losing speech. On 2026-09-05 a 358.8 s dictation came back with
// 1945 characters where the same day's dictations projected ~4800, repeating
// whole sentences and degenerating into `Marcador 44. Marcador 44.` at the end.
// See `.vibeflow/hotfixes/2026-09-05-long-dictation-loses-and-repeats-speech.md`.

/// The sentences the fixture speaks, one per marker.
///
/// Everyday technical Portuguese, which is what the app transcribes. The
/// content does not matter to the assertion: the numbered marker in front of
/// each one is what gets counted.
private let markedSentences = [
    "eu abri o terminal e rodei o build de novo pra ver se o erro continuava aparecendo",
    "a gente precisa medir o tempo de resposta antes de decidir qualquer coisa sobre o modelo",
    "o teste passou na minha máquina mas quebrou no pipeline por causa da versão do compilador",
    "quando eu falo por muito tempo seguido o texto começa a repetir frases que eu já tinha dito",
    "o microfone do notebook capta bem mas o ventilador entra no áudio quando a máquina esquenta",
    "eu prefiro falar do que digitar porque o pensamento flui muito melhor dessa forma",
    "a documentação está desatualizada em pelo menos três lugares que eu encontrei hoje de manhã",
    "o modelo roda local então nenhuma informação sai da máquina em nenhum momento do processo",
    "a gente vai precisar de um pacote distribuível porque ninguém quer compilar na própria máquina",
    "eu tentei reproduzir o problema gravando um áudio bem longo e o resultado veio cortado",
    "o histórico guarda as últimas trinta transcrições e depois disso as mais antigas caem fora",
    "a permissão de acessibilidade some toda vez que o certificado de assinatura muda de lugar",
    "eu comparei os bytes do arquivo com o valor esperado em hexadecimal e bateu certinho",
    "a janela de trinta segundos é o formato interno do modelo e não dá pra mudar isso facilmente",
    "o vocabulário customizado ajuda bastante com nome de sistema interno e termo técnico em inglês",
]

/// How many markers the fixture speaks. Sixty is ~460 s.
///
/// Sixty and not twenty, because the loss is cumulative and does not separate
/// the two configurations early. Measured 2026-09-05 by cutting this same
/// fixture short and transcribing each length with the flag on and off, as a
/// percentage of the words spoken:
///
///     119 s   97.3% against 96.7%   (tied, inside the noise)
///     180 s   98.0% against 97.3%   (tied)
///     243 s   91.3% against 97.2%
///     346 s   92.7% against 97.6%
///     460 s   57.6% against 98.3%
///
/// A twenty-marker fixture is a test that passes on the defect.
private let markerCount = 60

/// The script, with each sentence announced by its number.
private func longDictationScript() -> String {
    (1...markerCount)
        .map { "Marcador número \($0). \(markedSentences[($0 - 1) % markedSentences.count])." }
        .joined(separator: " ")
}

/// pt-BR voice used to synthesize. Ships with macOS.
private let fixtureVoice = "Luciana"

/// The fixture is synthesized, not recorded.
///
/// It takes almost eight minutes of speech to separate a working build from a
/// broken one, `fixtures/` is not versioned, and a recording that long would
/// exist on exactly one machine. `say` is deterministic: three runs of the
/// broken build over this same audio returned 33 of 60 markers, the same 33
/// every time, so a threshold here is not a coin flip.
///
/// Cached under `.cache/` because synthesis costs ~35 s against ~15 s for the
/// transcription, and the audio only changes when the script above changes.
private func longDictationFixture() throws -> URL? {
    let cache = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".cache/long-dictation")
    let wav = cache.appendingPathComponent("script-\(markerCount).wav")
    let script = cache.appendingPathComponent("script-\(markerCount).txt")
    let text = longDictationScript()

    // Rebuild when the script changed: a stale WAV would measure audio that no
    // longer matches the markers being counted, and the test would fail for a
    // reason that has nothing to do with the defect.
    let cached = try? String(contentsOf: script, encoding: .utf8)
    if FileManager.default.fileExists(atPath: wav.path), cached == text { return wav }

    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let aiff = cache.appendingPathComponent("script-\(markerCount).aiff")
    try text.write(to: script, atomically: true, encoding: .utf8)

    // `say` writes AIFF at the voice's own rate; `afconvert` brings it to the
    // 16 kHz mono the recorder produces and the model consumes.
    guard run("/usr/bin/say", ["-v", fixtureVoice, "-r", "175", "-o", aiff.path, "-f", script.path]),
          run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
    else {
        try? FileManager.default.removeItem(at: script)
        return nil
    }
    try? FileManager.default.removeItem(at: aiff)
    return wav
}

/// Runs a tool and answers whether it succeeded. Output goes nowhere on
/// purpose: `say` is chatty and neither command says anything useful here.
private func run(_ tool: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

/// Whether the pt-BR voice is installed.
///
/// Checked instead of assumed: without it `say` falls back to the system voice
/// and synthesizes Portuguese text in English, which the model would transcribe
/// into something the marker count rejects. The test would go red pointing at
/// the wrong thing.
private func portugueseVoiceInstalled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", "?"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).contains(fixtureVoice)
}

private func longDictationTestsRunnable() -> Bool {
    FileManager.default.fileExists(atPath: ModelStore.modelURL.path) && portugueseVoiceInstalled()
}

/// Case-folded and without accents, so `número` and `numero` compare equal.
private func fold(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                 locale: Locale(identifier: "pt_BR"))
}

/// The markers the model did not return.
///
/// Both spellings are accepted: whisper writes some of them as digits and some
/// as words, and which one it picks is not what this test is about. The `\b`
/// matters, otherwise marker 1 would be found inside marker 15.
private func missingMarkers(in text: String) throws -> [Int] {
    let spell = NumberFormatter()
    spell.numberStyle = .spellOut
    spell.locale = Locale(identifier: "pt_BR")
    let haystack = fold(text)

    return try (1...markerCount).filter { number in
        let written = fold(spell.string(from: NSNumber(value: number)) ?? "")
        let pattern = try Regex("marcador numero (\(number)|\(written))\\b")
        return haystack.firstMatch(of: pattern) == nil
    }
}

/// The longest run of identical consecutive sentences.
///
/// This is the second face of the defect and it needs its own reading: a
/// decoder stuck in a loop inflates the character count while losing speech, so
/// length alone reports the opposite of what happened.
private func longestRepeatedRun(in text: String) -> (length: Int, sentence: String) {
    let sentences = text
        .split(whereSeparator: { ".!?".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.count > 8 }
    var longest = (length: 1, sentence: "")
    var current = 1
    for (previous, sentence) in zip(sentences, sentences.dropFirst()) {
        current = previous == sentence ? current + 1 : 1
        if current > longest.length { longest = (current, sentence) }
    }
    return longest
}

/// Needs the model installed and the pt-BR voice; both live outside the repo.
@Suite("Long dictation", .enabled(if: longDictationTestsRunnable()))
struct LongDictationTests {

    /// One transcription, two assertions.
    ///
    /// They are two distinct properties and would normally be two tests. They
    /// share one here because the transcription is ~15 s and running it twice
    /// buys nothing: both readings come off the same text.
    @Test("speech above 30 s survives the window boundaries whole")
    func longDictationKeepsEveryWindow() throws {
        let fixture = try #require(try longDictationFixture(),
                                   "could not synthesize the fixture with `say`")
        let samples = try readWavSamples(fixture)
        #expect(samples.count > 400 * 16_000,
                "the fixture needs to cross several 30 s windows, it has \(samples.count / 16_000) s")

        let transcriber = try Transcriber()
        let text = try transcriber.transcribe(samples)

        // Six of sixty, a wide margin on both sides of the defect: the broken
        // build lost 27 and the fixed one lost none.
        let missing = try missingMarkers(in: text)
        #expect(missing.count <= 6, """
            \(missing.count) of \(markerCount) markers did not come back: \(missing).
            Whole windows of speech are being dropped between whisper's 30 s steps.
            """)

        // The broken build stacked ten identical sentences in a row here.
        let repeated = longestRepeatedRun(in: text)
        #expect(repeated.length <= 2, """
            the sentence "\(repeated.sentence)" came back \(repeated.length) times in a row.
            The decoder is looping instead of advancing through the audio.
            """)

        // Asking whisper for timestamps must not put them in what gets typed.
        // The fix turns them on, and this is the property that says the person
        // dictating never sees them.
        #expect(!text.contains("-->") && !text.contains("<|"),
                "timestamps leaked into the text that gets inserted: \(text.prefix(200))")
    }
}


// The same defect, measured on a real recording instead of a synthesized one.
//
// It earns its place because real speech fails harder and fails differently.
// Measured 2026-09-05 over 404 s of a recorded voice message: the broken build
// kept 19% of the words against 58% on the synthesized fixture of similar
// length, and it did it without repeating a single sentence. Pauses, breathing
// and room noise push a window past the confidence floor, and the window is
// dropped in silence. That failure leaves no trace in the text, which is worse
// than the loop: reading the result does not reveal it.

/// Shortest recording this check accepts, in seconds.
///
/// Four minutes. The synthesized fixture needed almost eight to separate the
/// two builds, and real speech diverges at the first window boundary, ~13 s
/// into the 404 s recording measured.
private let minimumRecordedSeconds: Double = 240

/// Seconds of audio, read from the file header instead of the samples.
///
/// The gate runs before any test and should not pull every fixture off disk to
/// answer how long it is.
private func wavSeconds(_ url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let rate = file.fileFormat.sampleRate
    guard rate > 0 else { return nil }
    return Double(file.length) / rate
}

/// The first recorded fixture above four minutes, if there is one.
///
/// Separate from `firstFixture()`, which takes whatever comes first
/// alphabetically: this check is about length, and the short clips the bench
/// asks for would pass it without exercising anything.
private func longRecordedFixture() -> URL? {
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("fixtures")
    let wavs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "wav" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return wavs?.first { (wavSeconds($0) ?? 0) >= minimumRecordedSeconds }
}

private func recordedLongDictationRunnable() -> Bool {
    FileManager.default.fileExists(atPath: ModelStore.modelURL.path) && longRecordedFixture() != nil
}

/// Needs the model and a recording above four minutes in `fixtures/`. Neither is
/// versioned, so a clean clone skips this suite and runs the synthesized one.
@Suite("Long dictation, recorded voice", .enabled(if: recordedLongDictationRunnable()))
struct RecordedLongDictationTests {

    /// Nothing about the recording's content is read, compared or reported.
    ///
    /// The fixture is somebody's real speech, and there is no transcript of it
    /// to compare against anyway. Both readings below are shape, not content:
    /// how much text came back per second of audio, and whether the decoder
    /// stalled. The failure messages carry numbers only, so a red run does not
    /// print the recording into the test log.
    @Test("a recorded dictation above four minutes comes back whole")
    func recordedLongDictationKeepsItsDensity() throws {
        let fixture = try #require(longRecordedFixture())
        let seconds = try #require(wavSeconds(fixture))
        let samples = try readWavSamples(fixture)

        let transcriber = try Transcriber()
        let text = try transcriber.transcribe(samples)

        // Eight characters per second, with room on both sides. Measured
        // 2026-09-05 on a 404 s recording: 2.7 with `no_timestamps` on and 15.8
        // with it off. Continuous Portuguese sits near 15, and a recording that
        // is mostly silence would sit under the floor for a reason that is not
        // this defect, which is why `fixtures/README.md` asks for continuous
        // speech.
        let density = Double(text.count) / seconds
        #expect(density >= 8, """
            \(String(format: "%.1f", density)) characters per second over \(Int(seconds)) s of audio.
            Windows of speech are being dropped, and on a real recording they are dropped silently.
            """)

        let repeated = longestRepeatedRun(in: text)
        #expect(repeated.length <= 2, """
            a sentence came back \(repeated.length) times in a row.
            The decoder is looping instead of advancing through the audio.
            """)
    }
}
