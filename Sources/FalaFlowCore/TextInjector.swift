import AppKit
import Carbon.HIToolbox

/// Insere texto onde o cursor estiver, via área de transferência.
///
/// Colar, e não digitar caractere a caractere: `CGEvent` por caractere leva
/// dezenas de ms por letra — um parágrafo ditado levaria segundos, jogando fora
/// o ganho de latência — e quebra em campos com autocomplete, que reagem a cada
/// tecla. Colar é atômico e funciona igual em AppKit, Electron e terminal.
///
/// O preço é mexer no pasteboard da pessoa. Por isso salvar e devolver não é
/// polimento: é obrigação, e vale inclusive quando a inserção falha.
public enum TextInjector {

    public enum Outcome: Equatable {
        case inserted
        /// Campo de senha em foco: o macOS bloqueia eventos sintéticos e o ⌘V
        /// simplesmente não aconteceria. Avisar é melhor que fingir.
        case blockedBySecureInput
        case failed(String)
    }

    /// Cópia completa do pasteboard: todos os itens, todos os tipos.
    ///
    /// Guardar só a string perderia imagem, arquivo, HTML — tudo que a pessoa
    /// tivesse copiado antes de ditar.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> Snapshot {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { acc, type in
                    if let data = item.data(forType: type) { acc[type] = data }
                }
            }
            return Snapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items.map { stored in
                let item = NSPasteboardItem()
                for (type, data) in stored { item.setData(data, forType: type) }
                return item
            })
        }
    }

    /// Quanto esperar antes de devolver o pasteboard.
    ///
    /// Vários apps leem o pasteboard de forma assíncrona depois do ⌘V. Devolver
    /// rápido demais faz colar o conteúdo antigo. Generoso de propósito: o custo
    /// de esperar é invisível, o de errar é colar a coisa errada.
    public static let restoreDelay: TimeInterval = 0.6

    /// Marca que gestores de clipboard bem-comportados respeitam para não gravar
    /// o item no histórico. Sem isto, cada ditado entraria no histórico do
    /// Raycast ou do Maccy e sobreviveria à restauração.
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Geração da inserção em curso, e o retrato ainda por devolver.
    ///
    /// Sem isto a restauração era incondicional e destruía dado do usuário de
    /// duas formas, ambas reproduzidas em auditoria:
    ///
    /// 1. **Qualquer escrita no pasteboard nos 600 ms seguintes a um ditado era
    ///    revertida** — um ⌘C seu, o Universal Clipboard, um gestor de clipboard.
    /// 2. **Dois ditados em menos de 600 ms** deixavam o texto do primeiro no
    ///    lugar do conteúdo original, permanentemente: o segundo `insert`
    ///    fotografava o pasteboard já contaminado pelo primeiro.
    ///
    /// A geração faz só a restauração mais recente valer; o retrato herdado faz
    /// ela devolver o conteúdo **original**, não o intermediário; e o
    /// `changeCount` faz ela desistir se alguém escreveu no meio.
    /// Indexado pelo pasteboard: o retrato pendente pertence a um pasteboard
    /// específico, não ao processo. Em produção existe só o `.general`, mas
    /// tratar como estado global fazia dois pasteboards distintos interferirem
    /// um no outro — o que os testes paralelos expuseram na hora.
    private struct Pending {
        var generation: Int
        var snapshot: Snapshot
    }
    @MainActor private static var pending: [NSPasteboard.Name: Pending] = [:]

    @MainActor
    @discardableResult
    public static func insert(_ text: String,
                              pasteboard: NSPasteboard = .general,
                              paste: (() -> Bool)? = nil,
                              secureInput: (() -> Bool)? = nil) -> Outcome {
        guard !text.isEmpty else { return .failed("texto vazio") }

        // Entrada segura ativa: o macOS descarta eventos sintéticos, o ⌘V não
        // aconteceria e o app pareceria quebrado. Aqui a spec manda deixar o
        // texto no pasteboard — e a versão anterior retornava **antes** de
        // tocá-lo, então não deixava nada. Sem colar não há o que restaurar,
        // então o texto fica lá para a pessoa colar quando quiser.
        //
        // Atenção ao nome: `IsSecureEventInputEnabled` é flag global da sessão,
        // não "campo de senha em foco". Qualquer processo pode ligá-la, inclusive
        // em segundo plano, e há apps que ligam e esquecem de desligar.
        if (secureInput ?? IsSecureEventInputEnabled)() {
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setData(Data(), forType: concealed)
            _ = pasteboard.writeObjects([item])
            return .blockedBySecureInput
        }

        let key = pasteboard.name
        let myGeneration = (pending[key]?.generation ?? 0) + 1

        // Herda o retrato de uma restauração ainda pendente: fotografar agora
        // capturaria o texto do ditado anterior, não o conteúdo da pessoa.
        let snapshot = pending[key]?.snapshot ?? Snapshot.capture(from: pasteboard)
        pending[key] = Pending(generation: myGeneration, snapshot: snapshot)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: concealed)
        guard pasteboard.writeObjects([item]) else {
            pending[key] = nil
            return .failed("não consegui escrever na área de transferência")
        }

        let stamp = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            MainActor.assumeIsolated {
                // Uma inserção mais nova assumiu: ela devolve o retrato.
                guard pending[key]?.generation == myGeneration else { return }
                // Alguém escreveu no pasteboard depois de nós. Devolver agora
                // apagaria o que essa pessoa acabou de copiar.
                guard pasteboard.changeCount == stamp else {
                    pending[key] = nil
                    return
                }
                snapshot.restore(to: pasteboard)
                pending[key] = nil
            }
        }

        return (paste ?? postCommandV)() ? .inserted : .failed("não consegui enviar ⌘V")
    }

    /// ⌘V sintético.
    ///
    /// Postado com as flags explícitas e depois do trigger já solto, então não há
    /// modificador pendente para contaminar o evento.
    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
