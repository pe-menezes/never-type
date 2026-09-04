# Hotfix: vocabulary-window-hides-the-orb

origin: session
status: verified

## Symptom
Fechar a janela do vocabulário faz o orb sumir. Ele só volta na gravação
seguinte. Visto em 2026-09-03 pelo painel de captura, que tinha copiado a linha
de fechamento da janela do vocabulário: o autor escolheu uma tecla, o painel
fechou, e o orb ficou fora da tela até o ditado seguinte. O painel foi mudado no
mesmo dia (`TriggerCapturePanel.swift`, `windowWillClose`,
`previous.activate(from: .current, options: [])`) e o orb ficou; a janela do
vocabulário continuava com a linha original.

## Checkpoint
hypothesis: `NSApp.hide(nil)` em `VocabularyWindow.windowWillClose`
(`Sources/NeverType/VocabularyWindow.swift`) esconde todas as janelas do app, o
orb junto. Estava ali para devolver o foco ao app em que a pessoa estava, e faz
isso também.
falsification_test: fechar a janela do vocabulário com a linha trocada pela
entrega da ativação ao app que estava na frente, e o orb sumir mesmo assim.
blind_spots: se o orb volta sozinho em algum evento que não seja uma gravação;
não conferido, e não necessário para a correção.

## Preservation
- Fechar a janela do vocabulário continua devolvendo o foco ao app em que a
  pessoa estava: o teclado vai para algum lugar visível.
- A janela do vocabulário continua salvando ao fechar.
- O painel de captura continua se comportando como desde 2026-09-03.

## Eliminated / Evidence

## Root cause
`NSApp.hide(nil)` em `VocabularyWindow.windowWillClose`. O `hide` desativa o app
e esconde todas as janelas dele que aceitam ser escondidas; o painel do orb
aceitava, então ia junto com a janela do vocabulário. A linha era o único jeito
que a janela tinha de devolver o foco.

## Fix
files_changed: Sources/NeverTypeCore/FocusHandback.swift (novo), Sources/NeverType/VocabularyWindow.swift, Sources/NeverType/RecordingOverlay.swift

`FocusHandback` (NeverTypeCore) lembra o app da frente antes de este app se
ativar e, ao fechar, entrega a ativação a ele, a ativação cooperativa do macOS
14; esconde o app só como fallback, com nada lembrado, com o próprio app
lembrado, ou com uma ativação que o sistema recusou. Não faz nada quando este
app já não está na frente: a pessoa foi para outro lugar, e as duas respostas
seriam erradas. As chamadas de sistema entram por parâmetro com padrão, a mesma
forma de `TextInjector.insert(secureInput:)`, então cada ramo tem teste.
`VocabularyWindow` chama `remember()` no `show()`, antes do `NSApp.activate`, e
`giveBack()` no `windowWillClose`, onde estava o `NSApp.hide(nil)`.

O painel do orb ganhou `canHide = false` (`RecordingOverlay.swift`) em
2026-09-04, depois da revisão do PR #6: o fallback do hand-back ainda passa pelo
`hide`, e o comando Esconder do sistema (⌘H) sempre passou. A linha fecha todos
os caminhos de uma vez, inclusive os que o app não controla.

## DoD
- [x] `FocusHandbackTests.swift` vermelho antes da correção, pelas duas razões
  nomeadas (`NSApp.hide(` presente, `FocusHandback` ausente), verde depois.
- [x] `swift test` verde: 169 testes em 18 suítes.
- [x] `NSApp.hide(` não aparece mais em `Sources/NeverType/`.
- [x] De olho: abrir a janela do vocabulário pelo menu, fechar, e o orb fica; o
  foco volta ao app que estava na frente. Confirmado pelo autor em 2026-09-04.

## Regression
WHEN a janela do vocabulário fecha, tendo sido aberta com outro app na frente
THEN este app não é escondido, então o orb continua na tela, e o app que estava
na frente volta a ficar ativo
test: Tests/NeverTypeCoreTests/FocusHandbackTests.swift
oracle_type: derived
reproduction: real
verification: red-green

A janela vive no alvo executável, que o alvo de teste não importa, então o
oráculo lê o texto do arquivo da janela: nada de `NSApp.hide(` em
`VocabularyWindow.swift` nem em `TriggerCapturePanel.swift`, e as chamadas
`focus.remember()` e `focus.giveBack()` presentes nos dois. A regra em si tem
cinco testes com as chamadas de sistema trocadas: devolve o foco e não esconde
nada; esconde só com nada na frente ou ativação recusada; nunca ativa a si
mesmo; esquece o app depois de devolver; e não faz nada com o app já fora da
frente.

## Deviations
- O painel de captura mantinha uma cópia inline do mesmo mecanismo
  (2026-09-03). Consolidado no mesmo dia, fora desta chamada: os dois passaram
  por `FocusHandback`, o comentário desatualizado saiu, e o oráculo de texto lê
  as duas janelas.
- O oráculo de texto aceitava a palavra `FocusHandback` em qualquer lugar do
  arquivo, comentário incluído. Apertado depois da revisão do PR #6 para exigir
  as chamadas.
