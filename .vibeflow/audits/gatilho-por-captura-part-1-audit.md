# Audit Report: Gatilho por captura, parte 1

> Auditado em 2026-09-03, a partir de `.vibeflow/specs/gatilho-por-captura-part-1.md`
> Diff auditado: árvore de trabalho contra `a38e3ca`, ainda sem commit

**Verdict: PASS**

## DoD Checklist

- [x] **1. `swift test` verde com as suítes movidas.** `Test run with 138 tests
  in 16 suites passed`. `Tests/NeverTypeCoreTests/HotkeyMonitorTests.swift`
  tem "Hotkey trigger" (L8) e "Hands-free latch" (L123);
  `AudioRecorderTests.swift` ficou com 3 `@Suite` (L8, L104, L295). `@Test`
  foi de 132 no HEAD para 138.
- [x] **2. Seis testes novos com os nomes da spec.** `HotkeyMonitorTests.swift`
  L58, L68, L75, L90, L104 e L111, um `@Test` cada.
- [x] **3. Botão do mouse dita de ponta a ponta.** Verificação humana, como a
  spec define. O autor rodou `defaults write com.nevertype.app trigger
  mouse:3`, relançou o app e reportou em 2026-09-03 que segurar, soltar, dois
  cliques e Esc funcionaram. O log é truncado a cada lançamento, então a
  evidência mecânica que sobrou é a do último passo (DoD 5); este check
  repousa no relato do autor. Confiança: média.
- [x] **4. Fn confirmado no teclado.** Mesma base: relato do autor, com a tecla
  🌐 em "Não Fazer Nada". Fn permanece em `Trigger.modifiers`
  (`HotkeyMonitor.swift` L204). Confiança: média.
- [x] **5. Máscaras esquerdas confirmadas.** Relato do autor para `59` (⌃
  esquerdo dita, ⌃ direito não dispara) e evidência mecânica para `55`:
  `nevertype.log` L2 `ready. trigger: Left ⌘ · hands-free: on`, L8
  `recorded: 9600 samples (0.6 s)`, L9 `transcribed in 462 ms: 9 chars`, e
  `defaults read com.nevertype.app trigger` responde `55`. Confiança: alta
  para `55`, média para `59`.
- [x] **6. Craftsmanship gate.** `git diff HEAD` sobre `Sources` e `Tests`: 0
  linhas adicionadas com travessão ou aspas curvas; 0 `!` de
  desempacotamento; 0 `assumeIsolated` novo (5 ocorrências no arquivo, as
  mesmas do HEAD); 0 XCTest; 0 rede. Doc comment em todo `public` novo:
  **corrigido nesta rodada.** A primeira passagem achou `Source`, `source`,
  `modifier(keyCode:)` e as cinco teclas novas da tabela sem doc comment
  próprio. Os quatro comentários entraram no mesmo arquivo, a suíte segue em
  138 verdes, e o da tabela registra o fato medido: lado esquerdo e Fn
  confirmados por ditado em 2026-09-03.

## Pattern Compliance

- [x] **`nucleo-testavel.md`**: `Trigger`, `named`, `mouseButton`,
  `modifier(keyCode:)` e `menuChoices` são puros e testados sem monitor
  (`HotkeyMonitorTests.swift` L8 a L120). O `NSEvent` só é lido em `handle`
  (`HotkeyMonitor.swift` L407 a L416). Confiança: alta.
- [x] **`isolamento-tipado.md`**: nenhum `assumeIsolated` novo; o caso de mouse
  entrou dentro de `handle`, já na main actor. Confiança: alta.
- [x] **`verificacao-estrutural.md`**: o teste compara `deviceMask` e `keyCode`
  por `Source` e deixa `label` fora da comparação (L21 a L30, L75 a L88); as
  máscaras foram confirmadas pelo evento real nos DoD 4 e 5. Confiança: alta.
- [x] **`falha-alta.md`**: id inválido em disco cai no padrão e a linha
  `ready. trigger:` do log diz qual valeu (`main.swift` L250, comportamento
  preservado). Confiança: alta.
- [x] **`conventions.md`, comentários**: os comentários novos explicam o porquê
  (`HotkeyMonitor.swift` L165 a L177, L206 a L213, L215 a L220, L235 a L238,
  L242 a L248, L268 a L271, L356 a L359, L408 a L412), e o da tabela traz o
  fato medido. Confiança: alta.

## Convention Violations

Nenhuma encontrada. Achados menores, todos INFO:

- `Trigger.Equatable` inclui `label`. Um `Trigger(keyCode: 54, deviceMask:
  0x0010, label: "outro")` pelo `init` público não seria igual a
  `.rightCommand`. Nenhum código constrói isso, e `named` devolve os
  estáticos. Severidade: baixa. Confiança: alta.
- `named` aceita ⇧ e ⌘ esquerdo, que a parte 2 recusa. É a Decisão 2 da spec,
  com o motivo escrito no doc de `modifiers`. Severidade: nenhuma.
- `CLAUDE.md` e `.vibeflow/index.md` ainda dizem 109 testes; são 138. Fora do
  escopo desta parte; entra na parte 4 ou num `/vibeflow:teach`.
- `scripts/install.sh`, bloco "How to use", ainda diz "Right ⌘, ⌥ or ⌃". A
  spec da parte 4 não o lista. Anotar lá.

## Critical Gate

Clean: no destructive operations detected. Os únicos casamentos do catálogo
foram a palavra `mask` (DAT105) em `HotkeyMonitor.swift` e nos testes movidos,
onde significa máscara de evento e de lado da tecla; nenhuma proteção foi
removida.

## Anti-escopo e orçamento

Respeitado: sem painel, item de menu novo ou texto de recusa; sem segundo
gatilho; sem documentação; sem `CGEventTap`, dependência SPM, clique principal
ou secundário, Caps Lock; `Latch` intocada; `all` e o padrão iguais. Quatro
arquivos, no orçamento.

Ready to ship. As pendências anotadas acima (`install.sh` e a contagem de
testes) são das partes seguintes.
