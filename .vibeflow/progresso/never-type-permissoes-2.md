# never-type-permissoes · parte 2 · executor

Estado: FEITO COM RESSALVA (05/11/2026). Falta só a conferência de fora e a auditoria, em outras sessões. Nada commitado.

Briefing: `.claude/threads/never-type-permissoes-executor-2-briefing.md` no vault. Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-pendencias`.

## Conserto 2

Estado: FEITO COM RESSALVA (05/11/2026), nada commitado; falta a reauditoria, em outra sessão. Briefing: `.claude/threads/never-type-permissoes-conserto-2-volta-2-briefing.md` no vault. Partida `eaf613a`. Varredura em `<scratchpad>/c2` (`sweep.py`, `muts.py`, `bak`, `full.jsonl`), onde `<scratchpad>` é `<rascunho da sessão>`. Vale este bloco onde ele diverge do resto do arquivo.

**O que mudou** (só `MenuLayoutTests.swift`, em `linesHidingCode` e `hidingFormsAreFound`)
* **R1:** `linesHidingCode` compara com `range(of:options: .literal)` nas quatro formas, por uma lista `tokens`. O comentário diz o porquê, com os 310 testes verdes da reauditoria. Fontes novas com `/*` seguido de `\u{0301}` e com `\u{0600}` antes do `/*`, escritas como escape.
* **R2:** fonte nova `private func keep() {} /*`.
* **Não consertados, como manda o briefing:** N-DECOY-SPACE e N-DECOY-COMMENTED, da família do A3.

**Vermelho e verde**
* Vermelho, com o filtro antigo: `swift test --filter MenuLayoutTests`, 43 testes, **falhou com 2 issues**, as fontes de U+0301 e U+0600. A fonte do R2 passa com `contains`, como esperado: ela só morde na mutação.
* Verde, depois do conserto: o mesmo filtro, **43 testes, passou**.

**Mutações, suíte inteira, uma por vez, volta por cópia com sha conferido** (`python3 -I <scratchpad>/c2/sweep.py <scratchpad>/c2/full.jsonl`, 40 mutações, todas com build verde e 310 testes na contagem)

| grupo | resultado | quem pegou |
|---|---|---|
| as 26 do conserto 1 (R-*, RR-EXACTHITS, RR-NOWHOLE, Y-*, F-RAW, B6-BF; RR-NOIF, RR-NOREGEX, RR-NOBLOCK, RR-NOTRIPLE e RR-PREFIX reescritas para a lista `tokens`) | **26 de 26 mortas** | os mesmos testes da tabela do conserto 1 |
| R1: N-COMBLAUNCH, N-COMBMENU, N-PREPMENU2 | **mortas**, antes sobreviviam | `noCodeHiddenFromTheOracles` |
| R2: RR-BLOCKPREFIX | **morta**, antes sobrevivia | `hidingFormsAreFound` |
| RR-REGEXPREFIX, RR-TRIPLEPREFIX | mortas | `hidingFormsAreFound` |
| volta a `contains`: RR-ALLCHARS (as quatro), RR-BLOCKCHARS (só `/*`) | mortas | `hidingFormsAreFound` |
| volta a `contains` em uma forma só: RR-IFCHARS, RR-REGEXCHARS, RR-TRIPLECHARS | **sobrevivem** | ver a ressalva |
| N-SEMIBLOCK, N-TABIF, N-HASH2REGEX2 | mortas | `noCodeHiddenFromTheOracles` |

**Ressalva: a comparação literal de `#if`, `#/` e `"""` não está presa por teste.** RR-IFCHARS, RR-REGEXCHARS e RR-TRIPLECHARS sobrevivem porque o briefing pede fontes só de `/*`. Não acrescentei outras: nenhuma forma com marca colada a esses três tokens compila, então uma fonte dessas prenderia uma linha que o `main.swift` não consegue ter. Medido agora, `python3 -I <scratchpad>/reaudit1/contains/forms.py`: todas as formas coladas a `#if`, `#/` e `"""` dão erro de compilação. A única além de `/*` que compila é `private let keep\u{0600} = 0; #if false`, em que a marca fica colada a `keep`, não ao `#if`, e o filtro acha o `#if`. A prova cobre as 11 formas do script, não toda forma possível. A reauditoria decide se isso conta.

**Sonda presa à forma:** nenhuma sonda da suíte quebrou. As RR-* e SK-* de `c1/muts.py` e `reaudit1/muts.py` procuram o filtro antigo e não se aplicam mais; a reauditoria usa as de `c2/muts.py`. As N-* e as demais seguem valendo.

**Prova final, uma vez, no estado entregue**
* `swift build`: Build complete.
* `swift test`: **310 testes em 33 suítes, passou**, 13,8 s (saída do XCTest: 0 testes, como sempre). A contagem é por função: as três fontes novas são casos do mesmo teste.
* `swift build --build-tests --scratch-path <scratchpad>/c2/clean` e `python3 scripts/count-swift-warnings.py <scratchpad>/c2/clean.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `grep -cE '#if|#/|/\*|"""' Sources/NeverType/main.swift`: 0.
* Nas 13 linhas adicionadas em `Tests` contra `eaf613a`: 0 travessão ou aspas curvas e 0 caractere invisível cru (contagem por categoria Unicode, Mn e Cf).
* `git diff eaf613a -- Tests Sources scripts docs`: só `MenuLayoutTests.swift`, só as duas funções.
* `shasum` depois da varredura: `main.swift` 252dc4ff, `Permissions.swift` b313bccb, `MenuLayoutTests.swift` f814ae88, iguais ao backup.
* `git status --short`: `MenuLayoutTests.swift`, este progresso e `models`, que continua fora.

## Conserto 1

Estado: FEITO (05/11/2026), nada commitado; falta a reauditoria, em outra sessão. Briefing: `.claude/threads/never-type-permissoes-conserto-2-briefing.md` no vault. Partida `44fd09c`. Varredura em `<scratchpad>/../c1` (`sweep.py`, `muts.py`, `bak`, `full.jsonl`). Vale este bloco onde ele diverge do resto do arquivo.

**O que mudou**
* **A1 e A6 (`MenuLayoutTests.swift`):** o filtro saiu do teste para `linesHidingCode(in:)`, que recusa linha com `#if`, `#/`, `/*` ou `"""` em qualquer ponto. Controle positivo: `hidingFormsAreFound` (8 fontes, entre elas `; #if` e form feed antes do `#if`) e `cleanSourceHidesNothing`. `noCodeHiddenFromTheOracles` continua lendo o `main.swift` real, e o nome dele agora cita o literal de regex.
* **A2 (`MenuLayoutTests.swift`):** `body(of:)` conta por `contains` e exige que o acerto, aparado, seja o marcador. Fonte dessa forma nova em `bodyHoldsItsEdges` (8 fontes).
* **A4 (`docs/pitfalls.md`):** a frase diz as duas formas medidas, 4 min 11 s em 16/10 e, em 05/11, 65,7 s sob pseudoterminal e nada por pipe. Título e regra iguais. "One run each way" fica escrito, para não generalizar a amostra.
* **A5:** comentários de `MicrophoneRequest` e `askAgain` (`Permissions.swift`) e de `showMicrophoneWaitingAlert` (`main.swift`). `git diff -U0 -- Sources` mostra só linhas `///`.
* **Poda:** `answerFromBackgroundQueue`, a classe `Calls` (sem outro uso, `grep`) e o `MARK` que só servia a eles saíram de `PermissionsPart1AuditTests.swift`. As outras sondas não mudaram.
* **Não consertados, como manda o briefing:** A3 e o cenário 1, que fica para o teste manual do Pedro.
* **Decisão:** a condição do A2 ficou `hits.count == 1, hits.allSatisfy(...)`, a forma escrita no briefing. Com um acerto só, equivale a olhar `hits[0]`.

**Vermelho e verde dos controles**
* Vermelho, com o filtro e o `body(of:)` antigos: `swift test --filter MenuLayoutTests`, 43 testes, **falhou com 4 issues**: as fontes de `;`, form feed e `#/` em `hidingFormsAreFound`, e a fonte nova em `bodyHoldsItsEdges`.
* Verde, depois do conserto: `swift test --filter "MenuLayoutTests|PermissionsPart1AuditTests"`, **50 testes em 2 suítes, passou**.

**Mutações, suíte inteira, uma por vez, volta por cópia com sha conferido** (`python3 -I <scratchpad>/../c1/sweep.py <scratchpad>/../c1/full.jsonl`, 26 de 26 mortas, todas com build verde e 310 testes na contagem)

| id | quem pegou |
|---|---|
| R-SEMIIF, R-FORMFEED, R-REGEX2 | `noCodeHiddenFromTheOracles` |
| R-DECOY | `menuNeedsUpdateWiring` |
| RR-NOIF, RR-NOBLOCK, RR-NOTRIPLE, e as novas RR-NOREGEX e RR-PREFIX (o `hasPrefix` antigo) | `hidingFormsAreFound` |
| RR-EXACTHITS (a contagem por linha exata, a régua antiga do A2) | `bodyHoldsItsEdges` |
| RR-NOWHOLE (sem exigir a linha inteira) | `bodyHoldsItsEdges`, `aPartialMarkerIsNotFound` |
| Y-ML1, Y-ML2 | `launchWiring`, `permissionLineWiring`, `undeterminedMicrophoneWiring` |
| Y-PP1, F-RAW, B6-BF | `noCodeHiddenFromTheOracles` |
| Y-ML3, Y-ML4 | `menuPermissionConditionsWiring` |
| Y-ML5, Y-ML6 | `menuItemsWiring` |
| Y-ML7, Y-ML8 | `permissionWatchWiring` |
| Y-ML9 | `triggerWiring`, `undeterminedMicrophoneWiring` |
| Y-ML10 | `accessibilityWarningWiring` |
| Y-MU1, Y-MU2 | `menuNeedsUpdateWiring` |

O script registra o título de cada teste; os nomes de função acima foram associados pelo título. RR-* foram reescritas para a forma nova do filtro, porque as do auditor procuram o texto antigo. As demais são as formas do auditor e do executor, sem mudança.

**Prova final, uma vez, no estado entregue**
* `swift build`: Build complete.
* `swift test`: **310 testes em 33 suítes, passou**, 14,2 s (309 menos a sonda podada, mais os 2 testes novos; saída do XCTest: 0 testes, como sempre).
* `swift build --build-tests --scratch-path <scratchpad>/../c1/clean` e `python3 scripts/count-swift-warnings.py <scratchpad>/../c1/clean.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `grep -cE '#if|#/|/\*|"""' Sources/NeverType/main.swift`: 0.
* `git diff -U0 | grep "^+" | grep -cE` de travessão e aspas curvas: 0.
* `shasum` depois da varredura: `main.swift` 252dc4ff, `Permissions.swift` b313bccb, `MenuLayoutTests.swift` 1d3200cf, iguais ao backup. `PermissionsPart1bAuditTests.swift` b05faa3d e `PermissionsPart2AuditTests.swift` 24e6a9bf, sem mudança. `PermissionsPart1AuditTests.swift` agora 64543f67, `docs/pitfalls.md` 0cf2fee2.
* `git status --short`: os cinco arquivos do perímetro, este progresso e `models`, que continua fora.

**Sonda presa à forma:** nenhuma quebrou. As RR-* do `audit2/muts.py` não se aplicam mais, porque procuram o filtro antigo; a reauditoria usa as de `c1/muts.py`.
**Não rodei** `scripts/test-count-swift-warnings.py`, `checa-sondas.py` nem `bash -n`: o briefing não pede, e nenhum script mudou.

## Marco final: dois ajustes pedidos pelo PG, antes da auditoria

O perímetro passou a incluir o comentário de `askAgainForMicrophone`. Vale este bloco onde ele diverge do resto do arquivo; os números abaixo dele são da rodada anterior.

* **`"""`:** `noCodeHiddenFromTheOracles` recusa também linha com `"""`. O nome do teste citava só `#if` e comentário de bloco e ficaria falso, então ganhou "no multi-line string"; a mensagem seguia verdadeira e não mudou.
* **F-RAW (a função inteira dentro de `#"""`):** sobrevivia à suíte inteira, 305 testes (`full.jsonl`). Agora **morta na suíte inteira** (`SWEEP_FILTER=.`, `full2.jsonl`), em `noCodeHiddenFromTheOracles`.
* **Comentário em `main.swift` 891 a 894:** diz também o pedido que volta sem resposta, sem repetir a regra do Core.
* **Varredura inteira de novo no estado novo** (`depois2.jsonl`, backup `bak2`, `main.swift` 6e49d4ba, `Permissions.swift` 80bf6977): as 13 mortas, Y-AC1 sem build, as 7 do N3 mortas, V3 morta, B6 (as três formas) vermelhas, F-RAW morta. Na sonda `answerFromBackgroundQueue`: S5 passa em 0,5 s; sem o pedido e com o pedido duplo, falha em 0,5 s. F-STR, F-OBJC e F-UNAV seguem sem build.
* **Decisão do PG sobre a ressalva do aviso:** fica como está. O efeito é a releitura pelo menu começar depois do clique no OK.

Placar final, no estado entregue:
* `swift build`: Build complete.
* `swift test`: **305 testes em 32 suítes, passou**, 16,0 s.
* `swift build --build-tests --scratch-path <scratchpad>/clean2` e `python3 scripts/count-swift-warnings.py <scratchpad>/clean2.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `grep -cE "#if|/\*|\"\"\"" Sources/NeverType/main.swift`: 0.
* Sondas sem alteração: d0eca29d e b05faa3d.

## O que mudou

* **Item 1 (`MenuLayoutTests.swift`):** `body(of:in:)` agora exige a linha do marcador, aparada, igual ao marcador; marcador que contém `func ` tem de terminar numa linha que, aparada, é exatamente `}`. O marcador parcial da linha 282 virou a linha inteira. Teste novo `noCodeHiddenFromTheOracles`: nenhuma linha que, aparada, começa com `#if`, e nenhuma linha com `/*`. Testes da régua: `bodyHoldsItsEdges` (7 fontes), `aPartialMarkerIsNotFound`, `onlyFunctionsEndOnABrace`.
* **Decisão, marcador de `case` e de `lazy var`:** terminam na próxima linha do mesmo nível, como hoje, porque não têm `}` próprio. A distinção é `marker.contains("func ")`, a forma mais simples. `body(of:in:)` passou a lançar um erro próprio (`BodyNotFound`) em vez de `#require`, para o teste poder esperar a recusa sem registrar issue.
* **Item 2, B11:** `menuNeedsUpdateWiring` prende o corpo inteiro: `["rebuildMenu()"]`.
* **Item 3, N3 (`Permissions.swift`, `main.swift`):** `askAgain` ganhou `microphone: () -> MicrophoneAccess`, sem valor padrão, lido depois de o pedido voltar. Ainda `notDetermined` e sem aviso dado pela espera: `onNoAnswer` na hora. A marca é a propriedade privada `alertedByTheWait`, na main actor, em vez de `var` local capturada pela `Task`, para não depender da análise de captura do Swift 6.0.3. `askAgainForMicrophone` passa `{ MicrophoneAccess.current }`, preso em `askAgainWiring`. Textos em `docs/reference.md`, `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md`, espelhados. O texto do aviso não mudou.
* **Item 4, L3 (`install.sh`):** a ordem real e o plano B do microfone, só texto.
* **Item 5, N4 (`verify-install.sh`):** quebra em até 80, sem mudar palavra.
* **Item 6 (`docs/pitfalls.md`):** entrada nova em "Concurrency the compiler does not see". Números conferidos na fonte: 4 min 11 s, `kill` e sem issue de limite em `progresso/never-type-permissoes-1.md` 69 e 131; 10 min em `audits/never-type-permissoes-1-audit.md` 59 (L4, com data de 15/10 no cabeçalho); 0,71 s em `audits/never-type-permissoes-1-reaudit-1.md` 37 (S5).

## N3: vermelho e verde

* Esboço: parâmetro `microphone:` aceito e ignorado, comportamento de hoje.
* Vermelho: `swift test --skip-build --filter "PermissionsTests|MenuLayoutTests"`, 47 testes em 2 suítes, **falhou com 4 issues**: `comingBackUnansweredAlertsAtOnce` e `returningAtOnceUnansweredAlerts`, `(prompt.alerts → 0) == 1`, duas vezes cada.
* Verde: o mesmo filtro, depois do código e do aperto, **52 testes em 2 suítes, passou**.
* Os quatro casos, sem relógio: volta sem resposta (`comingBackUnansweredAlertsAtOnce`, `returningAtOnceUnansweredAlerts`); volta respondido (`answerWithinTheWaitIsSilent`, com autorizado, negado e restrito, a leitura muda só com a resposta); espera disparou antes de voltar (`noAnswerWithinTheWaitAlerts`, a leitura segue sem resposta e continua um aviso só); pedido em andamento (`askingAgainWhilePendingAlertsAtOnce`).

## Mutações

`<scratchpad>` é `<rascunho da sessão>/p2`. Varredura em `sweep.py`, mutações em `muts.py`, um a um, troca exata com contagem 1, build verde para a morte contar, teste nomeado, volta por cópia com sha conferido. Filtro: as seis suítes da parte. Saídas `antes.jsonl` (`bak0`, código e testes de partida) e `depois.jsonl` (`bak1`, estado entregue, `main.swift` f166ecea, `Permissions.swift` 80bf6977).

A contagem do briefing: as 13 da tabela da reauditoria 3 já incluem Y-MU1 e Y-MU2 (11 da classe mais 2 do B11, "13 sobreviventes" na linha 112 do relatório). São 13 no total, não 15.

| id | função | antes | depois | quem pegou |
|---|---|---|---|---|
| Y-ML1 | `applicationDidFinishLaunching` | sobrevive | morta | `launchWiring`, `permissionLineWiring`, `undeterminedMicrophoneWiring` |
| Y-ML2 | `applicationDidFinishLaunching` | sobrevive | morta | os mesmos três |
| Y-PP1 | `applicationDidFinishLaunching` | sobrevive | morta | `noCodeHiddenFromTheOracles` |
| Y-ML3 | `rebuildMenu` | sobrevive | morta | `menuPermissionConditionsWiring` |
| Y-ML4 | `rebuildMenu` | sobrevive | morta | `menuPermissionConditionsWiring` |
| Y-ML5 | `item(for:)` | sobrevive | morta | `menuItemsWiring` |
| Y-ML6 | `item(for:)` | sobrevive | morta | `menuItemsWiring` |
| Y-ML7 | `renderResting` | sobrevive | morta | `permissionWatchWiring` |
| Y-ML8 | `permissionsChanged` | sobrevive | morta | `permissionWatchWiring` |
| Y-ML9 | `handle` | sobrevive | morta | `triggerWiring`, `undeterminedMicrophoneWiring` |
| Y-ML10 | `showAccessibilityRequiredAlert` | sobrevive | morta | `accessibilityWarningWiring` |
| Y-MU1 | `menuNeedsUpdate` | sobrevive | morta | `menuNeedsUpdateWiring` |
| Y-MU2 | `menuNeedsUpdate` | sobrevive | morta | `menuNeedsUpdateWiring` |
| Y-AC1 | `private` na abertura | sem build | sem build | sai da conta |

**13 de 13 mortas, 0 sobreviventes.**

As do N3, no estado entregue:

| id | mutação | resultado | quem pegou |
|---|---|---|---|
| N3-NOCHECK | sem a leitura depois do pedido | morta | `comingBackUnansweredAlertsAtOnce`, `returningAtOnceUnansweredAlerts` |
| N3-NOGUARD | sem conferir o aviso da espera | morta | `noAnswerWithinTheWaitAlerts` |
| N3-NOFLAG | a espera não marca o aviso | morta | `noAnswerWithinTheWaitAlerts` |
| N3-ANY | avisa qualquer que seja a leitura | morta | `answerWithinTheWaitIsSilent` |
| N3-EARLY | lê antes do pedido | morta | `answerWithinTheWaitIsSilent` |
| N3-W1 | `microphone: { .notDetermined }` no app | morta | `askAgainWiring` |
| N3-W2 | `microphone: { .authorized }` no app | morta | `askAgainWiring` |

## As três medições do item 7

Mutação nenhuma ficou aplicada; `main.swift` e `Permissions.swift` conferidos por sha depois de cada uma.

1. **V3 (`wait: { }` em `askAgainForMicrophone`):** morta em `askAgainWiring`, no código de partida e no entregue. A leitura do Pedro estava certa, nenhum oráculo novo foi preciso.
2. **`answerFromBackgroundQueue` (só essa sonda, código de partida, uma execução cada):** nenhuma forma travou.

   | forma | resultado | tempo do processo | tempo informado pelo swift-testing |
   |---|---|---|---|
   | S5, pede de novo negado e restrito (`!= .authorized`) | **passa** | 0,5 s | 0,001 s |
   | sem chamar `requestMicrophone` | falha | 0,5 s | 0,001 s |
   | chama duas vezes | falha | 0,7 s | 0,001 s |

   O S5 passa porque a sonda só lê `.notDetermined`, onde a condição sabotada dá o mesmo resultado. Quem mata o S5 é `answeredMicrophoneIsNotAsked`, em `PermissionsTests` (medido na reauditoria 1 da parte 1, não aqui). No estado entregue, o mesmo resultado: passa em 0,5 s, falha em 0,5 s e em 0,6 s.
3. **B6:**
   * `render(visual) // x` em `renderResting`: vermelho em `permissionWatchWiring`, antes e depois do item 1.
   * Comentário de bloco em volta de `render(visual)`, em linhas próprias: vermelho em `permissionWatchWiring` antes e depois; depois, também em `noCodeHiddenFromTheOracles`.
   * Forma a mais, a função inteira dentro de `/*`: **sobrevivia** antes do item 1 e agora morre em `noCodeHiddenFromTheOracles`.

## Comandos de prova (uma vez, no fim)

* `swift build`: Build complete.
* `swift test`: **305 testes em 32 suítes, passou**, 15,6 s (saída do XCTest: 0 testes, como sempre neste repositório).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* `swift build --build-tests --scratch-path <scratchpad>/clean` e `python3 scripts/count-swift-warnings.py <scratchpad>/clean.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `bash -n scripts/install.sh` e `bash -n scripts/verify-install.sh`: sem erro.
* Largura por `awk`, `verify-install.sh` 199 a 206: máximo 78. `install.sh` 120 a 137: o `awk` deste Mac mede bytes e acusa só a linha 137 com 81, que é a linha antiga "System Settings › Privacy…", não mudada, com dois `›` de 3 bytes. Em caracteres, medido por Python: máximo 80 no bloco, e essa linha tem 77.
* `git diff --word-diff=porcelain scripts/verify-install.sh`: nenhuma palavra adicionada nem removida.
* Sondas sem alteração: `PermissionsPart1AuditTests.swift` d0eca29d e `PermissionsPart1bAuditTests.swift` b05faa3d, iguais à partida, e verdes dentro da suíte.
* Contagem de travessão e de aspas curvas nas linhas adicionadas, por `grep -cE`: 0.
* `git diff --stat`: 10 arquivos, todos no perímetro. `git status --short` mostra só eles, este progresso e `models`, como novos.

## Ressalvas

* **O aviso do N3 segura o resto de `askAgainForMicrophone` até o OK.** `onNoAnswer` roda dentro de `askAgain`, e `runModal` só devolve com o clique; `renderResting`, a linha `permissions:` e `permissionWatch.start()` vêm depois dele. Pelo gatilho, o ícone e a releitura já estão de pé antes. Pelo item do menu, a releitura só começa depois do OK. É consequência de o aviso rodar na hora, dentro de `askAgain`, e o efeito real só o Mac mostra: o passo manual é do Pedro.
* O N3 continua sem mecanismo conhecido no build atual; a prova é só do Core, como o briefing prevê.

## Fora da parte

* Três formas de borda não compilam, então não são buraco: a string de várias linhas sem `#` (`cannot find 'status' in scope`), `@objc(renamedLaunch:)` acima da abertura e `@available(macOS, obsoleted: 1.0)` acima de `renderResting`. A forma com `#"""` entrou na parte (marco final).

## Para retomar

`cd ~/Projects/apps/never-type-permissoes && python3 -I <scratchpad>/sweep.py <scratchpad>/bak2 <saida>.jsonl all [ids]` (`SWEEP_FILTER=.` roda a suíte inteira).
