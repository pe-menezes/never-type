# Spec: Gatilho por captura, parte 1: `Trigger` generalizado e botão do mouse

> Gerado via /vibeflow:gen-spec em 2026-09-01
> A partir de `.vibeflow/prds/gatilho-por-captura.md`
> Parte 1 de 4. O PRD inteiro não cabe em 4 arquivos nem em 7 checks; o corte
> segue a ordem que ele próprio sugere.

## Objetivo

O gatilho passa a poder ser qualquer modificador dos dois lados, a tecla Fn ou
um botão extra do mouse, com o gesto de hoje (segurar, soltar, duplo toque, Esc)
e sem perder a escolha que já está guardada em disco.

## Contexto

`HotkeyMonitor.Trigger` é hoje `keyCode` + `deviceMask` + `label`, com três
valores estáticos (`rightCommand`, `rightOption`, `rightControl`) e a lista
`all`. O `id` é o keyCode em texto, e é o que está em `UserDefaults` sob a chave
`trigger` na máquina de quem já escolheu. `HotkeyMonitor.handle` filtra
`.flagsChanged` pelo keyCode e lê o lado pela máscara; os monitores escutam
`[.flagsChanged, .keyDown]`.

Esta parte não tem interface nova. Ela abre a fronteira que o PRD descreve, os
nove modificadores e os botões do mouse, e a torna verificável por hardware
antes de existir painel: com `defaults write com.nevertype.app trigger mouse:3`,
o app relançado tem que ditar com o botão do meio. O PRD pede que Fn e as
máscaras esquerdas sejam confirmados apertando as teclas, e é aqui que isso
acontece, porque é aqui que a hipótese custa menos se cair.

As duas suítes do gatilho vivem em `AudioRecorderTests.swift` (backlog H5). A
suíte "Hotkey trigger" precisa mudar de qualquer jeito com a API nova, então as
duas mudam de arquivo de uma vez.

## Definition of Done

1. **`swift test` verde, com `Tests/NeverTypeCoreTests/HotkeyMonitorTests.swift`
   novo** contendo as suítes "Hotkey trigger" e "Hands-free latch", movidas de
   `AudioRecorderTests.swift`, que fica com as três de áudio
   (`grep -c "@Suite" Tests/NeverTypeCoreTests/AudioRecorderTests.swift`
   responde `3`). A contagem total de testes não cai.

2. **Testes novos na suíte "Hotkey trigger"**, cada um com seu `@Test`:
   - "every known modifier round-trips through its identifier": os nove de
     `Trigger.modifiers`, ida e volta por `id` e `named`;
   - "a bare keyCode still resolves to the same key": `named("54")`,
     `named("61")` e `named("62")` devolvem `.rightCommand`, `.rightOption` e
     `.rightControl`, o formato que está em disco desde 29/08;
   - "left and right of the same key differ in mask and in label";
   - "mouse identifiers round-trip and the two main buttons resolve to nothing":
     `mouseButton(3)?.id == "mouse:3"`, `named("mouse:3")?.label == "Mouse
     button 3"`, `mouseButton(1)`, `mouseButton(2)` e `named("mouse:2")` nil;
   - "Caps Lock and a regular key resolve to nothing": `named("57")` e
     `named("0")` nil;
   - "menu choices are the three quick picks, plus the current trigger when it
     is off the list": `menuChoices(current: .rightOption)` são as três;
     `menuChoices(current: .leftControl)` são as três e `.leftControl` por
     último.

3. **Botão do mouse dita de ponta a ponta.** Com o app instalado:
   `defaults write com.nevertype.app trigger mouse:3`, relançar, e o log diz
   `ready. trigger: Mouse button 3`. Segurar o botão do meio, falar, soltar: o
   texto cai no app que estava na frente. Dois cliques travam, um clique
   transcreve, Esc descarta. Com mouse de botão 4, o mesmo com `mouse:4`.

4. **Fn confirmado no teclado.** `defaults write com.nevertype.app trigger 63`,
   "Pressionar a tecla 🌐 para" em "Não Fazer Nada", relançar: o log diz
   `ready. trigger: Fn` e segurar Fn dita. Se não ditar, Fn sai de
   `Trigger.modifiers` nesta mesma parte, com o comentário dizendo o que foi
   observado, e o PRD ganha a nota. O que reprova é Fn na tabela sem a rodada
   no hardware.

