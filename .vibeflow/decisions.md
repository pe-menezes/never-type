# Decisões

Registro das decisões de arquitetura, a mais recente primeiro. O backlog guarda
a lista curta em "Decidido e fechado"; aqui fica o contexto de cada uma.

### 2026-09-04: Devolver o foco é ativar o app anterior
**Decision:** Ao fechar uma janela do app, a ativação vai para o app que estava
na frente quando ela abriu (`NSRunningApplication.activate(from: .current,
options: [])`, a ativação cooperativa do macOS 14), lembrado antes de o app se
ativar. `NSApp.hide(nil)` fica só como fallback: nada lembrado, o próprio app
lembrado, ou ativação recusada. Vive em `FocusHandback` (NeverTypeCore), com as
chamadas de sistema por parâmetro.
**Context:** `hide` esconde todas as janelas do app, o orb junto. Visto em
2026-09-03 no painel de captura, que tinha copiado a linha da janela do
vocabulário: a tecla era escolhida, o painel fechava, e o orb sumia até a
gravação seguinte. A janela do vocabulário fazia o mesmo desde que existe;
hotfix em 2026-09-04.
**Discarded alternatives:** `NSApp.hide` sozinho (esconde o orb).
`NSApp.deactivate()` (a documentação diz para não chamar, e não diz quem fica
ativo depois). `canHide = false` no painel do orb (resolve o sintoma e mantém o
mecanismo que esconde o resto).

### 2026-09-01: O gatilho é escolhido apertando, dentro do modo escuta
**Decision:** O gatilho pode ser qualquer modificador dos dois lados, Fn ou um
botão do mouse a partir do terceiro, escolhido num painel que espera a próxima
tecla. Tecla comum, combinação, ⇧, ⌘ esquerdo, Caps Lock e os dois cliques
principais são recusados com o motivo na tela. Um segundo gatilho, opcional e da
mesma tabela, trava o mãos-livres com um toque. O app continua escutando sem
interceptar: nenhum `CGEventTap`.
**Context:** PRD `.vibeflow/prds/gatilho-por-captura.md`, discovery de
2026-09-01: quem testou pediu a própria tecla, o gesto de apertar para escolher
(Wispr Flow) e um botão do mouse. O modo escuta é o que dispensa interceptar, e
interceptar é o que pode congelar a entrada do sistema inteiro. Um início em
falso custa microfone, tom e pill, por isso as teclas de atalho do dia a dia são
recusadas.
**Discarded alternatives:** `CGEventTap` interceptando (I1: callback lento
congela o teclado). Dependência `KeyboardShortcuts` (SPM contra a linkagem
estática e o hardened runtime). Vários gatilhos ao mesmo tempo (o "+" do Wispr
Flow). Combinação com tecla comum para mãos-livres, o "⌥ Space" (chega ao app da
frente, insere espaço inflexível, e é o atalho padrão de Raycast e Alfred).

### 2026-09-01: Mãos-livres pode ser desligado
**Decision:** O duplo toque que trava a gravação tem um interruptor no menu,
ligado por padrão, guardado em `UserDefaults` sob `handsFree`. Desligado, um
toque curto conclui na própria soltura, sem a espera de 300 ms pelo segundo
toque, e (desde 2026-09-04) a segunda tecla de mãos-livres também não faz nada.
**Context:** Quem trava sem querer precisa de uma saída do modo, e o modo custa
a todo mundo até 300 ms num toque abaixo do limiar de 250 ms. A razão estava só
em `HotkeyMonitor.swift` (`handsFreeEnabled`) e no PR #5, que some depois do
merge; o backlog (H16) pediu o registro aqui, porque o interruptor cria uma
preferência permanente para todo mundo que já usa o app.
**Discarded alternatives:** Armar a janela do segundo toque como sempre e
recusar a trava quando ele chegasse (mantém um timer para um gesto que não pode
acontecer e deixa um estado que nenhuma entrada produz). Não oferecer saída
(quem trava sem querer fica sem como sair, salvo Esc a cada vez).
