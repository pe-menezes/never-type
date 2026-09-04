# Prompt pack: o título do Hands-free nomeia a segunda tecla

> Gerado via /vibeflow:quick em 2026-09-04. Spec efêmera, sem arquivo em `.vibeflow/specs/`.

You are only seeing this prompt; there is no context outside it.

## Objetivo e Definition of Done

**Objetivo.** O item Hands-free do menu da barra passa a nomear a segunda tecla
quando ela existe: `Hands-free: double tap or Right ⌥`. Sem tecla, continua
`Hands-free: double tap`. Com o modo desligado, continua `Hands-free: off`,
mesmo com uma tecla guardada.

**Definition of Done.**

1. `swift test` verde, com `MenuLayoutTests` cobrindo os três casos em
   `MenuLayout.rows(for:)`: sem tecla, `.handsFree(enabled: true, key: nil)`;
   com tecla, `.handsFree(enabled: true, key: "Right ⌥")`; modo desligado com
   tecla guardada, `.handsFree(enabled: false, key: nil)`. Os testes que já
   existem continuam compilando sem edição.
2. De olho: com uma tecla de mãos-livres escolhida, o menu diz `Hands-free:
   double tap or Right ⌥`; **Remove hands-free key** devolve `Hands-free:
   double tap`; desmarcar **Hands-free** mostra `Hands-free: off`.
3. `docs/reference.md` deixa de dizer que o título ignora a segunda tecla.
4. Craftsmanship: nenhuma linha adicionada com travessão ou aspas curvas; o
   rótulo é lido de `monitor.handsFreeTrigger` na montagem do menu, sem cópia
   em variável; o texto da frase continua no AppKit que a desenha, e
   `MenuLayout` só carrega o dado.

## Anti-escopo

- **Não** muda os itens do submenu Hands-free nem o de Hotkey.
- **Não** muda o título `Hotkey: <tecla>`.
- **Não** guarda o rótulo em variável do menu: consulta na hora, como
  `triggerLabel`.
- **Não** muda `HotkeyMonitor`, `TriggerCapture` nem o painel.

## Orçamento

Quatro arquivos:

- `Sources/NeverTypeCore/MenuLayout.swift`
- `Sources/NeverType/main.swift`
- `Tests/NeverTypeCoreTests/MenuLayoutTests.swift`
- `docs/reference.md`

## Padrões a seguir

**`estado-consultado.md`**: o menu se remonta ao abrir e lê o estado nesse
momento. O `Conditions` é a fotografia dessa leitura:

```swift
// Sources/NeverType/main.swift
let conditions = MenuLayout.Conditions(
    microphoneAuthorized: micAuthorized,
    accessibilityAuthorized: HotkeyMonitor.hasAccessibilityPermission,
    showsDiagnostics: NSEvent.modifierFlags.contains(.option),
    historyCount: history.entries.count,
    triggerLabel: monitor.trigger.label,
    handsFreeEnabled: monitor.handsFreeEnabled,
    ...
```

**`nucleo-testavel.md`**: `MenuLayout` decide "quais linhas, dado o estado"; a
frase que a pessoa lê é montada pelo AppKit. O `Row` carrega o dado que o título
precisa, como `hotkey(trigger:)` já faz:

```swift
// Sources/NeverTypeCore/MenuLayout.swift
/// Carries the chosen key, because the title is where the gesture is
/// taught: a menu you have to open to learn the menu exists reaches
/// nobody who has not opened it.
case hotkey(trigger: String)
case handsFree(enabled: Bool)
```

**`conventions.md`**: comentário explica o porquê; sem travessão nem aspas
curvas em prosa; doc comment em todo `public`.

## Onde trabalhar

`Sources/NeverTypeCore/MenuLayout.swift`: `Conditions` ganha
`handsFreeKeyLabel: String?`, com valor padrão `nil` no `init` para as chamadas
existentes seguirem compilando. `Row.handsFree` ganha `key: String? = nil`
(valor padrão em associated value, para os `.handsFree(enabled: true)` dos
testes atuais continuarem valendo). Em `rows(for:)`:

```swift
rows.append(.handsFree(enabled: conditions.handsFreeEnabled,
                       key: conditions.handsFreeEnabled ? conditions.handsFreeKeyLabel : nil))
```

Com o modo desligado a tecla não vai para a linha: o título diz `off`, e a
tecla continua guardada só no monitor.

`Sources/NeverType/main.swift`, na montagem de `Conditions`:
`handsFreeKeyLabel: monitor.handsFreeTrigger?.label`. No `row(for:)`:

```swift
case .handsFree(let enabled, let key):
    let title = enabled
        ? key.map { "Hands-free: double tap or \($0)" } ?? "Hands-free: double tap"
        : "Hands-free: off"
```

`Tests/NeverTypeCoreTests/MenuLayoutTests.swift`: o helper `conditions(...)`
ganha `handsFreeKey: String? = nil`; um teste novo, "the hands-free key reaches
the item that names it", com os três casos do DoD 1.

`docs/reference.md`, item **Hands-free: double tap**: a frase "The title says
`double tap` whether or not a second key is set" vira a descrição do título com
a tecla.

## Direção

Mesma forma de `hotkey(trigger:)`: o dado viaja no `Row`, o texto nasce no
AppKit. Nada de guardar o rótulo; a montagem do menu já lê tudo do monitor a
cada abertura.

## Como rodar e testar

```bash
swift build && swift test
```

Depois, `bash scripts/build-app.sh && bash scripts/install.sh` e o DoD 2 de
olho.
