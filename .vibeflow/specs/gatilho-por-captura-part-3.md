# Spec: Gatilho por captura, parte 3: segundo gatilho de mãos-livres

> Gerado via /vibeflow:gen-spec em 2026-09-01
> A partir de `.vibeflow/prds/gatilho-por-captura.md`
> Parte 3 de 4.

## Objetivo

Um segundo gatilho, opcional e escolhido no mesmo painel, trava em mãos-livres
com um toque e transcreve com o toque seguinte.

## Contexto

Mãos-livres hoje é o duplo toque do gatilho principal: `Latch` passa por
`awaitingSecondTap` e chega a `latched`. O Wispr Flow tem um atalho próprio para
isso, e o PRD aceitou a versão que cabe na arquitetura: um segundo gatilho da
mesma tabela, com semântica de liga e desliga. Combinação com tecla comum ficou
no anti-escopo, porque a tecla chega ao app da frente.

A parte 2 deixou a finalidade `handsFree(pushToTalk:)` na regra de captura, com
a recusa do gatilho principal testada, e o título do painel para ela. Esta
parte liga o resto: o gatilho no monitor, o toque na máquina de estados, a
persistência e os itens do submenu Hands-free.

## Definition of Done

1. **`swift test` verde, com testes novos em
   `Tests/NeverTypeCoreTests/HotkeyMonitorTests.swift`**, cada um com seu
   `@Test`. Na suíte "Hands-free latch", sobre a `Latch`:
   - "a toggle from idle asks to start, and the accepted start locks":
     `handle(.toggle) == [.start]`, `resolveStart(accepted: true) == [.latch]`,
     `isLatched`;
   - "a refused start after a toggle leaves nothing armed":
     `resolveStart(accepted: false) == []` e o estado é `idle`;
   - "a toggle while holding locks without the second tap";
   - "a toggle while waiting for the second tap locks and disarms the timer":
     `[.disarmTimeout, .latch]`;
   - "a toggle while locked finishes";
   - "with hands-free off the toggle does nothing", em todos os estados
     alcançáveis.
   Na suíte "Hotkey trigger", sobre o monitor, em teste `@MainActor` sem
   `start()`:
   - "choosing the hands-free key as the trigger clears the hands-free key".

2. **O ciclo inteiro, de olho.** Menu › Hands-free › Choose a hands-free key…,
   ⌥ direito: um toque toca o tom de trava e o pill entra em trava sem tecla
   segurada; falar; outro toque transcreve no app da frente. Um toque, Esc:
   descarta. Sair e abrir o app de novo mantém a tecla. `Remove hands-free key`
   limpa, e o submenu volta a mostrar `Choose a hands-free key…`.

3. **Os dois gatilhos não coincidem.** No painel aberto para mãos-livres, a
   tecla do gatilho principal mostra a linha de recusa e o painel continua. Com
   ⌥ direito como tecla de mãos-livres, escolher ⌥ direito nas três do submenu
   Hotkey limpa a tecla de mãos-livres, e o log diz
   `hands-free key removed: it is now the trigger`.

4. **Mãos-livres desligado desliga a tecla.** Com `Hands-free` desmarcado, os
   itens da tecla somem do submenu e um toque em ⌥ direito não faz nada. Ligar
   de novo traz os itens e a tecla de volta, sem reescolher.

5. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md` no
   diff: sem `assumeIsolated` novo, sem `!`, sem XCTest, sem chamada de rede,
   sem travessão nem aspas curvas em linha adicionada
   (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio). Todo `public` novo com doc
   comment dizendo o porquê, e o `didSet` novo com o comentário dizendo o que
   aconteceria sem ele.

## Escopo

- `Sources/NeverTypeCore/HotkeyMonitor.swift`: `handsFreeTrigger: Trigger?`,
  `Latch.Input.toggle`, o estado `startingLatched`, `resolveStart` devolvendo
  ações, o roteamento em `handle`, o `didSet` que limpa a coincidência.
- `Sources/NeverType/main.swift`: `setHandsFreeTrigger(_:)`, a chave
  `handsFreeTrigger` em `UserDefaults`, a restauração, os itens do submenu, a
  abertura do painel com `.handsFree(pushToTalk:)`.
- `Tests/NeverTypeCoreTests/HotkeyMonitorTests.swift`.

Três arquivos.

## Anti-escopo

- **Não** combinação com tecla comum. Continua no anti-escopo do PRD.
- **Não** muda `MenuLayout` nem o título `Hands-free: double tap`. A tecla
  aparece dentro do submenu, onde o ciclo é ensinado.
- **Não** muda `TriggerCapture.swift` nem `TriggerCapturePanel.swift`: a parte
  2 já deixou a finalidade pronta.
- **Não** muda documentação: parte 4.
- **Não** terceiro gatilho, **não** tecla de mãos-livres com o modo desligado,
  **não** tecla própria para descartar (Esc continua sendo a saída).

## Decisões técnicas

### 1. O toque entra na `Latch`, e a trava depois do início sai de `resolveStart`

```swift
public enum Input {
    case down(TimeInterval)
    case up(TimeInterval)
    case otherKey
    case escape
    case timeout
    /// The hands-free key went down: lock, or finish if already locked.
    case toggle
}
```

Tabela do `.toggle`, com `handsFree` ligado:

| Estado | Ações | Estado seguinte |
|---|---|---|
| `idle` | `[.start]` | `startingLatched` |
| `holding` | `[.latch]` | `latched` |
| `awaitingSecondTap` | `[.disarmTimeout, .latch]` | `latched` |
| `latched` | `[.finish]` | `idle` |
| `startingLatched` | `[]` | `startingLatched` |

`resolveStart(accepted:)` passa a devolver `[Action]`: em `startingLatched`,
aceito devolve `[.latch]` e vai para `latched`; recusado zera e devolve `[]`.
Nos outros estados devolve `[]`. O motivo de não devolver `[.start, .latch]`
de uma vez: um início recusado (sem Acessibilidade, sem microfone, falha do
gravador) faria o app tocar o tom de trava e mostrar o pill travado sobre uma
gravação que não existe. A ordem "só trava se começou" é regra, e regra vive no
tipo puro, onde tem teste. `apply` só aplica o que `resolveStart` devolve.

`startingLatched` é transitório: `apply` chama `resolveStart` na mesma volta da
main actor em que aplicou `.start`, e nenhum evento entra no meio.

Com `handsFree` desligado, `.toggle` devolve `[]` em todo estado. Mesma forma da
regra que já existe para o duplo toque.

### 2. O roteamento em `handle` reconhece os dois gatilhos

Evento que casa com `trigger` segue como hoje, `.down` e `.up`. Evento que casa
com `handsFreeTrigger` vira `.toggle` na descida, e a soltura é ignorada:
segurar a tecla de mãos-livres não significa nada, e o PRD deixou isso em
aberto. Vale para tecla (`.flagsChanged`) e para botão (`.otherMouseDown`), com
a mesma conversão de `buttonNumber` da parte 1.

Travou pela tecla de mãos-livres e tocou o gatilho principal: `(.latched,
.down)` já encerra, como hoje. Nenhum caso especial.

### 3. Mãos-livres desligado desliga a tecla e esconde os itens

"Off" hoje significa "a tecla só grava enquanto segurada", e o submenu diz isso
numa linha. Uma tecla própria de trava com o modo desligado contradiz a linha.
Então: com `handsFreeEnabled` falso, `.toggle` não faz nada (Decisão 1) e os
itens da tecla não são montados. A escolha continua guardada, e volta com o
modo.

### 4. Os dois gatilhos nunca coincidem, por dois caminhos

Pelo painel, `TriggerCapture` com `.handsFree(pushToTalk:)` recusa o gatilho
principal (parte 2). Pelas três do submenu Hotkey, que não passam pelo painel,
o `didSet` de `trigger` limpa `handsFreeTrigger` quando os dois ficam iguais,
e o app loga `hands-free key removed: it is now the trigger`. A regra fica no
monitor, para o teste `@MainActor` alcançá-la sem menu.

`handsFreeTrigger` tem `didSet` próprio que zera o gesto, pelo mesmo motivo do
de `trigger`: um gesto em voo pertence à regra que o começou. Quem muda a tecla
encerra a gravação órfã, como `chooseTrigger` faz.

### 5. Persistência e restauração

Chave `handsFreeTrigger` em `UserDefaults`, com o `id` da parte 1; ausente é
"nenhuma". `setHandsFreeTrigger(_ trigger: Trigger?)` é o único ponto de
mudança: atribui, persiste ou remove a chave, encerra gravação órfã, loga
`hands-free key is now <rótulo>` ou `hands-free key removed`. A restauração no
lançamento passa por ele.

### 6. O submenu Hands-free, com o modo ligado

Depois das três linhas de instrução e de um separador:

- sem tecla: `Choose a hands-free key…`;
- com tecla: a linha cinza `Tap Right ⌥ to lock, tap again to finish`, depois
  `Change hands-free key…` e `Remove hands-free key`.

O painel abre com `.handsFree(pushToTalk: monitor.trigger)`, o monitor é parado
e religado como na parte 2, e o veredito aceito entra por
`setHandsFreeTrigger`.

## Padrões aplicáveis

- **`nucleo-testavel.md`**: a tabela do toque e a regra "só trava se começou"
  vivem em `Latch`, e o teste as percorre sem monitor. A coincidência vive no
  `didSet` do monitor, alcançável por teste `@MainActor`.
- **`isolamento-tipado.md`**: nenhum `assumeIsolated` novo. O roteamento novo
  está dentro de `handle`, que já roda na main actor.
- **`falha-alta.md`**: início recusado não toca tom de trava nem mostra pill
  travado (Decisão 1). Toda mudança de tecla vai para o log com o rótulo.
- **`estado-consultado.md`**: o submenu se remonta ao abrir e lê
  `monitor.handsFreeTrigger`; nenhuma variável do menu guarda a tecla.

## Riscos

| Risco | Mitigação |
|---|---|
| Dois toques rápidos na tecla de mãos-livres travam e encerram uma gravação de 100 ms | Igual a um toque curto no gatilho principal hoje: transcrição vazia loga `empty transcription` e não insere nada. Aceito. |
| Toque na tecla de mãos-livres enquanto o pill ainda diz "working" do ditado anterior | Mesmo comportamento do gatilho principal hoje: nenhum caso especial. Se incomodar em uso, vira item do backlog com evidência. |
| A tecla de mãos-livres remapeada pelo software do mouse nunca chega | Mesma ressalva da parte 2, na tela, ao escolher. |
| `resolveStart` devolvendo ações muda um contrato que a suíte antiga exercita | Os testes antigos continuam válidos: fora de `startingLatched` a devolução é `[]`, e o `_ =` nos usos antigos é a única edição. |

## References

- `.vibeflow/prds/gatilho-por-captura.md`: o PRD, e a decisão sobre o segundo gatilho
- `Sources/NeverTypeCore/HotkeyMonitor.swift`, `Latch`: a máquina de estados que ganha o toque
- `Sources/NeverTypeCore/TriggerCapture.swift` (parte 2), `Purpose.handsFree`: a recusa já pronta
- `Sources/NeverType/main.swift`, `handsFreeMenu(enabled:)` e `toggleHandsFree`: onde os itens entram

## Dependências

- .vibeflow/specs/gatilho-por-captura-part-1.md
- .vibeflow/specs/gatilho-por-captura-part-2.md
