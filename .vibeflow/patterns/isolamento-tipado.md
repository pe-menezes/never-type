---
tags: [concurrency, swift6, main-actor, actors, thread-safety]
modules: [Sources/FalaFlowCore/, Sources/FalaFlow/]
applies_to: [services, handlers, models]
confidence: inferred
---
# Pattern: Isolamento declarado no tipo, não afirmado em runtime

<!-- vibeflow:auto:start -->
## What

O contrato de thread de cada tipo é expresso no tipo — `@MainActor`, `actor`, ou
uma fila serial que é dona do estado. `MainActor.assumeIsolated` só aparece onde
uma API do sistema documenta a entrega na main thread **e** a ordem dos eventos
importa mais que a pureza.

## Where

- `Sources/FalaFlowCore/HotkeyMonitor.swift` — `@MainActor`, e `onEvent` também
- `Sources/FalaFlow/main.swift` — `actor TranscriptionService`, `@MainActor AppDelegate`
- `Sources/FalaFlowCore/AudioRecorder.swift` — fila serial dona do estado

## The Pattern

**Ator quando a serialização precisa ser garantida pelo compilador.** O contexto
do whisper.cpp é de uso serial e mora dentro de um ator:

```swift
// Sources/FalaFlow/main.swift:20
/// É um `actor` e não uma fila serial de propósito: o contexto do whisper.cpp é
/// de uso serial, e um ator faz o compilador garantir isso. Fila serial
/// dependeria de eu lembrar de sempre despachar por ela.
actor TranscriptionService {
```

**`@MainActor` quando o tipo só existe na main thread**, com o contrato indo até
o callback:

```swift
// Sources/FalaFlowCore/HotkeyMonitor.swift:11
/// Vive na main actor. Os monitores do `NSEvent` são API do AppKit ligada ao
/// run loop principal, e o tipo passa a dizer isso em vez de deixar implícito.
@MainActor
public final class HotkeyMonitor {
    public var onEvent: (@MainActor (Event) -> Void)?
```

**Fila serial quando o estado é tocado por uma thread de tempo real**, com
barreira no encerramento:

```swift
// Sources/FalaFlowCore/AudioRecorder.swift
/// O tap roda na thread de áudio em tempo real e o encerramento roda na main.
/// Antes, os dois tocavam o mesmo arquivo e o mesmo conversor sem
/// sincronização — e o compilador não acusava, porque `AVAudioNodeTapBlock`
/// não é marcado como `Sendable`.
private let io = DispatchQueue(label: "com.falaflow.audio-io")
```

## Rules

- Salto para a main actor a partir de contexto sem contrato documentado usa
  `Task { @MainActor in }` — verificado pelo compilador, não afirmado.
- `MainActor.assumeIsolated` só onde a API documenta entrega na main thread
  **e** um salto assíncrono poderia reordenar eventos. Sempre com comentário
  explicando as duas razões.
- Estado tocado por thread de tempo real pertence a uma fila serial; o callback
  de tempo real só copia e despacha.
- `stop()` de algo assíncrono usa `io.sync` como barreira antes de fechar
  recurso: `removeTap` não garante ausência de callback em voo.
- Exclusão mútua entre processos usa primitiva atômica (`flock`), nunca
  consultar-e-decidir.

## Examples from this codebase

File: `Sources/FalaFlowCore/HotkeyMonitor.swift` — a exceção, justificada:
```swift
// `assumeIsolated`, e não `Task { @MainActor in }`, de propósito.
//
// O AppKit entrega estes eventos na main thread — os monitores são
// instalados no run loop principal. E aqui a ordem importa mais que a
// pureza: um salto assíncrono poderia processar o `keyDown` depois do
// release, transformando um ditado válido em cancelamento.
MainActor.assumeIsolated { self?.handle(event) }
```

File: `Sources/FalaFlow/main.swift` — exclusão entre processos, atômica:
```swift
guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
    close(fd)
    return false
}
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **`MainActor.assumeIsolated` em callback de API de sistema sem contrato.** O
  callback do TCC chega em fila de background; a afirmação derrubou o processo
  com `EXC_BREAKPOINT` duas vezes. Pior: a segunda correção também falhou,
  porque **closures escritas dentro de um método `@MainActor` herdam esse
  isolamento por inferência** — a checagem estoura na closure externa, antes de
  chegar no corpo. A saída foi usar a API assíncrona, que não tem closure.
- **`NSRunningApplication` para exclusão de instância.** Consultar e decidir são
  dois passos, e o registro no LaunchServices é assíncrono: dois lançamentos
  simultâneos passavam ambos, 3 de 3.
- **`deinit { stop() }` em tipo `@MainActor`.** `deinit` é `nonisolated` e não
  pode tocar estado da main actor. Quem cria, encerra.
