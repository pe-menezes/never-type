# Audit Report: Gatilho por captura, parte 3

> Auditado em 2026-09-04, a partir de `.vibeflow/specs/gatilho-por-captura-part-3.md`
> Diff auditado: árvore de trabalho contra `8a1e03d` (parte 2 commitada), antes do commit desta parte

**Verdict: PASS**

## DoD Checklist

- [x] **1. `swift test` verde com os sete testes novos.** `Test run with 154
  tests in 17 suites passed`, 147 da parte 2 mais 7. Na suíte "Hands-free
  latch" (`HotkeyMonitorTests.swift` L274, L284, L294, L303, L313, L325) os
  seis do toque, com os nomes da spec; na suíte "Hotkey trigger" (L122) o
  `@MainActor` "choosing the hands-free key as the trigger clears the
  hands-free key", num `HotkeyMonitor()` sem `start()`. O uso antigo de
  `resolveStart` ganhou o `_ =` que a spec previa.
- [x] **2. O ciclo inteiro, de olho.** Relato do autor em 2026-09-04, com o
  log de duas sessões: `hands-free key is now Right ⌥` ao escolher pelo
  painel; `hands-free locked. Tap Left ⌥ to transcribe, Esc to discard.`
  depois de um toque, sem duplo toque; `recorded: 35200 samples (2.2 s)` e
  `transcribed in 488 ms` no toque seguinte; nova trava seguida de
  `cancelled` (Esc); `hands-free key removed` pelo item Remove. Na sessão
  seguinte, `hands-free key is now Right ⌥` antes de `ready. trigger`, ou
  seja, a restauração no lançamento. `defaults read` responde `54` para
  `handsFreeTrigger`, a tecla escolhida por último. Confiança: alta.
- [x] **3. Os dois gatilhos não coincidem.** Log: `hands-free key removed: it
  is now the trigger` seguido de `trigger is now Right ⌥`, o quick pick de
  ⌥ direito com ⌥ direito como tecla de mãos-livres. A recusa no painel é
  relato do autor, com o par `capture panel open` / `closed` sem tecla
  escolhida entre eles como rastro. Confiança: alta para o quick pick, média
  para a recusa.
- [x] **4. Mãos-livres desligado desliga a tecla.** Log `hands-free: off` e
  `defaults read handsFree` respondendo `0`; o autor viu os itens sumirem.
  Que o toque não faz nada com o modo desligado é o teste "with hands-free
  off the toggle does nothing" (L325), e a guarda está em `Latch.handle`
  (`HotkeyMonitor.swift` L132). A volta dos itens ao religar não foi
  observada ao vivo: a tecla continua em disco (`54`) e no monitor, e o
  submenu se remonta ao abrir, então é construção, com confiança média.
- [x] **5. Craftsmanship gate.** `git diff HEAD`: 0 travessão ou aspas curvas
  em linha adicionada, 0 `!`, 0 `assumeIsolated` novo, 0 XCTest, 0 rede.
  `resolveStart` (L112) e `handsFreeTrigger` (L374) com doc comment dizendo o
  porquê; o `didSet` de `trigger` (L360) e o de `handsFreeTrigger` dizem o que
  aconteceria sem eles. `monitor.trigger =` continua aparecendo uma vez em
  `main.swift`.

## Pattern Compliance

- [x] **`nucleo-testavel.md`**: a tabela do toque (L187 a L208) e a regra "só
  trava o que começou" (`resolveStart` devolvendo `[.latch]`, L112) vivem na
  `Latch`, e o teste as percorre sem monitor. A coincidência vive no `didSet`
  do monitor (L360) e tem teste `@MainActor`. `press(of:in:)` (L487) é
  estático e puro. Confiança: alta.
- [x] **`isolamento-tipado.md`**: nenhum `assumeIsolated` novo; o roteamento
  dos dois gatilhos está dentro de `handle` (L514), já na main actor.
  Confiança: alta.
- [x] **`falha-alta.md`**: início recusado depois do toque não toca tom de
  trava nem mostra pill (teste L284, e `apply` aplicando o que `resolveStart`
  devolve, L528). Toda mudança da tecla vai ao log, inclusive a recusa de uma
  tecla igual ao gatilho vinda do disco (`main.swift` L598). Confiança: alta.
- [x] **`estado-consultado.md`**: o submenu se remonta ao abrir e lê
  `monitor.handsFreeTrigger` (`main.swift` L895 a L899). Confiança: alta.

## Convention Violations

Nenhuma encontrada. Achados menores, todos INFO:

- O título `Hands-free: double tap` não nomeia a segunda tecla; ela só aparece
  dentro do submenu. É o anti-escopo desta spec (título e `MenuLayout`
  intocados), e o autor notou em uso: "ainda fica escrito double tap". Fica
  como evolução: `Row.handsFree` carregando o rótulo da tecla e o título
  dizendo `Hands-free: double tap or Right ⌥`, com teste em
  `MenuLayoutTests`. Severidade: baixa. Confiança: alta.
- Ao limpar a coincidência, o `didSet` de `trigger` dispara o de
  `handsFreeTrigger`, e `resetGesture()` roda duas vezes. Inofensivo: a
  máquina de estados é reconstruída de novo, no mesmo turno. Severidade:
  nenhuma.
- A linha `ready. trigger:` do log não nomeia a tecla de mãos-livres; a
  restauração dela aparece na linha anterior. Severidade: nenhuma.
- `scripts/install.sh` ("How to use"), `CLAUDE.md` (109 testes; são 154) e a
  referência seguem para a parte 4.

## Critical Gate

Clean: no destructive operations detected. Nenhum casamento do catálogo no
diff.

## Anti-escopo e orçamento

Respeitado: sem combinação com tecla comum; `MenuLayout` e o título
intocados; `TriggerCapture.swift` e `TriggerCapturePanel.swift` intocados;
sem documentação; um só gatilho de mãos-livres, dependente do modo ligado.
Três arquivos, no orçamento de quatro.

Ready to ship.
