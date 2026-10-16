---
tags: [state-management, permissions, staleness, system-apis, ui-refresh]
modules: [Sources/NeverType/, Sources/NeverTypeCore/]
applies_to: [services, handlers, components]
confidence: inferred
---
# Pattern: Estado do sistema é consultado, nunca guardado

<!-- vibeflow:auto:start -->
## What

Permissão, foco, conteúdo de área de transferência — nada disso é copiado para
uma variável do app. Esses estados mudam por fora, sem avisar ninguém, e uma
cópia envelhece em silêncio. Consultar é barato; mentir para o usuário não é.

## Where

- `Sources/NeverType/main.swift` — permissão de microfone, menu da bandeja
- `Sources/NeverTypeCore/HotkeyMonitor.swift` — `AXIsProcessTrusted()`
- `Sources/NeverTypeCore/TextInjector.swift` — `changeCount` do pasteboard

## The Pattern

**Permissão é propriedade computada, não flag:**

```swift
// Sources/NeverTypeCore/Permissions.swift — MicrophoneAccess.current
/// Queried from the system on every read, never kept: the person changes it
/// in System Settings without the app hearing about it
/// (`.vibeflow/patterns/estado-consultado.md`).
public static var current: MicrophoneAccess {
    MicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio))
}
```

Quem lê chama `MicrophoneAccess.current` no ponto em que precisa (o gatilho, a
abertura do menu, a abertura do app), e as duas permissões juntas saem de
`PermissionReading.current` (`StatusIcon.swift`). Uma versão anterior guardava
o estado numa flag preenchida durante o lançamento, e o menu era montado antes
disso: exibia "Microfone: faltando" com a permissão concedida e a gravação
funcionando.

**Interface se remonta ao ser aberta**, em vez de tentar acompanhar mudanças:

```swift
// Sources/NeverType/main.swift
// O menu se remonta ao ser aberto (menuNeedsUpdate), então nunca mostra
// estado velho.
menu.delegate = self
statusItem.menu = menu

// ...
func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu()
}
```

**Antes de desfazer alteração em recurso compartilhado, confira se ele ainda
está como você deixou:**

```swift
// Sources/NeverTypeCore/TextInjector.swift — insert(_:pasteboard:paste:secureInput:)
let stamp = pasteboard.changeCount
// ...
// Alguém escreveu no pasteboard depois de nós. Devolver agora
// apagaria o que essa pessoa acabou de copiar.
guard pasteboard.changeCount == stamp else {
    pending[key] = nil
    return
}
snapshot.restore(to: pasteboard)
```

## Rules

- Estado de permissão: propriedade computada consultando a API do sistema.
- Interface que mostra estado do sistema se reconstrói na hora de aparecer.
- Restauração de recurso compartilhado é condicional: só desfaz se ninguém mais
  mexeu desde então.
- Quando várias operações competem pelo mesmo recurso, uma geração decide qual
  restauração vale.
- Estado que pertence a um recurso é indexado por ele, não guardado no tipo.

## Examples from this codebase

File: `Sources/NeverTypeCore/HotkeyMonitor.swift` — `hasAccessibilityPermission`
```swift
/// A concessão de Acessibilidade. Sem ela os monitores globais não recebem
/// evento nenhum — e não avisam. O app pareceria quebrado em silêncio.
public static var hasAccessibilityPermission: Bool {
    AXIsProcessTrusted()
}
```

File: `Sources/NeverTypeCore/TextInjector.swift` — geração por recurso, em `insert`:
```swift
let key = pasteboard.name
let myGeneration = (pending[key]?.generation ?? 0) + 1
let snapshot = pending[key]?.snapshot ?? Snapshot.capture(from: pasteboard)
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **Flag de permissão preenchida no lançamento.** O menu era montado antes da
  checagem e nunca remontado: exibia "Microfone: faltando" com tudo funcionando.
- **Restauração incondicional.** Devolver o pasteboard sem conferir `changeCount`
  revertia qualquer coisa que a pessoa copiasse nos 600 ms seguintes, e dois
  ditados seguidos deixavam o texto do primeiro no lugar do conteúdo original —
  permanentemente.
