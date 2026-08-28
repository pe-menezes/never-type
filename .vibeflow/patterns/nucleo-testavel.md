---
tags: [testability, dependency-injection, module-boundaries, swiftpm, system-apis]
modules: [Sources/FalaFlowCore/, Sources/FalaFlow/, Tests/FalaFlowCoreTests/]
applies_to: [services, models, tests]
confidence: inferred
---
# Pattern: Núcleo testável separado da casca

<!-- vibeflow:auto:start -->
## What

A lógica vive em `FalaFlowCore`, uma biblioteca; o executável `FalaFlow` é só a
casca que monta a menu bar e liga os pedaços. E toda chamada de sistema que
impediria um teste — colar no cursor, ler uma flag global, abrir o microfone — é
recebida como parâmetro com valor padrão, para o teste poder trocá-la.

## Where

- `Sources/FalaFlowCore/` — tudo que tem teste
- `Sources/FalaFlow/` — `NSApplication`, menu, painel flutuante; sem lógica
- `Tests/FalaFlowCoreTests/` — importa `FalaFlowCore`, nunca o executável

## The Pattern

A divisão não é estética: **um alvo executável do SwiftPM não é importável por um
alvo de teste.** Sem a biblioteca, nada seria testável.

```swift
// Package.swift
.systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
.target(name: "FalaFlowCore", dependencies: ["CWhisper"], linkerSettings: [...]),
.executableTarget(name: "FalaFlow", dependencies: ["FalaFlowCore"]),
.testTarget(name: "FalaFlowCoreTests", dependencies: ["FalaFlowCore"]),
```

Dentro do núcleo, o que depende do sistema entra por parâmetro:

```swift
// Sources/FalaFlowCore/TextInjector.swift:88
public static func insert(_ text: String,
                          pasteboard: NSPasteboard = .general,
                          paste: (() -> Bool)? = nil,
                          secureInput: (() -> Bool)? = nil) -> Outcome {
    ...
    if (secureInput ?? IsSecureEventInputEnabled)() { ... }
    ...
    return (paste ?? postCommandV)() ? .inserted : .failed("não consegui enviar ⌘V")
}
```

Em produção os padrões valem e ninguém precisa saber que existem. No teste,
ambos os ramos ficam determinísticos sem ligar entrada segura para a sessão
inteira nem postar teclas de verdade.

Quando o obstáculo não é uma chamada e sim o custo, a **regra** é separada da
leitura de disco:

```swift
// Sources/FalaFlowCore/Transcriber.swift:44
/// A regra em si, separada da leitura de disco.
///
/// Assim dá para testar o piso de tamanho sem escrever 50 MB a cada execução
/// da suíte.
public static func isValid(magic: Data, size: Int) -> Bool {
    guard size >= minimumBytes else { return false }
    guard magic.count == 4 else { return false }
    return magic.map { String(format: "%02x", $0) }.joined() == "6c6d6767"
}
```

## Rules

- Lógica nova entra em `FalaFlowCore`. `Sources/FalaFlow/` só orquestra.
- Chamada de sistema que impeça teste vira parâmetro com padrão — nunca uma
  variável global de configuração nem um `#if DEBUG`.
- Regra pura e leitura de I/O são funções diferentes, com a pura sendo pública.
- O tipo que grava arquivo é separado do que fala com o hardware: `RecordingSink`
  cuida do WAV e é testável; `AudioRecorder` liga o `AVAudioEngine` e não é.
- Testes usam swift-testing (`import Testing`), **não XCTest** — o XCTest só
  existe com o Xcode completo, e este projeto compila com Command Line Tools.

## Examples from this codebase

File: `Sources/FalaFlowCore/AudioRecorder.swift:155`
```swift
/// Escreve o WAV: conversão, dreno e descarte.
///
/// Separado do `AudioRecorder` de propósito. A parte que decide se o arquivo
/// sobrevive ou é apagado é exatamente a que o DoD manda garantir, e ela não
/// precisa de microfone para ser exercitada. Antes só dava para testá-la falando.
public final class RecordingSink {
```

File: `Tests/FalaFlowCoreTests/TextInjectorTests.swift`
```swift
let outcome = TextInjector.insert("texto ditado", pasteboard: pb,
                                  paste: { pasted = true; return true },
                                  secureInput: { true })
#expect(outcome == .blockedBySecureInput)
#expect(!pasted, "com entrada segura não se tenta colar")
```

File: `Tests/FalaFlowCoreTests/TextInjectorTests.swift` — o pasteboard também é
injetado, e é sempre um nomeado próprio:
```swift
private func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("com.falaflow.tests.\(UUID().uuidString)"))
}
```
<!-- vibeflow:auto:end -->

## Rationale

Cada uma dessas separações nasceu de um defeito real, não de gosto:

- `RecordingSink` saiu do `AudioRecorder` porque a auditoria da Parte 2 apontou
  que `start/stop/cancel` nunca era exercitado — o comportamento que o DoD manda
  garantir (cancelar apaga o arquivo) só dava para testar falando no microfone.
- `secureInput` virou parâmetro porque o teste do ramo dependia de ligar entrada
  segura para a sessão inteira.
- `isValid(magic:size:)` foi extraído porque a alternativa era escrever 50 MB em
  disco a cada execução da suíte.

## Anti-patterns

- **Estado estático global no núcleo.** `TextInjector.pending` começou como duas
  variáveis estáticas do processo e fazia dois pasteboards distintos
  interferirem um no outro — os testes paralelos expuseram na hora. Hoje é
  indexado por `NSPasteboard.Name`. Estado que pertence a um recurso é indexado
  por ele, não guardado no tipo.
