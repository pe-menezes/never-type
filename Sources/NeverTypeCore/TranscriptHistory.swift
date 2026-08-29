import Foundation

/// Uma transcrição guardada.
public struct TranscriptEntry: Codable, Equatable, Sendable {
    public let text: String
    public let date: Date

    public init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

/// O histórico das últimas transcrições.
///
/// Antes existia só a última, num `ultima-transcricao.txt`, e ela servia de rede
/// para quando a colagem não chegava em lugar nenhum. Um ditado depois do outro
/// apagava o anterior.
///
/// Isto é registro do que a pessoa falou, então três decisões são deliberadas e
/// não padrões herdados:
///
/// - **Teto de 30.** Não é "guardar tudo": passa de 30, a mais antiga cai.
/// - **Fica em texto claro no disco**, dentro do Application Support do próprio
///   app. Criptografar exigiria uma chave, e a chave moraria ao lado do arquivo
///   na mesma máquina — cerimônia sem ganho. Quem tem acesso local à conta já lê
///   o `last.wav`, que é a gravação inteira.
/// - **Dá para apagar**, pelo menu, sem sair procurando arquivo.
public final class TranscriptHistory {
    /// Quantas entradas sobrevivem. Acima disto, a mais antiga sai.
    public static let limit = 30

    private let url: URL
    /// Mais recente primeiro: é a ordem em que o menu mostra e em que "a última"
    /// é lida.
    public private(set) var entries: [TranscriptEntry] = []

    public init(url: URL) {
        self.url = url
        load()
    }

    public var last: TranscriptEntry? { entries.first }

    /// Guarda uma transcrição nova. Texto vazio não entra.
    @discardableResult
    public func add(_ text: String, at date: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        entries.insert(TranscriptEntry(text: trimmed, date: date), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
        return true
    }

    public func clear() {
        entries.removeAll()
        // Some com o arquivo, e não só com o conteúdo: um arquivo vazio com
        // nome de histórico ainda diz que existiu histórico.
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Disco

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        // Histórico ilegível não pode derrubar o app nem apagar o que vier
        // depois: começa vazio e a primeira gravação sobrescreve.
        guard let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else { return }
        entries = Array(decoded.prefix(Self.limit))
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        // Atômico: uma escrita interrompida no meio deixaria um JSON truncado, e
        // o histórico inteiro seria descartado na próxima abertura.
        try? data.write(to: url, options: .atomic)
    }
}
