---
tags: [user-data, pasteboard, reversibility, privacy, side-effects]
modules: [Sources/NeverTypeCore/, Sources/NeverType/]
applies_to: [services, handlers]
confidence: inferred
---
# Pattern: Estado do usuário que se toca, se devolve

<!-- vibeflow:auto:start -->
## What

Este app precisa mexer em coisas que são da pessoa — a área de transferência, o
microfone, o teclado. Toda alteração tem devolução garantida, inclusive no
caminho de erro, e nada do que a pessoa disse é perdido nem duplicado em lugar
que ela não escolheu.

## Where

- `Sources/NeverTypeCore/TextInjector.swift` — área de transferência
- `Sources/NeverTypeCore/AudioRecorder.swift` — microfone
- `Sources/NeverType/main.swift` — última transcrição

## The Pattern

**A cópia é completa, não só a parte que interessa:**

```swift
// Sources/NeverTypeCore/TextInjector.swift:23
/// Cópia completa do pasteboard: todos os itens, todos os tipos.
///
/// Guardar só a string perderia imagem, arquivo, HTML — tudo que a pessoa
/// tivesse copiado antes de ditar.
struct Snapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
```

**O que a pessoa ditou não vaza para onde ela não pediu:**

```swift
/// Marca que gestores de clipboard bem-comportados respeitam para não gravar
/// o item no histórico. Sem isto, cada ditado entraria no histórico do
/// Raycast ou do Maccy e sobreviveria à restauração.
static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
```

**O recurso é liberado quando não está em uso:**

```swift
// Sources/NeverTypeCore/AudioRecorder.swift
// O motor nasce e morre com cada ditado, em vez de viver junto com o app.
// Um AVAudioEngine parado mas vivo mantém o nó de entrada configurado, e o
// macOS continua contando o app como usuário do microfone — o indicador
// laranja da menu bar fica aceso o tempo todo. Num app cujo argumento é
// privacidade, isso é inaceitável mesmo sendo só um indicador.
private var engine: AVAudioEngine?
```

E o caminho de erro também libera:

```swift
var started = false
defer { if !started { self.engine?.reset(); self.engine = nil } }
```

## Rules

- Alteração em recurso do usuário tem devolução no caminho de sucesso **e** no de
  erro.
- A cópia guarda todos os tipos, não só o que o app entende.
- Conteúdo ditado é marcado como oculto para gestores de clipboard.
- Recurso de privacidade (microfone, câmera) é adquirido no uso e liberado
  imediatamente depois — inclusive quando a aquisição falha no meio.
- Nada que a pessoa falou é descartado sem que exista outro caminho até ele.

## Examples from this codebase

File: `Sources/NeverType/main.swift` — a saída para uma contradição da spec:
```swift
/// Resolve uma tensão da spec: ela manda devolver o pasteboard depois de
/// colar (educado) e também manda não perder a transcrição se não houver
/// onde colar. As duas juntas se contradizem — devolver apaga o texto. E não
/// dá para saber se a colagem chegou em algum lugar sem consultar a API de
/// Acessibilidade, que está no anti-escopo.
///
/// Então: devolve o pasteboard sempre, e o texto continua alcançável por
/// aqui. Nada se perde, e o clipboard de ninguém é sequestrado.
/// Não é mais uma variável: a última é a primeira do histórico, e ter as
/// duas coisas criaria duas fontes de verdade para o mesmo texto.
private var lastTranscript: String? { history.last?.text }
```

O que fica em disco está listado no doc de `lastRecordingURL()` (`main.swift`) e
no README: `historico.json`, `last.wav`, `nevertype.log` (sem texto desde
29/08/2026) e `vocabulario.json`. "Limpar histórico" apaga o JSON **e** o WAV.

File: `Sources/NeverTypeCore/TextInjector.swift` — sem colar não há o que
restaurar, então o texto fica:
```swift
if (secureInput ?? IsSecureEventInputEnabled)() {
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setData(Data(), forType: concealed)
    _ = pasteboard.writeObjects([item])
    return .blockedBySecureInput
}
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **Motor de áudio vivo entre ditados.** Mantinha o indicador de microfone do
  macOS aceso o tempo todo.
- **Restauração incondicional e agendada.** Ver `estado-consultado.md`: destruía
  o que a pessoa copiava nos 600 ms seguintes.
- **`clearContents()` sem restauração** em `copyLastTranscript` e nos itens do
  histórico — aceito por ser ação explícita do usuário, mas é a única escrita no
  pasteboard sem devolução, e vai sem `ConcealedType`: entra no histórico de
  qualquer gestor de clipboard (declarado no README desde 29/08/2026).
- **Log com o texto da transcrição.** `nevertype.log` guardou o texto de cada
  ditado da sessão até 29/08/2026, fora de "Limpar histórico" e de qualquer doc.
  Hoje a linha é `transcribed in N ms: M chars`.
