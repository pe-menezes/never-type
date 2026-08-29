import Foundation

/// Uma troca literal aplicada depois da transcrição.
public struct Replacement: Codable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// As duas listas que corrigem o que o modelo escreve — e são duas de
/// propósito, porque resolvem problemas diferentes.
///
/// **Termos** viram o `initial_prompt` do whisper: dica de reconhecimento, que
/// ajuda o modelo a *ouvir* a palavra. É probabilístico e não garante nada, mas
/// influencia também pontuação e formatação.
///
/// **Substituições** rodam depois, sobre o texto pronto. São determinísticas:
/// "saiu X, eu queria Y" sempre vira Y. É o que resolve o caso de uma palavra
/// que o modelo consistentemente troca por outra parecida.
///
/// Misturar as duas numa lista só seria prometer garantia onde não existe.
public final class Vocabulary {
    private let url: URL

    public private(set) var terms: [String] = []
    public private(set) var replacements: [Replacement] = []

    public init(url: URL) {
        self.url = url
        load()
    }

    // MARK: - Edição

    public func setTerms(_ value: [String]) {
        terms = value.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        save()
    }

    public func setReplacements(_ value: [Replacement]) {
        replacements = value
            .map { Replacement(from: $0.from.trimmingCharacters(in: .whitespaces),
                               to: $0.to.trimmingCharacters(in: .whitespaces)) }
            // Origem vazia casaria com tudo; destino vazio é apagar palavra, e
            // quem quer isso escreve a substituição inteira.
            .filter { !$0.from.isEmpty && !$0.to.isEmpty }
        save()
    }

    // MARK: - Uso

    /// O `initial_prompt` do whisper, ou `nil` quando não há termos.
    ///
    /// Frase com vírgulas, e não lista crua: o prompt é interpretado como texto
    /// que *precede* a fala, então ele funciona melhor parecendo linguagem.
    public var prompt: String? {
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ") + "."
    }

    /// Aplica as substituições no texto transcrito.
    ///
    /// Casa palavra inteira e ignora maiúsculas na busca, mas escreve exatamente
    /// o que foi pedido no destino — trocar "pix" por "Pix" é justamente um dos
    /// usos. Sem a fronteira de palavra, trocar "ia" por "IA" estragaria
    /// "família".
    public func apply(to text: String) -> String {
        var output = text
        for replacement in replacements {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: replacement.from) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.to))
        }
        return output
    }

    // MARK: - Disco

    private struct Stored: Codable {
        var terms: [String]
        var replacements: [Replacement]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        terms = stored.terms
        replacements = stored.replacements
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Stored(terms: terms, replacements: replacements)) else { return }
        // Atômico: escrita interrompida deixaria um JSON truncado, e a lista
        // inteira sumiria na próxima abertura.
        try? data.write(to: url, options: .atomic)
    }
}
