# Audit Report: Gatilho por captura, parte 2

> Auditado em 2026-09-04, a partir de `.vibeflow/specs/gatilho-por-captura-part-2.md`
> Diff auditado: árvore de trabalho contra `ee11a85` (parte 1 commitada), antes do commit desta parte

**Verdict: PASS**

## DoD Checklist

- [x] **1. `swift test` verde com os nove testes.** `Test run with 147 tests in
  17 suites passed`, 138 da parte 1 mais 9. `TriggerCaptureTests.swift` L31,
  L40, L56, L67, L77, L90, L100, L109 e L118, um `@Test` por caso, com os
  nomes da spec.
- [x] **2. O caminho feliz, de olho.** Relato do autor em 2026-09-03: escolheu
  a tecla pelo painel, o título, o submenu e o tooltip nomearam a tecla, e a
  tecla ditou. Evidência mecânica no log do último lançamento: L2
  `trigger is now Left ⌥` (a restauração passando por `setTrigger`) e L3
  `ready. trigger: Left ⌥`, ou seja, a escolha sobreviveu ao relançamento;
  `defaults read com.nevertype.app trigger` responde `58`. A tecla do log é
  ⌥ esquerdo, escolhida pelo caminho da ressalva; ⌃ esquerdo é o relato.
  Confiança: alta para a persistência, média para o resto.
- [x] **3. A suspensão e a volta.** Log L7 `capture panel open: trigger
  monitor off`, L8 `capture panel closed: trigger monitor back on`, L11 e L12
  um ditado gravado e transcrito depois disso (`3200 samples`, `458 ms`), e o
  par de novo em L13 e L14: o monitor voltou nas duas aberturas. Que nada
  grava com o painel aberto é relato do autor. Confiança: alta para a volta,
  média para a suspensão.
- [x] **4. Recusa e ressalva, de olho.** Relato do autor. Evidência mecânica
  do caminho da ressalva: `58` em disco só se alcança pelo botão
  `Use Left ⌥`. Confiança: média.
- [x] **5. Um ponto só muda o gatilho.** `grep -c "monitor.trigger = "
  Sources/NeverType/main.swift` responde `1`, na L575, dentro de
  `setTrigger(_:)` (L573). Chamado por `chooseTrigger`, pelo painel
  (`chooseOtherTrigger`, L587 a L597) e pela restauração do lançamento
  (L252).
- [x] **6. Cinco segundos sem evento.** Relato do autor. Implementação em
  `TriggerCapturePanel.swift` L126 a L131, `Task` com `Task.sleep`, cancelada
  a cada evento e no fechamento. Confiança: média.
- [x] **7. Craftsmanship gate.** Regra, tradução do `NSEvent` e toda frase em
  `NeverTypeCore` (`grep -c "keyCode" Sources/NeverType/TriggerCapturePanel.swift`
  responde `0`). Dois `MainActor.assumeIsolated` no painel (L87 a L99), com o
  comentário das duas razões de `HotkeyMonitor.start()` acima do par, e sem
  terceiro. Zero `!`, zero XCTest, zero rede, zero travessão ou aspas curvas
  nos três arquivos novos e nas linhas adicionadas de `main.swift`. Todo
  `public` novo com doc comment: os de `Verdict`, `init(purpose:)`, do
  `typealias` e dos textos de `Prompt` entraram nesta rodada, comentários só,
  suíte reconfirmada em 147.

## Pattern Compliance

- [x] **`nucleo-testavel.md`**: `TriggerCapture` é puro, com `Input`,
  `Verdict`, `Refusal`, `Caveat`, `Prompt` e a tradução `Input(_ event:)` em
  `TriggerCapture.swift`; o painel só traduz e desenha. Os nove testes rodam
  sem janela, sem mouse e sem relógio. Confiança: alta.
- [x] **`isolamento-tipado.md`**: os dois `assumeIsolated` são os dos
  monitores, pelas mesmas duas razões do `HotkeyMonitor`. O compilador
  recusou devolver `NSEvent` de dentro do `assumeIsolated` (não é
  `Sendable`), e a resposta cruza como `Bool` (L98). A dica de 5 s usa
  `Task`. Confiança: alta.
- [x] **`falha-alta.md`**: recusa, ressalva e silêncio de 5 s são frases na
  tela, cada uma nomeando a saída (`Refusal.description`, `Caveat.description`,
  `Prompt.nothingArrived`). O religamento do monitor tem linha de log dos
  dois lados (`main.swift` L590 e L596). Confiança: alta.
- [x] **`estado-do-usuario.md`**: o monitor local devolve `nil` só para evento
  que nasceu com o painel em foco (L95 a L100); o global não engole. Confiança:
  alta.
- [x] **`estado-consultado.md`**: o submenu se remonta ao abrir, e a quarta
  linha vem de `monitor.trigger`. `previousApp` (L58) é uma cópia guardada, e
  precisa ser: depois de ativar, o app da frente é o próprio NeverType, então
  consultar na hora do fechamento devolveria a resposta errada. Confiança:
  alta.

## Desvio da spec, justificado

**Decisão 8, a devolução do foco.** A spec mandava fechar "do mesmo jeito que
a janela do vocabulário faz", que é `NSApp.hide(nil)`. Em uso, em 2026-09-03,
o autor viu o orb sumir depois de escolher a tecla e só voltar na gravação
seguinte: `hide` esconde todas as janelas do app, o orb junto. O painel passou
a devolver a ativação ao app que estava na frente
(`previous.activate(from: .current, options: [])`, L202), com `hide` como
fallback quando não há esse app (L203). O objetivo da decisão, o foco de
volta, se mantém; o mecanismo mudou, e o comentário no código registra o
porquê e a data. Confirmado pelo autor: o orb ficou.

A janela do vocabulário tem o mesmo `NSApp.hide` (`VocabularyWindow.swift`
L229) e deve esconder o orb do mesmo jeito. Fora do orçamento desta parte;
candidato a `/vibeflow:hotfix` com a evidência de hoje.

## Convention Violations

Nenhuma encontrada. Achados menores, todos INFO:

- `Refusal.description` e `Caveat.description` não têm doc comment próprio.
  São exigência de `CustomStringConvertible`, e o doc do enum diz o que o texto
  faz. Severidade: nenhuma.
- Se o app da frente ao abrir o painel for o próprio NeverType (o orb ativado
  por um clique, por exemplo), `previousApp` aponta para ele mesmo e a
  ativação não devolve o foco a ninguém; o fallback só cobre `nil`. Não
  observado em uso. Severidade: baixa. Confiança: baixa.
- `scripts/install.sh` ("How to use") e `CLAUDE.md` (109 testes) continuam
  desatualizados; a contagem é 147. Parte 4, ou `/vibeflow:teach`.

## Critical Gate

Clean: no destructive operations detected. Os únicos casamentos do catálogo
foram a palavra `mask` (DAT105, que só dispara em linha removida) em linhas
adicionadas, onde significa máscara de evento e de lado da tecla.

## Anti-escopo e orçamento

Respeitado: `HotkeyMonitor.swift` e `MenuLayout.swift` intocados; sem item de
mãos-livres; sem documentação; sem `CGEventTap`; sem janela de ajustes; um
gatilho só; sem combinação; o painel não fecha sozinho por tempo; ressalva
confirmada por botão. Quatro arquivos, no orçamento.

Ready to ship.
