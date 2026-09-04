# Spec: Gatilho por captura, parte 2: regra de captura, painel e item de menu

> Gerado via /vibeflow:gen-spec em 2026-09-01
> A partir de `.vibeflow/prds/gatilho-por-captura.md`
> Parte 2 de 4.

## Objetivo

Do submenu Hotkey, a pessoa aperta a tecla ou o botão que quer e ele vira o
gatilho na hora, com o resto recusado dizendo por quê.

## Contexto

Depois da parte 1, o `HotkeyMonitor` aceita nove modificadores e os botões
extras do mouse, e o único caminho até eles é `defaults write`. Esta parte põe o
gesto que as pessoas pediram: um painel que espera a próxima tecla.

O que já existe e esta parte usa:

- `chooseTrigger` (`main.swift`) é o único ponto que muda o gatilho, e é o que
  mantém título do menu, submenu e tooltip (`refreshHoverHint`) dizendo a tecla
  certa. O backlog avisa que um segundo caminho deixaria o tooltip errado sem
  sinal. O painel tem que desembocar no mesmo método.
- `endOrphanRecording` encerra a gravação que um gesto abandonado segurava.
  Trocar o gatilho no meio de um ditado já descarta o ditado; abrir o painel
  faz o mesmo.
- `VocabularyWindow.show()` é o precedente de janela num app acessório:
  `NSApp.activate(ignoringOtherApps: true)` antes de `makeKeyAndOrderFront`, e
  o foco volta ao app anterior ao fechar.
- `HotkeyMonitor.start()` instala um monitor global e um local, com
  `assumeIsolated` justificado em comentário pelas duas razões (AppKit entrega
  na main thread; a ordem entre down e up importa). O painel copia a forma e o
  comentário.
- `PointerGesture` e `PasteTarget.decide` são o molde da regra: uma função
  pura, de evento para veredito, exercitável sem teclado, sem mouse e sem
  janela.

## Definition of Done

1. **`swift test` verde, com `Tests/NeverTypeCoreTests/TriggerCaptureTests.swift`
   novo**, cada caso com seu `@Test`:
   - "a right-side modifier is accepted on its release": ⌘, ⌥ e ⌃ direitos e ⌃
     esquerdo, `.waiting` na descida e `.accepted` na subida;
   - "Fn, Left ⌥ and a mouse button are accepted with their caveat";
   - "Shift, Left ⌘ and Caps Lock are refused on the press, each with its
     reason";
   - "a regular key is refused, alone or on top of a held modifier, and the
     release that follows accepts nothing";
   - "a second modifier on top of a held one is refused as a combination";
   - "Escape cancels, from idle and from a hold";
   - "the secondary click is refused";
   - "for hands-free, the push-to-talk key is refused";
   - "a release with nothing held is ignored".

2. **O caminho feliz, de olho.** Menu › Hotkey › Other key or mouse button…,
   segurar e soltar ⌃ esquerdo: o painel fecha; o título do menu diz
   `Hotkey: Left ⌃`; o submenu mostra Left ⌃ marcado como quarta linha; o
   tooltip do ícone nomeia Left ⌃; segurar ⌃ esquerdo dita no app da frente;
   sair e abrir o app de novo mantém Left ⌃.

3. **A suspensão e a volta.** Com o painel aberto, segurar ⌘ direito (o gatilho
   de então): nenhum tom, nenhum pill, nenhuma gravação. Esc fecha o painel, e
   ⌘ direito volta a ditar. Este é o caminho de falha que mais importa: um
   painel que fecha sem religar o monitor deixa o app mudo até o relançamento.

4. **Recusa e ressalva, de olho.** Com o painel aberto: ⇧ direito mostra a
   linha do motivo e o painel continua; uma letra, idem; Fn mostra a ressalva e
   o botão `Use Fn`, e Return confirma; clique do meio mostra a ressalva do
   mouse e `Use Mouse button 3`; clique secundário mostra a recusa.

5. **Um ponto só muda o gatilho.**
   `grep -c "monitor.trigger = " Sources/NeverType/main.swift` responde `1`, e
   a linha está dentro de `setTrigger(_:)`, chamado pelas três teclas do
   submenu, pelo painel e pela restauração no lançamento.

6. **Cinco segundos sem evento.** Abrir o painel e não apertar nada: em 5 s a
   linha de status diz que nada chegou e que Esc fecha. É a saída para o
   teclado que trata Fn no firmware.

7. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md` no
   diff. A regra e toda frase que a pessoa lê vivem em `NeverTypeCore`
   (`grep -c "keyCode" Sources/NeverType/TriggerCapturePanel.swift` responde
   `0`). Os dois `assumeIsolated` do painel carregam o mesmo comentário de duas
   razões de `HotkeyMonitor.start()`, e não há um terceiro. Sem `!`, sem
   XCTest, sem chamada de rede, sem travessão nem aspas curvas em linha
   adicionada (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio).

## Escopo

- `Sources/NeverTypeCore/TriggerCapture.swift` (novo): a regra pura, com
  `Purpose`, `Input`, `Verdict`, `Refusal` e `Caveat`, e o texto de cada recusa
  e ressalva.
- `Sources/NeverType/TriggerCapturePanel.swift` (novo): o painel, os dois
  monitores, a linha de status, os botões, a dica dos 5 s.
- `Sources/NeverType/main.swift`: `setTrigger(_:)`, o item de captura no
  `hotkeyMenu()`, abrir o painel, parar e religar o monitor.
- `Tests/NeverTypeCoreTests/TriggerCaptureTests.swift` (novo).

Quatro arquivos. A finalidade `handsFree(pushToTalk:)` já entra na regra e no
título do painel nesta parte, para a parte 3 não tocar nos dois arquivos; até
lá, só o teste a exercita.

## Anti-escopo

- **Não** muda `HotkeyMonitor.swift`. A suspensão é `stop()` e `start()`, que
  já existem (Decisão 3).
- **Não** muda `MenuLayout`. Ele decide as linhas do menu principal, e o título
  `Hotkey: <tecla>` já carrega o rótulo. O submenu continua montado em
  `main.swift`, com `menuChoices(current:)` da parte 1.
- **Não** há item de mãos-livres no menu: parte 3.
- **Não** muda documentação: parte 4.
- **Não** `CGEventTap`. O monitor local do painel devolve `nil` só para evento
  que nasceu com o painel em foco; o global não engole nada, e não precisa.
- **Não** janela de ajustes, **não** mais de um gatilho, **não** combinação.
- **Não** fechar o painel sozinho por tempo. A dica dos 5 s é uma frase; Esc
  continua sendo a saída.
- **Não** confirmar ressalva por segundo aperto da tecla (Decisão 5).

## Decisões técnicas

### 1. A regra é uma struct pura, e o veredito sai na soltura

```swift
public struct TriggerCapture: Sendable {
    public enum Purpose: Sendable, Equatable {
        case pushToTalk
        /// The hands-free key cannot be the push-to-talk key.
        case handsFree(pushToTalk: HotkeyMonitor.Trigger)
    }
    public enum Input: Sendable, Equatable {
        /// `.flagsChanged`: the key, and the raw flags after the change.
        case flagsChanged(keyCode: UInt16, rawFlags: UInt)
        case keyDown(keyCode: UInt16)
        /// `NSEvent.buttonNumber + 1`, as people count.
        case mouseDown(button: Int)
        case mouseUp(button: Int)
        case rightMouseDown
    }
    public enum Verdict: Sendable, Equatable {
        case waiting
        case accepted(HotkeyMonitor.Trigger)
        case acceptedWithCaveat(HotkeyMonitor.Trigger, Caveat)
        case refused(Refusal)
        case cancelled
    }
    public init(purpose: Purpose)
    public mutating func handle(_ input: Input) -> Verdict
}
```

Dois estados: `idle` e `holding(Trigger)`. Modificador aceito na **soltura**, e
só se nada mais chegou entre a descida e ela. O motivo: uma combinação só se
revela depois que o modificador desceu, e a soltura é o momento em que se sabe
que nada veio junto. Tecla recusada (⇧ dos dois lados, ⌘ esquerdo, Caps Lock,
tecla comum) é recusada na **descida**, porque não há o que esperar. Uma tecla
comum sobre um modificador seguro recusa e volta a `idle`; a soltura que vem
depois cai em `idle` e é ignorada. Segundo modificador sobre um seguro: recusa
como combinação. Esc (`keyDown(53)`) cancela de qualquer estado. Botão do
mouse: `mouseDown` segura, `mouseUp` do mesmo botão aceita com a ressalva.
`rightMouseDown` recusa. Botão principal não é `Input`: é o clique nos botões do
próprio painel.

A regra consulta `Trigger.modifier(keyCode:)` da parte 1 para saber lado e
máscara, e `Trigger.mouseButton(_:)` para o mouse. A tabela de quem é aceito,
com ressalva ou recusado é a do PRD, e mora aqui.

### 2. Cada recusa e cada ressalva é um caso de enum com `description`

Mesma forma dos erros do projeto (`enum ...: CustomStringConvertible`, texto em
inglês nomeando a saída). O painel só exibe `description`; nenhuma frase vive
no arquivo do painel. A essência de cada texto:

| Caso | O que a linha diz |
|---|---|
| `Refusal.reachesFrontApp` | One key on its own. A regular key or a combination would also reach the app in front. |
| `Refusal.everyCapitalLetter` | Not ⇧: every capital letter would start a recording. |
| `Refusal.everyShortcut` | Not Left ⌘: every shortcut would start a recording. Right ⌘ works. |
| `Refusal.togglesKeyboardState` | Not Caps Lock: it toggles the keyboard state and cannot be held. |
| `Refusal.secondaryClick` | Not the secondary click. A mouse button from the third on works. |
| `Refusal.alreadyThePushToTalkKey` | That is the push-to-talk key. Pick another one for hands-free. |
| `Caveat.fnSystemAction` | Fn also opens the emoji picker unless System Settings > Keyboard sets "Press 🌐 key to" to "Do Nothing". Some keyboards handle Fn on their own, and macOS never sees it. |
| `Caveat.leftOptionAccents` | On a US layout, Left ⌥ types the accents, and every accent would start a recording. |
| `Caveat.clickReachesFrontApp` | The click still reaches the app in front: in a browser, button 4 is Back. A button remapped by the mouse software never reaches NeverType. |

### 3. A suspensão é `stop()` e `start()`, sem estado novo no monitor

Abrir o painel: `endOrphanRecording("the trigger is being chosen")`,
`monitor.stop()`, mostrar. Fechar o painel, por qualquer caminho:
`monitor.start()`, num lugar só, o `windowWillClose`. O `stop()` já zera a
máquina de estados, então o gesto em voo morre junto, pelo mesmo motivo de
`chooseTrigger`.

A alternativa era um modo de captura dentro do `HotkeyMonitor`, roteando os
eventos para a regra pelos monitores que já existem. Custa um arquivo a mais
nesta parte e um estado a mais num tipo que já tem quatro. O preço da escolha
feita é que o religamento é uma chamada que pode faltar, e por isso o DoD 3 é
humano e explícito.

### 4. O painel tem os dois monitores, e só o local engole

Um clique de botão extra com o ponteiro sobre a janela de outro app é entregue
a esse app, e só o monitor global vê. Tecla vai para a janela em foco, que é o
painel, e só o local vê. Os dois alimentam a mesma `TriggerCapture`, e um
evento nunca chega pelos dois. O local devolve `nil` para o evento que tratou,
senão cada tecla recusada faz o macOS bipar; o global não engole, e não
precisa. Os dois `assumeIsolated` ganham o comentário de `HotkeyMonitor.start()`
inteiro: AppKit entrega na main thread, e a ordem entre descida e soltura é a
própria regra.

A dica dos 5 s é uma `Task` na main actor com `Task.sleep`, cancelada em
qualquer evento e no fechamento. Sem `Timer`, sem `assumeIsolated` extra.

### 5. Ressalva se confirma por botão, com a captura já parada

No `acceptedWithCaveat`, o painel para de alimentar a regra, mostra a linha e
oferece `Use <rótulo>` como botão padrão, com Cancel ao lado. Return confirma
porque a captura já parou e Return é só o botão padrão. Esc cancela. A pessoa
lê a ressalva antes de o gatilho valer, que era o critério do PRD, e sem
inventar um gesto de "aperte de novo" que a tecla Fn, com o seletor de emoji
ligado, faria abrir o seletor duas vezes.

### 6. `setTrigger(_:)` é o único ponto de mudança

Recebe o `Trigger`, ignora igualdade (o mesmo motivo de hoje: reescolher a
mesma tecla não pode descartar um ditado em mãos-livres), atribui, persiste
pelo `id`, chama `endOrphanRecording`, `refreshHoverHint` e loga
`trigger is now <rótulo>`. `chooseTrigger`, o painel e a restauração do
lançamento chamam esse método. Na restauração, persistir de novo e encerrar
gravação inexistente são inofensivos, e o custo compra a contagem `1` do DoD 5.

### 7. O submenu Hotkey

`menuChoices(current:)`, cada linha com marca na atual; separador; `Other key or
mouse button…`; separador; `Sounds`. A quarta linha, quando existe, é a atual
fora das três, e continua sendo uma ação (reescolher é ignorado por
igualdade).

### 8. O painel

`NSPanel` pequeno, sem redimensionar, título `Choose the trigger`. Três linhas de
texto: a instrução (`Press the key or mouse button to use`), a linha fixa do
que serve (`A modifier key on either side, Fn, or a mouse button from the third
on. Esc closes.`) e a linha de status, vazia até haver recusa, ressalva ou a
dica dos 5 s. Botão Cancel sempre; `Use <rótulo>` só na ressalva. Uma instância
só, como `vocabularyWindow`; abrir de novo traz à frente. Ao fechar, o foco
volta ao app anterior do mesmo jeito que a janela do vocabulário faz.

## Padrões aplicáveis

- **`nucleo-testavel.md`**: `TriggerCapture` e os textos em `NeverTypeCore`,
  sem AppKit; o painel só traduz `NSEvent` em `Input` e desenha `Verdict`. Os
  nove testes rodam sem monitor, sem janela e sem relógio.
- **`isolamento-tipado.md`**: o painel é `@MainActor`; os dois `assumeIsolated`
  são a exceção documentada, pelo mesmo par de razões de `HotkeyMonitor`; a
  dica de 5 s usa `Task`, sem `Timer`.
- **`falha-alta.md`**: recusa, ressalva e silêncio de 5 s são frases na tela,
  cada uma nomeando a saída. Painel que fecha sem religar o monitor é a falha
  desta parte, e o DoD 3 a exercita.
- **`estado-do-usuario.md`**: o painel engole só o que nasceu com ele em foco.
  Nada que a pessoa apertou some do app da frente por causa do NeverType.
- **`estado-consultado.md`**: o submenu se remonta ao abrir, como hoje, e a
  marca na quarta linha vem de `monitor.trigger` a cada abertura.

## Riscos

| Risco | Mitigação |
|---|---|
| O painel fecha por um caminho que não religa o monitor, e o app fica mudo | Religamento num lugar só, `windowWillClose`, e o DoD 3 aperta o gatilho depois do Esc. |
| O clique de botão extra sobre outro app não chega ao monitor global com o NeverType ativo | DoD 4 clica com o ponteiro fora do painel. Se não chegar, o painel instrui a clicar sobre ele mesmo, e o texto diz isso. |
| A pessoa aperta o gatilho atual para reescolhê-lo e nada acontece por igualdade | `setTrigger` ignora igualdade em silêncio, e o painel fecha como aceito: para quem escolheu, a tecla vale. |
| A tecla que abriu o menu (⌥ para diagnóstico) ainda está pressionada quando o painel abre, e a soltura chega solta | "a release with nothing held is ignored" cobre: soltura em `idle` é `.waiting`. |
| Teclado de terceiros trata Fn no firmware e o painel fica em silêncio | A dica dos 5 s (DoD 6) e a ressalva de Fn dizem isso por escrito. |
| Return confirma a ressalva antes de a pessoa ler | O botão padrão só existe depois da ressalva aparecer, e a captura já parou. |

## References

- `.vibeflow/prds/gatilho-por-captura.md`: o PRD, com a tabela e o anti-escopo
- A tela de atalhos do Wispr Flow que o autor mandou na discovery: o gesto a replicar é apertar a tecla e vê-la escolhida. A janela de ajustes fica de fora.
- `Sources/NeverTypeCore/HotkeyMonitor.swift`, `start()`: a instalação dos dois monitores e o comentário do `assumeIsolated` a copiar
- `Sources/NeverType/VocabularyWindow.swift`, `show()`: como uma janela aparece e devolve o foco num app acessório
- `Sources/NeverTypeCore/PointerGesture.swift` e `PasteTarget.swift`: a forma da regra pura
- `Sources/NeverTypeCore/Transcriber.swift`, o enum de erro com `description`: a forma dos textos de recusa
- `Sources/NeverType/main.swift`, `chooseTrigger` e `endOrphanRecording`: o que vira `setTrigger(_:)`

## Dependências

- .vibeflow/specs/gatilho-por-captura-part-1.md