5. **Lado confirmado nas máscaras esquerdas.**
   `defaults write com.nevertype.app trigger 59` (⌃ esquerdo) dita, e ⌃ direito
   não inicia nada com ele escolhido. Mesma rodada com `55` (⌘ esquerdo), só
   para confirmar a máscara: a parte 2 é quem recusa essa tecla. A tabela de
   máscaras desta spec é hipótese até isso rodar.

6. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md` no
   diff: sem `!` de desempacotamento, sem `assumeIsolated` novo (os dois de
   `start()` continuam sendo os únicos), sem XCTest, sem chamada de rede, e sem
   travessão nem aspas curvas em linha adicionada
   (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio). Todo `public` novo com doc
   comment dizendo o porquê.

## Escopo

- `Sources/NeverTypeCore/HotkeyMonitor.swift`: `Trigger` com `Source`, a tabela
  `modifiers`, `mouseButton(_:)`, `id` e `named` nos dois formatos,
  `menuChoices(current:)`, os eventos de mouse em `start()` e em `handle`.
- `Sources/NeverType/main.swift`: as três comparações por `keyCode` viram
  comparação de valor (`chooseTrigger`, `hotkeyMenu`, o `didSet`), e
  `hotkeyMenu()` passa a listar `menuChoices(current:)`.
- `Tests/NeverTypeCoreTests/HotkeyMonitorTests.swift` (novo).
- `Tests/NeverTypeCoreTests/AudioRecorderTests.swift`: só a saída das duas
  suítes.

Quatro arquivos. No orçamento de `index.md`.

## Anti-escopo

- **Não** há painel, item de menu novo nem texto de recusa: parte 2.
- **Não** há segundo gatilho: parte 3.
- **Não** muda documentação: parte 4. A janela em que o README diz "três
  teclas" e o app aceita mais é aceita, porque sem painel ninguém chega às
  outras sem `defaults write`.
- **Não** `CGEventTap`, **não** dependência SPM, **não** clique principal ou
  secundário, **não** Caps Lock.
- **Não** muda o `Latch`. Mouse entra pelos `.down` e `.up` que já existem, e
  tecla comum durante o hold do botão continua cancelando (decisão do PRD).
- **Não** muda o padrão (⌘ direito) nem as três de `all`.

## Decisões técnicas

### 1. `Trigger` continua struct, e ganha uma origem

```swift
public struct Trigger: Sendable, Equatable, Hashable {
    public enum Source: Sendable, Equatable, Hashable {
        /// Modifier key. The keyCode names the key; the mask names the side,
        /// because `.command` is set by either ⌘.
        case modifier(keyCode: UInt16, deviceMask: UInt)
        /// Numbered as people count them: 3 is the middle button. `NSEvent`
        /// counts from zero, and the conversion lives in one place, `handle`.
        case mouseButton(Int)
    }
    public let source: Source
    public let label: String
}
```

Struct, porque `rightCommand`, `rightOption` e `rightControl` seguem sendo
valores nomeados com o rótulo ao lado, e o resto do app os usa assim. O rótulo é
derivado na construção (tabela para tecla, `"Mouse button \(n)"` para mouse) e
nunca vai para o disco, pelo motivo que já está no código: é texto de interface
e muda.

Membros novos: `leftCommand`, `leftOption`, `leftControl`, `leftShift`,
`rightShift`, `fn`; `modifiers` (os nove, a tabela do PRD);
`modifier(keyCode:)`; `mouseButton(_:)`, nil abaixo de 3;
`menuChoices(current:)`. `all` continua sendo as três de sempre, porque é a
lista do menu, e o nome fica para não mexer nos usos.

Valores de partida, confirmados pelos DoD 4 e 5:

| Tecla | keyCode esq / dir | máscara esq / dir |
|---|---|---|
| ⌘ | 55 / 54 | 0x0008 / 0x0010 |
| ⌥ | 58 / 61 | 0x0020 / 0x0040 |
| ⌃ | 59 / 62 | 0x0001 / 0x2000 |
| ⇧ | 56 / 60 | 0x0002 / 0x0004 |
| Fn | 63 | `.function` (0x800000) |

Caps Lock (57) fica fora da tabela de propósito: não tem segurar, e alterna o
estado do teclado.

### 2. O identificador guarda o formato antigo e soma um prefixo para mouse

`id` é `"54"` para tecla, o keyCode em texto que está em disco desde 29/08, e
`"mouse:3"` para botão, com o número como as pessoas contam. `named` lê os dois
formatos e devolve nil para o resto, inclusive `"57"` e `"mouse:2"`. Trocar o
formato das teclas exigiria migração para um ganho que ninguém vê, a regra do
`CLAUDE.md` sobre nomes em disco.

`named` aceita qualquer um dos nove modificadores, inclusive ⇧ e ⌘ esquerdo,
que a captura da parte 2 recusa. A porteira é a captura. Quem escreve
`defaults write ... trigger 56` pediu por isso, e o submenu mostra a escolha
como quarta linha, então nada acontece em silêncio.

### 3. Mouse pelos mesmos dois monitores

`start()` soma `.otherMouseDown` e `.otherMouseUp` à máscara. `handle` ganha o
caso: com `trigger.source` igual a `.mouseButton(n)` e
`event.buttonNumber + 1 == n`, `.otherMouseDown` vira `.down(timestamp)` e
`.otherMouseUp` vira `.up(timestamp)`. `.leftMouseDown` e `.rightMouseDown`
nunca entram na máscara: é o que garante "nunca clique principal ou secundário"
sem regra nenhuma.

Monitor global de mouse não exige Acessibilidade, e o app já a tem de qualquer
forma. A aposta a confirmar no DoD 3 é que um clique de botão extra sobre a
janela de outro app não muda o foco: o texto tem que cair no app que estava na
frente.

### 4. `didSet` compara o valor inteiro

`guard trigger != oldValue` no `didSet`: trocar tecla por mouse também tem que
zerar a máquina de estados. As três comparações de `main.swift` seguem o mesmo
caminho, e a `Equatable` sintetizada cobre `source` e `label` juntos.

### 5. As suítes do gatilho mudam de arquivo

Resolve o H5 pelo lado que a convenção já diz, "um arquivo por unidade":
`HotkeyMonitorTests.swift` recebe "Hotkey trigger" e "Hands-free latch"
inteiras, mudando só o que a API nova pede. `AudioRecorderTests.swift` fica com
áudio.

### 6. Verificação por hardware, nesta parte

Sem painel, o único caminho até um gatilho fora das três é `defaults write`. É
de propósito: é o jeito mais barato de saber se Fn chega como `.flagsChanged` e
se as máscaras esquerdas estão certas antes de gastar a parte 2 em cima delas.
`main.swift` já ensina `defaults write com.nevertype.app` numa mensagem de log,
então o comando não é novidade no projeto.

## Padrões aplicáveis

- **`nucleo-testavel.md`**: `Trigger`, `named` e `menuChoices` são puros; o
  `NSEvent` só é tocado em `handle`. Os testes comparam valores de `Trigger`,
  sem monitor instalado.
- **`isolamento-tipado.md`**: nenhum `assumeIsolated` novo. Os dois de `start()`
  continuam os únicos, com o comentário que já têm.
- **`verificacao-estrutural.md`**: máscara e keyCode confirmados pelo evento
  real (DoD 4 e 5). O teste compara `deviceMask` e `keyCode`. O rótulo fica fora da comparação.
- **`falha-alta.md`**: `named` que não reconhece devolve nil, o app cai no
  padrão, e a linha `ready. trigger:` do log diz qual gatilho valeu. Um id
  inválido em disco fica visível ali.

## Riscos

| Risco | Mitigação |
|---|---|
| Fn não chega como `.flagsChanged` a monitor global, ou chega sem keyCode 63 | DoD 4 no teclado do autor. Se cair, Fn sai da tabela com o comentário. |
| Máscara esquerda errada: ⌃ esquerdo dispara junto com o direito | DoD 5 confirma lado por lado. |
| Software do mouse (Logi Options+ e afins) remapeia o botão antes do sistema, e nada chega | Fora do alcance do app. A parte 2 escreve isso na ressalva, a parte 4 na referência. |
| `buttonNumber` do botão do meio não ser 2 em algum mouse | DoD 3 lê o rótulo no log e faz o gesto no botão. A conversão vive num lugar só. |
| Mover 13 testes de arquivo esconde uma regressão na mudança de API | A contagem total não cai (DoD 1), e os testes antigos mudam só onde a API mudou. |

## References

- `.vibeflow/prds/gatilho-por-captura.md`: o PRD, com a tabela de teclas e o anti-escopo
- `Sources/NeverTypeCore/HotkeyMonitor.swift`: `Trigger`, `Latch` e `handle`, o que muda
- `Tests/NeverTypeCoreTests/AudioRecorderTests.swift`, suítes "Hotkey trigger" (L102) e "Hands-free latch" (L386): os testes que mudam de arquivo
- `Sources/NeverTypeCore/PointerGesture.swift`: a forma de regra pura que `menuChoices` segue
