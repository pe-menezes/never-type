# never-type-permissoes · parte 1b · progresso do executor

Briefing: vault `.claude/threads/never-type-permissoes-executor-1b-briefing.md`. Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-icone`, base `e2fa8bb`.

## Marco 0: leitura (16/10)
* Lidos: briefing, `CLAUDE.md`, `.vibeflow/index.md`, `conventions.md`, padrões `estado-consultado`, `nucleo-testavel`, `verificacao-estrutural`, `isolamento-tipado`, `docs/pitfalls.md` (closure que herda o `@MainActor`), L6 da auditoria e N2 da reauditoria da parte 1, progresso da parte 1, dev-remoto princípios 1, 3, 4 e 6.
* `git status --short` (16/10): só `?? models`. `git log -1`: `e2fa8bb`.
* Plano:
  * `Sources/NeverTypeCore/StatusIcon.swift` (novo): `PermissionReading` (as duas leituras, `isComplete`, `current` do sistema), `ModelState` (`loading`, `ready`, `notLoaded`, `noMetal`), `StatusIcon.resting(permissions:model:)` devolve `.normal` ou `.slashed`, e `PermissionWatch` (`@MainActor`, relê a cada `interval`, recebido por parâmetro, padrão um segundo; entrega cada mudança uma vez; para sozinho com as duas concedidas; não começa sem permissão faltando).
  * `main.swift`: `modelState` guardado pela `Task` do `prepare`; `renderResting()` desenha pela regra; `askAgainForMicrophone` e o fim da abertura usam `renderResting()` (L6); `permissionWatch.start()` no fim da abertura, a cada gatilho e depois do pedido de novo; a mudança escreve a linha `permissions:` e redesenha.
  * `MenuLayoutTests`: `body(of:in:)` ignora linha comentada (N2), com teste próprio; oráculo novo da ligação.

## Falta
* Nada desta parte. Conferência de fora, auditoria e o teste manual do Pedro (abaixo).

## Marco 1: vermelho (16/10)
* Esboço com o comportamento de hoje em `Sources/NeverTypeCore/StatusIcon.swift` (novo): `StatusIcon.resting` olha só o microfone (o que `askAgainForMicrophone` faz hoje), `PermissionWatch.start()` não faz nada (ninguém relê hoje). `main.swift` intocado.
* Testes novos: `Tests/NeverTypeCoreTests/StatusIconTests.swift` (regra do ícone: concedidas com modelo pronto ou carregando dão normal; modelo falho e sem Metal seguem riscados; qualquer permissão faltando risca, com os quatro estados do modelo; releitura: para quando as duas são concedidas e não abre outro intervalo; não começa com nada faltando; cada mudança chega uma vez e leitura igual nunca, `start()` duas vezes não abre dois laços; reinicia depois de parar). O intervalo é uma continuação que o teste encerra, sem relógio; todo teste que deixa a releitura viva termina o intervalo com as duas concedidas (lição L4 da parte 1).
* `MenuLayoutTests`: `permissionWatchWiring` (oráculo da ligação) e `bodyIgnoresComments` (N2).
* `swift build --build-tests` ok; `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests"`: **35 testes em 2 suítes, 12 issues, falhou**; 7 testes vermelhos: as três da regra (`.normal` em vez de `.slashed` com modelo falho e com Acessibilidade faltando), `bodyIgnoresComments` (`hits.count → 2`), `permissionWatchWiring`, e três da releitura (`stopsWhenGranted`, `eachChangeOnce`, `startsAgainAfterStopping`). `doesNotStartWhenGranted` passa no esboço, como deve (o esboço nunca começa).

## Marco 2: verde (16/10)
* `StatusIcon.swift`: `PermissionReading` (`isComplete`, `current` `@MainActor` lendo `MicrophoneAccess.current` e `HotkeyMonitor.hasAccessibilityPermission`), `ModelState`, `StatusIcon.resting` (permissão faltando risca; com as duas, `notLoaded` e `noMetal` riscam, `loading` e `ready` não), `PermissionWatch` (`@MainActor`; `start()` lê, não começa sem nada faltando nem com laço já vivo; a cada `interval` relê, entrega a leitura só quando muda, e para na leitura completa, depois de entregá-la; `oneSecond` de padrão).
* `main.swift`: `permissionWatch` (lazy, `read: { PermissionReading.current }`, `onChange` para `permissionsChanged`), `modelState` gravado na `Task` do `prepare` (`.ready`, `.noMetal`, `.notLoaded`); `permissionsChanged` escreve a linha `permissions:` e redesenha por `renderResting`, fora de gravação e transcrição; `renderResting` desenha por `StatusIcon.resting`. Abertura: `if !self.micAuthorized { self.render(.blocked) }` virou `self.renderResting()`, e `permissionWatch.start()` depois dos pedidos (ordem dos pedidos intacta, `LaunchPermissions.run` não mudou). Gatilho: `permissionWatch.start()` logo depois da linha `permissions:`. `askAgainForMicrophone`: `renderResting()` no lugar do `.idle` com microfone autorizado (L6) e `permissionWatch.start()`. Doc de `logPermissionsIfChanged` atualizado.
* `MenuLayoutTests.body(of:in:)`: descarta linha que é só comentário antes de procurar o marcador e o corpo (N2).
* Docs: `docs/reference.md` (parágrafo do ícone riscado sob as linhas de permissão; "Granting a permission does not clear this slash." no parágrafo das falhas de abertura); INSTALL nos dois idiomas, só a frase do ícone no passo da Acessibilidade.
* `swift build --build-tests` sem erro; `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests"`: **63 testes em 5 suítes, passou**.

## Marco 3: prova final (16/10)
* `swift build && swift test`: exit 0, **279 testes em 31 suítes, passou** (268 da parte 1 mais 11 novos; pulos são as suítes condicionais de sempre).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Build limpo `swift build --build-tests --scratch-path <scratchpad>/build-1b` (exit 0) + `python3 scripts/count-swift-warnings.py <log>`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29, 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* Travessão e aspas curvas: nenhum nas linhas adicionadas nem nos arquivos novos (`git diff -U0 | grep '^+'` e `cat` dos novos, `grep -E "—|–|“|”|‘|’"`, vazio).
* `git status --short`: `main.swift`, `MenuLayoutTests.swift`, `docs/INSTALL.md`, `docs/INSTALL.pt-BR.md`, `docs/reference.md` modificados; novos `StatusIcon.swift`, `StatusIconTests.swift`, este progresso; `?? models`. Nada fora do perímetro; sondas de `Tests/NeverTypeCoreTests/Audit/` intocadas e verdes.

## Decisões
* Quem para a releitura é o Core: `PermissionWatch` para sozinho na leitura completa, depois de entregá-la, e é isso que o teste `stopsWhenGranted` prova. O `main.swift` não tem `stop`; o oráculo prende o que é do app: começar (depois dos pedidos da abertura, no gatilho e depois do pedido de novo), ler do sistema (`PermissionReading.current`), o intervalo de padrão (sem `interval:`), escrever a linha `permissions:` e redesenhar pela regra.
* `start()` em todo lugar que acha permissão faltando, e não só na abertura: permissão tirada nos Ajustes depois da releitura parar volta a ser vigiada no gatilho seguinte (`startsAgainAfterStopping`). `start()` é idempotente e custa uma leitura.
* Modelo carregando não risca (é como a abertura sempre ficou). A `Task` do `prepare` grava `modelState` e mantém o `render(.blocked)` direto nos dois casos de falha, que dá o mesmo resultado da regra.
* A mudança vinda da releitura não redesenha durante gravação ou transcrição: o ícone ali diz gravando, e o fim do ditado redesenha. A linha `permissions:` sai mesmo assim.
* `PermissionWatch` guarda a última leitura entregue, só para distinguir mudança de repetição; não decide nada com ela, como o `PermissionLog`. A linha do log continua deduplicada pelo `PermissionLog`.
* `body(of:in:)` descarta linhas que são só comentário (`//` e `///`) antes de procurar marcador e corpo. Os oráculos que já existiam continuam verdes.
* `micAuthorized` ficou sem uso no `main.swift` e não saiu: o padrão `.vibeflow/patterns/estado-consultado.md` o cita como exemplo.

## Fora da parte
* Mesma família do L6, fora desta decisão: `render(.idle)` no fim do ditado (`.released`), no `discardRecording` e no `flashIdle` depois de 2 s ainda desenha o ícone normal sem olhar o modelo, e apaga o risco de modelo ou Metal. Seria trocar por `renderResting()`.
* O risco de `recorder.onError` não é de permissão nem de modelo; se uma permissão mudar depois dele, a releitura redesenha pela regra e o tira.
* `body(of:in:)` ainda aceita comentário de bloco (`/* */`) e comentário no fim da linha depois do código.
* `AVCaptureDevice.authorizationStatus` pode não mudar dentro do processo depois de ligar o microfone nos Ajustes; o macOS oferece "Quit & Reopen" nesse caso (vídeo 2 do Pedro), então o caminho medido é o da Acessibilidade.
* Teste manual do Pedro (TCC real fora dos testes): (1) Acessibilidade desligada, abrir o app, ligar nos Ajustes: o ícone deixa de ser riscado em cerca de um segundo, sem gatilho, e o `nevertype.log` ganha `permissions: microphone=authorized accessibility=granted` e `icon → idle`; (2) depois disso, nenhuma linha nova por segundo no log (a releitura parou); (3) com o modelo ausente, o mesmo passo deixa o ícone riscado.
* Já fora pelo briefing: o -600 do `killall NeverType; open …` e a janela de primeira abertura (parte 2).

## Comandos de prova
* `cd ~/Projects/apps/never-type-permissoes && swift test --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests"`
* `cd ~/Projects/apps/never-type-permissoes && swift build && swift test`
* `cd ~/Projects/apps/never-type-permissoes && python3 scripts/test-count-swift-warnings.py`
* `cd ~/Projects/apps/never-type-permissoes && swift build --build-tests --scratch-path <tmp>/build > <tmp>/build.log 2>&1; python3 scripts/count-swift-warnings.py <tmp>/build.log`

## Estado: FEITO (o teste manual do TCC é do Pedro)

---

## Conserto 1 (16/10)
Briefing: vault `.claude/threads/never-type-permissoes-conserto-1b-briefing.md`. Achados do relatório `.vibeflow/audits/never-type-permissoes-1b-audit.md`: A1 e B5. B1, B2, B3, B4 e B6 ficam fora (viram tarefa).

### Marco C0: leitura
* Lidos: briefing do conserto, relatório da auditoria, este progresso, briefing do executor, `CLAUDE.md`, `nucleo-testavel.md`, `verificacao-estrutural.md`, `isolamento-tipado.md`, `sab.sh` e `sabs.py` do auditor.
* `git log --oneline -3`: `e6d9431`, `945bbfa`, `e2fa8bb`. `git status --short`: só `?? models`.
* Plano do A1:
  * Core (`StatusIcon.swift`): `StatusVisual` (`idle`, `recording`, `blocked`, o que o app desenha; o `Visual` privado do `main.swift` passa a ser ele), `StatusIcon.visual` (o mapeamento, M1), `ModelState(loaded:metalActive:)` (M5) e `StatusIcon.redraw(permissions:recording:transcribing:model:)`, que devolve o que desenhar ou `nil` durante ditado (M2 e o efeito do M8), cada um com teste de comportamento.
  * `main.swift`: `permissionsChanged` e o fim do carregamento do modelo chamam `redrawIfResting`, que só desenha o que o Core decidiu; `renderResting` desenha `StatusIcon.resting(...).visual`.
  * Oráculo linha a linha em `MenuLayoutTests` (molde do `expectAlert`): os corpos inteiros de `permissionsChanged`, `redrawIfResting` e `renderResting`; o `start()` dentro da `Task` das permissões, logo depois do `LaunchPermissions.run(`, uma vez só na abertura; no gatilho, as linhas do `.pressed` até o `switch DictationAttempt.decide(` exatas, com o `start()` imediatamente antes; o `modelState` gravado uma vez, pelo Core, seguido do redesenho.
* Como provo as sabotagens: o `sab.sh` do auditor restaura de `bak/` (o estado entregue), então não serve para o código novo. Uso uma cópia dele no meu scratchpad, com `bak/` tirado do meu estado final e as mutações reescritas na forma nova onde a âncora mudou.

### Marco C1: vermelho
* Esboço no Core (`ModelState(loaded:metalActive:)` devolvendo `.loading`, `StatusIcon.visual` sempre `.idle`, `StatusIcon.redraw` sempre `nil`), `main.swift` intocado.
* Testes novos em `StatusIconTests`: `restingVisual` (M1), `modelStateFromTheLoad` (M5, quatro casos), `redrawAtRest` (o caso das 08:28 e o risco do modelo, M8 e M2), `noRedrawWhileDictating` (três casos de ditado, M2).
* `MenuLayoutTests.permissionWatchWiring` reescrito linha a linha com `codeLines`: corpos inteiros de `permissionsChanged` e `renderResting`; na abertura, a `Task { @MainActor in` antes de `await LaunchPermissions.run(` e, depois do último argumento, exatamente `self.renderResting()`, `self.logPermissionsIfChanged()`, `self.permissionWatch.start()`, `}`, com um único `start()` na abertura; `modelState` gravado uma vez, por `ModelState(loaded: loaded, metalActive: metalActive)`, seguido de `self.renderResting()`; no gatilho, as linhas do `handle` até `switch DictationAttempt.decide(` exatas, com um único `start()`.
* `swift build --build-tests` ok; `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests"`: **39 testes em 2 suítes, falhou com 14 issues**: `modelStateFromTheLoad` (4), `restingVisual`, `redrawAtRest` e `permissionWatchWiring` vermelhos; `noRedrawWhileDictating` passa no esboço, como deve (o esboço nunca desenha).

### Marco C2: verde
* Core (`StatusIcon.swift`): `ModelState.init(loaded:metalActive:)`, `StatusVisual`, `StatusIcon.visual`, `StatusIcon.redraw(permissions:recording:transcribing:model:)` (nil durante ditado, senão `resting(...).visual`).
* `main.swift`: `Visual` virou `typealias` de `StatusVisual`; `renderResting` desenha só o que `StatusIcon.redraw` devolve; `permissionsChanged` perdeu a guarda (está no Core); a `Task` do modelo grava `ModelState(loaded:metalActive:)` e chama `renderResting()` (os dois `render(.blocked)` diretos saíram).
* `swift build --build-tests` sem erro; `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests|PermissionsPart1bAuditTests"`: **69 testes em 6 suítes, passou**.

### Marco C3: sabotagens do A1
* Ferramenta: cópia do `sab.sh` do auditor em `<scratchpad>/conserto1b/` (o script é o mesmo; o `bak/` é o meu estado final: `main.swift` fad16d7a, `StatusIcon.swift` b4d425d9, `MenuLayoutTests.swift` e38fdb2f), mutações em `<scratchpad>/conserto1b/sabs.py`, log em `sab.log` (0 linhas `error:`, então toda morte é teste vermelho, não compilação). Cada uma aplicada por troca exata com contagem 1 e desfeita por cópia, sha conferido.
* As seis do relatório, na forma nova. Onde a decisão saiu para o Core, a mesma mutação foi aplicada nos dois lugares: no Core (onde a decisão mora agora) e no `main.swift` (o que sobrou dela lá):

| id | forma nova | filtro | resultado |
|---|---|---|---|
| M8 | âncora original intacta: `if reading.isComplete { return }` antes de `renderResting(reading)` em `permissionsChanged` | `MenuLayoutTests` | morre |
| M8c | a mesma saída no Core: `if permissions.isComplete { return nil }` em `StatusIcon.redraw` | `StatusIconTests` | morre (`redrawAtRest`) |
| M2 | âncora mudou (a guarda saiu do `main.swift`): `recording: !recorder.isRecording` no `renderResting` | `MenuLayoutTests` | morre |
| M2c | a guarda invertida no Core: `guard recording, !transcribing` | `StatusIconTests` | morre (`redrawAtRest`, `noRedrawWhileDictating`) |
| M1 | âncora mudou (o mapeamento está no Core): `.normal` dá `.blocked` e `.slashed` dá `.idle` em `StatusIcon.visual` | `StatusIconTests` | morre (`restingVisual`, `redrawAtRest`) |
| M1m | a inversão no que sobrou do `main.swift`: `render(visual == .idle ? .blocked : .idle)` | `MenuLayoutTests` | morre |
| M5 | âncora mudou (os ramos estão no Core): `.ready` e `.noMetal` trocados em `ModelState.init(loaded:metalActive:)` | `StatusIconTests` | morre (`modelStateFromTheLoad`) |
| M5m | no `main.swift`: `ModelState(loaded: loaded, metalActive: !metalActive)` | `MenuLayoutTests` | morre |
| M10 | o ramo `.notLoaded` saiu do `main.swift`; reescrita no equivalente: `start()` sai da `Task` das permissões e entra como `if !loaded { self.permissionWatch.start() }` depois do `renderResting()` do modelo | `MenuLayoutTests` | morre |
| M11 | âncoras originais intactas: `start()` sai de antes do `switch DictationAttempt.decide(` e vai para `case .startRecording:` | `MenuLayoutTests` | morre |

* Reconfirmadas na forma nova, com as âncoras originais: M3, M4, M6, M7, M9 morrem.
* Novas, nas linhas que o conserto criou: M12 (tirar o `self.renderResting()` depois do `modelState`) e M13 (`transcribing: false` no lugar de `transcriptionSession.isTranscribing`) morrem.

### Marco C4: B5
* `docs/reference.md`, parágrafo do ícone: o "about a second ... with no key press and no relaunch" ficou só para a Acessibilidade; para o microfone, a referência diz que ligar a chave com o app aberto faz o macOS oferecer **Quit & Reopen**, e o app reaberto lê a permissão na abertura (o vídeo 2 do Pedro). Não prometi nada sobre o "Later" (passo 3 do teste manual da auditoria). INSTALL intocados.

### Marco C5: prova final
* `swift build`: exit 0. `swift test`: exit 0, **285 testes em 32 suítes, passou** (281 da auditoria mais 4 novos em `StatusIconTests`; `permissionWatchWiring` reescrito, não somado).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Build limpo `swift build --build-tests --scratch-path <scratchpad>/conserto1b/build-clean` (exit 0) + `python3 scripts/count-swift-warnings.py <log>`: **4**, a mesma lista (`AudioRecorder.swift` 1:1, 402:29, 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* Travessão e aspas curvas nas linhas adicionadas (`git diff -U0 | grep '^+'`): 0.
* `git status --short`: `main.swift`, `StatusIcon.swift`, `MenuLayoutTests.swift`, `StatusIconTests.swift`, `docs/reference.md` e este progresso modificados; `?? models`. Nada fora do perímetro; sondas de `Tests/NeverTypeCoreTests/Audit/` intocadas e verdes.

### Decisões do conserto
* `renderResting` passou a ser o único caminho do repouso e não desenha durante gravação ou transcrição (decisão do Core, `StatusIcon.redraw`). Isso muda três lugares além da releitura: o redesenho depois dos pedidos da abertura e o do `askAgainForMicrophone` não pisam mais num ícone de gravação; e o fim do carregamento do modelo, que antes desenhava `.blocked` direto até durante um ditado, agora desenha pela regra e só em repouso (com modelo pronto e as duas concedidas, desenha o normal, que já estava lá). O fim do ditado ainda desenha `.idle` direto (B3, fora desta parte), como antes.
* O `Visual` privado do `main.swift` virou `typealias` de `StatusVisual` do Core, para o mapeamento do repouso morar onde há teste; os `render(.idle)`, `render(.recording)` e `render(.blocked)` de sempre não mudaram.
* Sondas presas à forma: nenhuma das sondas da auditoria olha o `main.swift`; nada a registrar.

### Fora da parte (conserto 1)
* B1, B2, B3, B4 e B6 seguem como o relatório pede (tarefa; B2 e B4 pelo teste manual). O B3 continua aberto: com a regra agora em `renderResting`, o conserto do B3 é trocar os três `render(.idle)` por `renderResting()`.
* O passo 3 do teste manual da auditoria ("Later" no Quit & Reopen) decide se a referência pode dizer mais sobre o microfone; hoje ela diz só o que o vídeo mostrou.

### Comandos de prova (conserto 1)
* `cd ~/Projects/apps/never-type-permissoes && swift test --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests|PermissionsPart1bAuditTests"`
* `bash <scratchpad>/conserto1b/sab.sh <id>` para M8, M8c, M2, M2c, M1, M1m, M5, M5m, M10, M11 (e M3, M4, M6, M7, M9, M12, M13)
* `cd ~/Projects/apps/never-type-permissoes && swift build && swift test`
* `cd ~/Projects/apps/never-type-permissoes && python3 scripts/test-count-swift-warnings.py`

## Estado do conserto 1: FEITO (o teste manual do TCC segue com o Pedro)

---

## Conserto 2 (16/10)
Briefing: vault `.claude/threads/never-type-permissoes-conserto-2-1b-briefing.md`. Achados: A2 e a classe dele (reauditoria `never-type-permissoes-1b-reaudit-1.md`), B7 (comentário de `StatusIcon.redraw`). B1, B3, B4 e B6 ficam fora (tarefa). Volta 2 de 2.

### Marco D0: leitura (09:26)
* Lidos: briefing do conserto 2, reauditoria e auditoria da 1b, tabelas de sabotagem da parte 1 (auditoria, reauditoria e progresso da parte 1, onde estão D1c, D1e e D1f), este progresso (conserto 1), briefing do conserto 1, `CLAUDE.md`, `nucleo-testavel.md`, `verificacao-estrutural.md`, dev-remoto princípios 1, 6 e 7.
* `git log --oneline -3`: `bbfec96`, `3e87fb4`, `e6d9431`. `git status --short`: só `?? models`. Shas iguais aos da reauditoria (`main.swift` fad16d7a, `StatusIcon.swift` b4d425d9, `MenuLayoutTests.swift` e38fdb2f, `StatusIconTests.swift` f9c39d90). Cópia do estado de partida em `<scratchpad>/conserto2-1b/bak0/` (mais `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da, `MenuLayout.swift` 1c7a6dec).
* Plano:
  * A2 sai para o Core: `ModelState.afterLoad(loaded:devices:metalActive:log:)`, `@MainActor`, recebe as leituras como chamadas e só consulta o Metal (e a lista de devices) com o modelo carregado; escreve as duas linhas de log de hoje (`ggml devices:` e o `WARNING` sem Metal). O `main.swift` só grava o que ela devolve e redesenha. Teste de comportamento em `StatusIconTests`.
  * O resto da classe é ligação (chamar `NSAlert`, `render`, `Task`), sem decisão sobrando para o Core: o oráculo de `MenuLayoutTests` passa a prender cada ligação linha a linha, inteira (bloco das permissões na abertura, fim do modelo, gatilho do `case .pressed:` até `case .startRecording: break`, `askAgainForMicrophone`, `askForMicrophone`, `askForMicrophoneFromMenu`, `permissionsChanged`, `renderResting` com a assinatura, `logPermissionsIfChanged` com a assinatura, a propriedade `permissionWatch`, `warnIfAccessibilityMissing`, os três avisos inteiros com o portão, e as duas condições de permissão do menu).
  * `PermissionReading.current` (Core, desta frente) é a fronteira com o TCC e não se executa em teste: oráculo de texto sobre as duas leituras.
  * Varredura: `<scratchpad>/conserto2-1b/sweep.py` com as mutações em `muts.py`; cada uma por troca exata com contagem 1, `swift build --build-tests` (morte só conta com build verde), `swift test --skip-build --filter` das seis suítes da parte com `--xunit-output` para nomear o teste que pegou, desfeita por cópia de `bak/` com sha conferido. Roda duas vezes: "antes" (código e testes de partida) e "depois".

### Marco D1: varredura "antes"
* `python3 -I <scratchpad>/conserto2-1b/sweep.py antes bak0 antes.jsonl`, 101 mutações sobre o código e os testes de partida (`bak0`). Resultado completo na tabela do marco D4. Placar: 59 mortas, 41 sobreviventes, 1 sem build. Sobreviviam: M14, M15 (o A2) e mais 39 na classe, entre elas L2, L3, L5 (as leituras e o pedido da Acessibilidade na abertura), MD3, T7, T9, T10, TA1 a TA4, TR3, TW3, TM4, TS1, TS2, S17v (gatilho), AG6, AG7, AF1, RR5, LW2 a LW4, PR1, PR2, W1 a W4, G1, R1, R3, R4, R5 (avisos) e MC1m a MC4m (menu). P3 (intervalo de 60 s na propriedade) não compila e foi descartada (B1 já diz que o valor de um segundo não tem prova sem relógio).

### Marco D2: vermelho
* Esboço no Core: `ModelState.afterLoad(loaded:devices:metalActive:log:)` devolvendo `.loading` sem chamar nada. `main.swift` intocado.
* Testes novos em `StatusIconTests`: `afterLoadNotLoaded` (dois casos: `.notLoaded`, Metal e devices nunca consultados, log vazio), `afterLoadReady`, `afterLoadNoMetal` (estado, uma leitura de cada, as linhas de log exatas), e `currentReadsTheSystem` (oráculo de texto de `PermissionReading.current`).
* `MenuLayoutTests`: `permissionWatchWiring` reescrito (propriedade inteira, `permissionsChanged`, `renderResting` com a assinatura); novos `launchPermissionsWiring`, `modelLoadWiring`, `triggerWiring`, `askAgainWiring`, `permissionLineWriterWiring`, `accessibilityWarningWiring`, `menuPermissionConditionsWiring`; `expectAlert` compara o corpo inteiro linha a linha (`shown:` e `logged:` novos) e passa a valer também para o aviso da Acessibilidade.
* `swift build --build-tests` ok; `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests|PermissionsPart1bAuditTests"`: **80 testes em 6 suítes, falhou com 12 issues**; vermelhos: os três `afterLoad*` e `modelLoadWiring`. Os oráculos novos sobre ligações que já estavam certas passam no código de partida, como devem: são endurecimento, provado pela varredura (a mutação que sobrevivia no "antes" morre no "depois").

### Marco D3: verde
* `StatusIcon.swift`: `ModelState.afterLoad` (`@MainActor`; `guard await loaded() else { return .notLoaded }`, depois a linha `ggml devices:`, a leitura do Metal, o `WARNING` sem Metal, e `ModelState(loaded: true, metalActive:)`). Comentário de `StatusIcon.redraw` corrigido (B7): a gravação é redesenhada pelo `.released` com o ícone normal, fora da regra (B3), e o fim da transcrição com sucesso não redesenha (B7).
* `main.swift`: a `Task` do modelo grava `ModelState.afterLoad(...)` com as quatro chamadas do app e redesenha; o `if loaded {` e o `var metalActive` saíram. As linhas de log e a ordem delas são as mesmas de antes.
* `swift build --build-tests` sem erro; mesmo filtro: **80 testes em 6 suítes, passou**.
* Estado entregue copiado em `<scratchpad>/conserto2-1b/bak1/`: `main.swift` ca37b8f9, `StatusIcon.swift` ac60fa3e, `MenuLayoutTests.swift` 99020d81, `StatusIconTests.swift` a33cab34 (os outros três iguais ao `bak0`).

### Marco D4: varredura "depois"
* `python3 -I <scratchpad>/conserto2-1b/sweep.py depois bak1 depois.jsonl`: 110 mutações (as 101 do "antes", com as do modelo reescritas na forma nova, mais 9 que só existem na forma nova: M14c, M15c, MD4, MD5, MC1 a MC5). **109 mortas, 0 sobreviventes, 1 sem build (P3, descartada).** Toda morta tem build verde (0 `error:`) e o teste que a pegou nomeado pelo `--xunit-output`. Cada mutação aplicada por troca exata com contagem 1 e desfeita por cópia de `bak1/`, sha conferido depois de cada uma (gravado no `depois.jsonl`); no fim, os sete arquivos com o sha do `bak1`.
* M14, M14c, M15 e M15c também com a suíte inteira (`SWEEP_FILTER=.`): as quatro deixam vermelha a suíte de 296 testes em 32 suítes (`modelLoadWiring` para as duas do `main.swift`; `afterLoad*` para as duas do Core).
* Ligações: `abertura` (bloco das permissões na abertura), `modelo` (fim do carregamento), `gatilho`, `askAgain` (com `askForMicrophone` e o item do menu), `permissionsChanged`, `renderResting`, `linha permissions` (`logPermissionsIfChanged`), `releitura` (propriedade e `PermissionReading.current`), `warnIfAccessibilityMissing`, `avisos` (os três e o portão), `menu` (condições de permissão). Arquivo: `main` é `Sources/NeverType/main.swift`, `icon` é `StatusIcon.swift`, `dict` é `DictationAttempt.swift` (o `PresentationGate`), `menu` é `MenuLayout.swift`. "antes" é o código e os testes de partida (`3e87fb4` mais a reauditoria), "depois" é o entregue.

| id | ligação | arquivo | mutação | antes | depois |
|---|---|---|---|---|---|
| L1-S16 | abertura | main | sem a linha `permissions:` antes da `Task` (S16) | morre (permissionLineWiring) | morre (launchPermissionsWiring, permissionLineWiring) |
| L2 | abertura | main | `microphone: { MicrophoneAccess.authorized }` (constante) | **sobrevive** | morre (launchPermissionsWiring) |
| L3 | abertura | main | `accessibilityGranted: { true }` (constante) | **sobrevive** | morre (launchPermissionsWiring) |
| L4-D1c | abertura | main | pedido sem `microphoneRequest.ask` (D1c) | morre (undeterminedMicrophoneWiring) | morre (launchPermissionsWiring, undeterminedMicrophoneWiring) |
| L5 | abertura | main | `requestAccessibility: { }` (chamada apagada) | **sobrevive** | morre (launchPermissionsWiring) |
| L6 | abertura | main | sem `renderResting()` depois dos pedidos | morre (permissionWatchWiring) | morre (launchPermissionsWiring) |
| L7 | abertura | main | sem a segunda linha `permissions:` | morre (permissionLineWiring, permissionWatchWiring) | morre (launchPermissionsWiring, permissionLineWiring) |
| L8-M3 | abertura | main | sem `permissionWatch.start()` (M3) | morre (permissionWatchWiring) | morre (launchPermissionsWiring) |
| L9 | abertura | main | saída antes de `LaunchPermissions.run(` | morre (permissionWatchWiring) | morre (launchPermissionsWiring) |
| L10-M10b | abertura | main | `start()` antes dos pedidos | morre (permissionWatchWiring) | morre (launchPermissionsWiring) |
| M9 | abertura | main | volta `if !self.micAuthorized { self.render(.blocked) }` | morre (permissionWatchWiring) | morre (launchPermissionsWiring) |
| M10 | abertura | main | `start()` só no modelo que falhou (M10) | morre (permissionWatchWiring) | morre (launchPermissionsWiring, modelLoadWiring) |
| M14 | modelo | main | **`if !loaded`** (antes) / `loaded: { !(await didLoad()) }` (depois) | **sobrevive** | morre (modelLoadWiring) |
| M14c | modelo | icon | Core: `guard !(await loaded())` | n/a | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| M15 | modelo | main | **`metalActive = loaded`** (antes) / `metalActive: { await didLoad() }` (depois) | **sobrevive** | morre (modelLoadWiring) |
| M15c | modelo | icon | Core: `metalActive: true` no estado final | n/a | morre (afterLoadNoMetal) |
| M5a | modelo | icon | Core: `.ready` e `.noMetal` trocados | morre (modelStateFromTheLoad) | morre (afterLoadNoMetal, afterLoadReady, modelStateFromTheLoad) |
| M5b | modelo | main | Metal negado no `main.swift` | morre (permissionWatchWiring) | morre (modelLoadWiring) |
| MD1 | modelo | main | `loaded` constante `true` | morre (permissionWatchWiring) | morre (modelLoadWiring) |
| MD2 | modelo | main | Metal constante `true` | morre (permissionWatchWiring) | morre (modelLoadWiring) |
| MD3 | modelo | main | saída antes de gravar o `modelState` | **sobrevive** | morre (modelLoadWiring) |
| M12 | modelo | main | sem `renderResting()` depois do modelo | morre (permissionWatchWiring) | morre (modelLoadWiring) |
| M16 | modelo | main | `renderResting()` antes de gravar o estado | morre (permissionWatchWiring) | morre (modelLoadWiring) |
| MD4 | modelo | main | `log: { _ in }` | n/a | morre (modelLoadWiring) |
| MD5 | modelo | main | `devices: { "" }` (constante) | n/a | morre (modelLoadWiring) |
| MC1 | modelo | icon | Core: Metal consultado antes do `guard` (sem modelo) | n/a | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| MC2 | modelo | icon | Core: `if metal` (aviso invertido) | n/a | morre (afterLoadNoMetal, afterLoadReady) |
| MC3 | modelo | icon | Core: sem o `WARNING` | n/a | morre (afterLoadNoMetal) |
| MC4 | modelo | icon | Core: sem a linha `ggml devices:` | n/a | morre (afterLoadNoMetal, afterLoadReady) |
| MC5 | modelo | icon | Core: devices lidos antes do `guard` | n/a | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| T1 | gatilho | main | `let microphone = .authorized` (constante) | morre (permissionWatchWiring) | morre (triggerWiring) |
| T2 | gatilho | main | `let accessibility = true` (constante) | morre (permissionWatchWiring) | morre (triggerWiring) |
| T3 | gatilho | main | sem a linha `permissions:` no gatilho | morre (permissionWatchWiring) | morre (triggerWiring) |
| T4-M4 | gatilho | main | sem `permissionWatch.start()` (M4) | morre (permissionWatchWiring) | morre (triggerWiring) |
| M11 | gatilho | main | `start()` só em `.startRecording` (M11) | morre (permissionWatchWiring) | morre (triggerWiring) |
| T6 | gatilho | main | saída antes do `switch DictationAttempt.decide(` | morre (permissionWatchWiring) | morre (triggerWiring) |
| T7 | gatilho | main | `isTranscribing: false` | **sobrevive** | morre (triggerWiring) |
| D1d | gatilho | main | `microphoneRequestPending: false` (D1d) | morre (undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| T9 | gatilho | main | `accessibilityAuthorized: !accessibility` | **sobrevive** | morre (triggerWiring) |
| T10 | gatilho | main | `microphone: .authorized` na decisão | **sobrevive** | morre (triggerWiring) |
| TA1 | gatilho | main | Acessibilidade: sem `render(.blocked)` | **sobrevive** | morre (triggerWiring) |
| TA2 | gatilho | main | Acessibilidade: sem o aviso | **sobrevive** | morre (triggerWiring) |
| TA3 | gatilho | main | Acessibilidade: `return true` | **sobrevive** | morre (triggerWiring) |
| TA4 | gatilho | main | Acessibilidade: abre o aviso do microfone (ramos trocados) | **sobrevive** | morre (triggerWiring) |
| S15 | gatilho | main | indeciso sem `askAgainForMicrophone()` (S15) | morre (undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TR2 | gatilho | main | indeciso mostra o aviso de espera (ramos trocados) | morre (undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TR3 | gatilho | main | indeciso: sem `render(.blocked)` | **sobrevive** | morre (triggerWiring) |
| D1a | gatilho | main | pedido aberto sem o aviso de espera (D1a) | morre (undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| V1 | gatilho | main | pedido aberto pede de novo (ramos trocados) | morre (undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TW3 | gatilho | main | pedido aberto: sem `render(.blocked)` | **sobrevive** | morre (triggerWiring) |
| S14 | gatilho | main | negado sem `showMicrophoneRequiredAlert()` (S14) | morre (microphoneWiring) | morre (microphoneWiring, triggerWiring) |
| S14c | gatilho | main | a chamada do aviso comentada (S14c) | morre (microphoneWiring) | morre (microphoneWiring, triggerWiring) |
| S17v | gatilho | main | saída antes do aviso do negado, no gatilho | **sobrevive** | morre (triggerWiring) |
| TM4 | gatilho | main | negado: sem `render(.blocked)` | **sobrevive** | morre (triggerWiring) |
| TS1 | gatilho | main | `.startRecording` devolve `false` (saída antes de gravar) | **sobrevive** | morre (triggerWiring) |
| TS2 | gatilho | main | `.waitForTranscription` vira `break` (grava durante a transcrição) | **sobrevive** | morre (triggerWiring) |
| AG1 | askAgain | main | `request: { }` | morre (undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| D1b | askAgain | main | `onNoAnswer: { }` (D1b) | morre (undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| AG3 | askAgain | main | sem `renderResting()` | morre (permissionWatchWiring) | morre (askAgainWiring) |
| AG4-L6 | askAgain | main | `render(.idle)` no lugar da regra (L6) | morre (permissionWatchWiring) | morre (askAgainWiring) |
| M6 | askAgain | main | sem `permissionWatch.start()` (M6) | morre (permissionWatchWiring) | morre (askAgainWiring) |
| AG6 | askAgain | main | saída antes do `askAgain(` | **sobrevive** | morre (askAgainWiring) |
| AG7 | askAgain | main | sem a linha `permissions:` | **sobrevive** | morre (askAgainWiring) |
| MA1 | askAgain | main | item do menu sem `askAgainForMicrophone()` | morre (undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| AF1 | askAgain | main | `requestAccess(for: .video)` | **sobrevive** | morre (askAgainWiring) |
| M8a | permissionsChanged | main | `if reading.isComplete { return }` antes do redesenho (M8) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC2 | permissionsChanged | main | sem a linha `permissions:` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC3 | permissionsChanged | main | leitura constante no redesenho | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC4 | permissionsChanged | main | sem `renderResting(reading)` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M2a | renderResting | main | `recording: !recorder.isRecording` (M2) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M1b | renderResting | main | mapeamento invertido no `render` (M1) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M13 | renderResting | main | `transcribing: false` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR4 | renderResting | main | `model: .ready` (constante) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR5 | renderResting | main | padrão do parâmetro constante no lugar de `.current` | **sobrevive** | morre (permissionWatchWiring) |
| RR6 | renderResting | main | sem `render(visual)` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR7 | renderResting | main | saída antes do `StatusIcon.redraw(` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M2c | renderResting | icon | Core: guarda sem a transcrição | morre (noRedrawWhileDictating) | morre (noRedrawWhileDictating) |
| M8c | renderResting | icon | Core: `if permissions.isComplete { return nil }` | morre (redrawAtRest) | morre (redrawAtRest) |
| M1a | renderResting | icon | Core: `StatusIcon.visual` invertido | morre (redrawAtRest, restingVisual) | morre (redrawAtRest, restingVisual) |
| LW1 | linha permissions | main | sem `log(line)` | morre (permissionLineWiring) | morre (permissionLineWiring, permissionLineWriterWiring) |
| LW2 | linha permissions | main | padrão `microphone: .authorized` | **sobrevive** | morre (permissionLineWriterWiring) |
| LW3 | linha permissions | main | padrão `accessibility: true` | **sobrevive** | morre (permissionLineWriterWiring) |
| LW4 | linha permissions | main | `accessibilityGranted: true` na linha | **sobrevive** | morre (permissionLineWriterWiring) |
| P1 | releitura | main | `read:` constante completa | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| P2 | releitura | main | `onChange: { _ in }` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| P3 | releitura | main | intervalo de 60 s na propriedade | não compila | não compila |
| PR1 | releitura | icon | Core: `PermissionReading.current` com microfone constante | **sobrevive** | morre (currentReadsTheSystem) |
| PR2 | releitura | icon | Core: `PermissionReading.current` com Acessibilidade constante | **sobrevive** | morre (currentReadsTheSystem) |
| W1 | warnIfAccessibilityMissing | main | `guard HotkeyMonitor.hasAccessibilityPermission` (negado) | **sobrevive** | morre (accessibilityWarningWiring) |
| W2 | warnIfAccessibilityMissing | main | sem `render(.blocked)` | **sobrevive** | morre (accessibilityWarningWiring) |
| W3 | warnIfAccessibilityMissing | main | sem `requestAccessibilityPermission()` | **sobrevive** | morre (accessibilityWarningWiring) |
| W4 | warnIfAccessibilityMissing | main | saída antes do pedido | **sobrevive** | morre (accessibilityWarningWiring) |
| G1 | avisos | main | Acessibilidade: `guard !permissionAlertGate.begin()` | **sobrevive** | morre (accessibilityWarningWiring) |
| G2 | avisos | main | microfone: sem o `defer` do portão | morre (microphoneWiring) | morre (microphoneWiring) |
| D1f | avisos | main | espera: sem o portão (D1f) | morre (undeterminedMicrophoneWiring) | morre (undeterminedMicrophoneWiring) |
| R1 | avisos | main | Acessibilidade: `runModal() !=` | **sobrevive** | morre (accessibilityWarningWiring) |
| R2 | avisos | main | microfone: sem `openMicrophoneSettings()` | morre (microphoneWiring) | morre (microphoneWiring) |
| R3 | avisos | main | Acessibilidade abre a página do microfone (ramos trocados) | **sobrevive** | morre (accessibilityWarningWiring) |
| R4 | avisos | main | microfone: `runModal() !=` | **sobrevive** | morre (microphoneWiring) |
| D1e | avisos | main | espera: saída antes do `runModal` (D1e) | morre (undeterminedMicrophoneWiring) | morre (undeterminedMicrophoneWiring) |
| S17 | avisos | main | `if microphoneRequest.isPending { return }` antes do aviso do negado (S17) | morre (microphoneWiring) | morre (microphoneWiring) |
| R5 | avisos | main | Acessibilidade: saída antes do aviso | **sobrevive** | morre (accessibilityWarningWiring) |
| GC1 | avisos | dict | Core: `begin()` sempre verdadeiro | morre (warningPresentationRejectsReentry) | morre (warningPresentationRejectsReentry) |
| GC2 | avisos | dict | Core: `end()` vazio | morre (warningPresentationRejectsReentry) | morre (warningPresentationRejectsReentry) |
| MC1m | menu | main | `microphone: .authorized` (constante) | **sobrevive** | morre (menuPermissionConditionsWiring) |
| MC2m | menu | main | `accessibilityAuthorized: true` (constante) | **sobrevive** | morre (menuPermissionConditionsWiring) |
| MC3m | menu | main | Acessibilidade negada | **sobrevive** | morre (menuPermissionConditionsWiring) |
| MC4m | menu | main | sem a linha `permissions:` ao abrir | **sobrevive** | morre (menuPermissionConditionsWiring) |
| ML1 | menu | menu | Core: `if conditions.accessibilityAuthorized` (negado) | morre (accessibilityMissing, bothPermissionsMissing, handsFreeOff, microphoneMissing, nothingTranscribedYet, optionShowsTheDiagnostics, theDefaultMenu, undeterminedMicrophoneAsksAgain) | morre (accessibilityMissing, bothPermissionsMissing, handsFreeOff, microphoneMissing, nothingTranscribedYet, optionShowsTheDiagnostics, theDefaultMenu, undeterminedMicrophoneAsksAgain) |
| ML2 | menu | menu | Core: indeciso oferece a página (ramos trocados) | morre (bothPermissionsMissing, undeterminedMicrophoneAsksAgain) | morre (bothPermissionsMissing, undeterminedMicrophoneAsksAgain) |

### Marco D5: prova final (09:43)
* `swift build`: exit 0. `swift test`: exit 0, **296 testes em 32 suítes, passou** (285 da reauditoria mais 11 novos: 4 em `StatusIconTests` com 5 casos, 7 em `MenuLayoutTests`; `permissionWatchWiring` reescrito, não somado).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Build limpo `swift build --build-tests --scratch-path <scratchpad>/conserto2-1b/build-clean` (exit 0) + `python3 scripts/count-swift-warnings.py <log>`: **4**, a mesma lista (`AudioRecorder.swift` 1:1, 402:29, 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* Travessão e aspas curvas nas linhas adicionadas (`git diff -U0 | grep '^+'`): 0.
* `git status --short`: `main.swift`, `StatusIcon.swift`, `MenuLayoutTests.swift`, `StatusIconTests.swift` e este progresso modificados; `?? models`. `git diff --stat` em `docs/`, `scripts/`, `Package.swift`, README e `Tests/NeverTypeCoreTests/Audit/`: vazio. As sondas da auditoria seguem intactas e verdes.

### Decisões do conserto 2
* A única decisão que ainda morava no `main.swift` era a do fim do modelo (o A2): saiu para o Core (`ModelState.afterLoad`), com teste de comportamento que conta as leituras (Metal e devices nunca consultados sem modelo) e confere as linhas de log. O resto da classe é ligação (desenhar, escrever o log, abrir `NSAlert`, criar a `Task`), sem condição de permissão ou de modelo que pudesse ir para o Core além das que já estão lá (`DictationAttempt.decide`, `StatusIcon.redraw`, `LaunchPermissions.run`, `MicrophoneRequest`, `PresentationGate`, `MenuLayout.rows`). Por isso o resto ficou com oráculo linha a linha, inteiro, no molde do `expectAlert`.
* Os oráculos inteiros prendem também o texto das linhas de log e dos avisos dentro das ligações. Mudar uma frase de log no gatilho passa a exigir mudar o teste junto. É o preço de prender a ligação inteira: um oráculo parcial foi o que deixou o A1 e o A2 passarem.
* `PermissionReading.current` (Core, desta frente) é a fronteira com o TCC, que não entra em teste: ficou com oráculo de texto em `StatusIconTests.currentReadsTheSystem`, o mesmo tipo de prova dos oráculos do `main.swift`. PR1 e PR2 morrem nele.
* Comportamento do app: sem mudança. As linhas `ggml devices:` e `WARNING: without Metal…` saem na mesma ordem e nas mesmas condições; o estado e o redesenho são os mesmos do conserto 1. Nada a declarar como ressalva.
* B7: só o comentário de `StatusIcon.redraw` mudou; o redesenho que falta no fim da transcrição segue com o B3.
* Sondas presas à forma: nenhuma das sondas da auditoria (`Tests/NeverTypeCoreTests/Audit/`) olha o `main.swift` nem o `StatusIcon.swift`; nada a registrar.

### Fora da parte (conserto 2)
* B1, B3, B4 e B6 seguem como tarefa. P3 (o intervalo de um segundo trocado na propriedade) não compila na forma tentada; o valor de um segundo segue sem prova (B1).
* `MicrophoneAccess.current` (parte 1) é a outra leitura do TCC no Core e não tem oráculo de texto; ficou fora por ser da parte 1, não desta frente.
* `body(of:in:)` segue aceitando comentário de bloco e comentário no fim da linha (B6). Os oráculos inteiros deste conserto comparam linhas de código aparadas, então um comentário no fim de uma linha presa deixa o teste vermelho, não verde.

### Comandos de prova (conserto 2)
* `cd ~/Projects/apps/never-type-permissoes && swift test --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests|PermissionsPart1bAuditTests"`
* `cd ~/Projects/apps/never-type-permissoes && python3 -I <scratchpad>/conserto2-1b/sweep.py depois <scratchpad>/conserto2-1b/bak1 <saida>.jsonl [ids]` (mutações em `muts.py`, tabela por `table.py`; `SWEEP_FILTER=.` roda a suíte inteira)
* `cd ~/Projects/apps/never-type-permissoes && swift build && swift test`
* `cd ~/Projects/apps/never-type-permissoes && python3 scripts/test-count-swift-warnings.py`

## Estado do conserto 2: FEITO (o teste manual do TCC segue com o Pedro)

## Conserto 3 (16/10)

Volta 3, liberada pela orquestração às 10:01. Achados da reauditoria 2 (`.vibeflow/audits/never-type-permissoes-1b-reaudit-2.md`): a classe do A2 (X-AB1 a X-AB3, X-MD1, X-MD2, X-MN1), B8, B9 e B10. B1, B3, B4 e B6 seguem como tarefa.

### Marco E0: leitura
* Lidos: o briefing do conserto 3, o `CLAUDE.md`, a reauditoria 2, as seções dos consertos 1 e 2 deste progresso, os princípios 1, 6 e 7 do dev-remoto e o padrão `estado-consultado.md`.
* `git log --oneline -3`: `c50aa43`, `552d715`, `bbfec96`, como no briefing. `git status --short`: só `?? models`.
* Shas de partida (iguais ao `bak/` da reauditoria 2): `main.swift` ca37b8f9, `StatusIcon.swift` ac60fa3e, `MenuLayoutTests.swift` 99020d81, `StatusIconTests.swift` a33cab34, `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da, `MenuLayout.swift` 1c7a6dec. Sondas: `PermissionsPart1AuditTests.swift` d0eca29d, `PermissionsPart1bAuditTests.swift` b05faa3d. Cópia em `<scratchpad>/conserto3-1b/bak0/`, conferida por `shasum`.
* Falta: a varredura "antes" das mutações novas, os oráculos inteiros, B8, B9, B10, a varredura "depois" e a prova final.

### Marco E1: varredura "antes" (10:10)
* Mutações novas em `<scratchpad>/conserto3-1b/muts.py`, geradas do `main.swift` de partida: uma saída (`if ProcessInfo.processInfo.processIdentifier > 0 { return }`, sempre verdadeiro) antes de cada instrução do primeiro nível de `applicationDidFinishLaunching` até a `Task` do modelo (AR1 a AR21); um `if` sempre falso (`processIdentifier < 0`) de cada um desses pontos até o fim do bloco das permissões (AWP1 a AWP20) e até o fim do bloco do modelo (AWM1 a AWM21); saída e `if` sempre falso em cada ponto de dentro das duas `Task` (AIP, AJP, AIM, AJM); o mesmo em `rebuildMenu` até o fim do laço das linhas (NR1 a NR5, NWL1 a NWL5, NIL1, NJL1). Mais M9b (o M9 do conserto 2 escrito sem `micAuthorized`, que o B9 apaga), AV3 e AV4 (as duas funções que abrem os Ajustes sem o `open`). 97 ao todo. O `sweep.py` é o do conserto 2, copiado sem mudança.
* `python3 -I <scratchpad>/conserto3-1b/sweep.py antes bak0 antes.jsonl`, nos testes de partida: **32 mortas, 65 sobreviventes, 0 sem build.** Sobrevivem todas as saídas e `if` do primeiro nível antes da `Task` das permissões (AR1 a AR19, AWP1 a AWP19, AWM1 a AWM19), as da `Task` do modelo (AR21, AWM21), as do laço do menu (NR5, NWL5, NIL1, NJL1) e AV3 e AV4. É a classe do A2 inteira, maior que as seis da reauditoria. `main.swift` voltou a ca37b8f9.

### Marco E2: oráculos inteiros, B8, B9 e B10 (10:20)
* `MenuLayoutTests`: `launchPermissionsWiring` virou `launchWiring`, que prende `applicationDidFinishLaunching` inteiro, linha de código a linha de código (59 linhas, da trava de instância ao último `log`); `modelLoadWiring` ficou só com a conferência de que o `modelState` é gravado num lugar só (a janela dele está dentro do corpo inteiro); `menuPermissionConditionsWiring` prende `rebuildMenu` inteiro; novos `menuItemsWiring` (`item(for:)` inteiro) e `settingsPagesWiring` (`openAccessibilitySettings` e `openMicrophoneSettings` inteiros). Mesmo molde do `handle` e do `expectAlert`: `codeLines(body) == [...]`.
* B8: o comentário de `renderResting` diz o que o B7 já diz no Core (o `.released` desenha o normal fora da regra, B3; a transcrição com sucesso não redesenha).
* B9: `micAuthorized` saiu do `main.swift`; o comentário de `loginItemState`, que dizia "same as the microphone", aponta `MicrophoneAccess.current` e `PermissionReading.current`. O exemplo de `.vibeflow/patterns/estado-consultado.md` passou a citar `MicrophoneAccess.current` (`Permissions.swift`), com o histórico da flag numa frase abaixo.
* Testes novos sobre código que já estava certo: endurecimento, provado pela varredura (vermelho é a mutação que sobrevivia no "antes" e morre no "depois").
* `swift build --build-tests`: 0 `error:`. Filtro das seis suítes: **82 testes em 6 suítes, passou** (80 mais `menuItemsWiring` e `settingsPagesWiring`).
* Estado entregue em `<scratchpad>/conserto3-1b/bak1/`: `main.swift` 4ecb8338, `MenuLayoutTests.swift` 891ee521; os outros cinco iguais ao `bak0`.

### Marco E3: varredura "depois"
Três listas, cada uma no estado entregue (`bak1`), filtro das seis suítes da parte, com o `sweep.py` do conserto 2 sem mudança (troca exata com contagem 1, `swift build --build-tests` verde para a morte contar, teste que pegou nomeado pelo `--xunit-output`, volta por cópia de `bak1/` com o sha conferido depois de cada uma, gravado no `.jsonl`):
* as 97 do conserto 3 (`<scratchpad>/conserto3-1b/muts.py`): **97 mortas, 0 sobreviventes, 0 sem build**;
* as 27 da reauditoria 2 (`reaudit2-1b/mine/muts.py`, copiado para `conserto3-1b/re2/`): **26 mortas, 1 sobrevivente (X-PW8, o B1 conhecido)**. As seis da classe morrem: X-AB1, X-AB2, X-AB3, X-MD1 e X-MD2 em `launchWiring`, X-MN1 em `menuPermissionConditionsWiring`. B10: X-AV1 morre em `settingsPagesWiring`, X-AV2 em `menuItemsWiring`;
* as 110 do conserto 2 (`conserto2-1b/muts.py`, copiado para `conserto3-1b/c2/`): **108 mortas, 0 sobreviventes, 2 sem build**: P3 (como antes) e M9, que usava `micAuthorized`, apagada pelo B9. A mesma regressão escrita com a leitura que fica (M9b, `if MicrophoneAccess.current != .authorized { self.render(.blocked) }`) morre em `launchWiring`.
* Nenhuma morta com a lista de testes vazia; nenhuma morta por erro de compilação. Depois das três, `main.swift` 4ecb8338 e `StatusIcon.swift` ac60fa3e, os do `bak1`.
* "antes" é o resultado no código e nos testes de partida: para as do conserto 3, `antes.jsonl` desta volta; para as da reauditoria, o `mine.jsonl` dela; para as do conserto 2, o `depois.jsonl` dele. "abertura" é `applicationDidFinishLaunching`, bloco P é a `Task` das permissões, bloco M a do modelo, bloco L o laço das linhas do menu.

| id | origem | ligação | arquivo | mutação | antes | depois |
|---|---|---|---|---|---|---|
| AR1 | conserto 3 | abertura | main | saída antes de `guard Self.acquireInstanceLock() else {` | **sobrevive** | morre (launchWiring) |
| AR2 | conserto 3 | abertura | main | saída antes de `let ranBefore = startLog()` | **sobrevive** | morre (launchWiring) |
| AR3 | conserto 3 | abertura | main | saída antes de `removeLegacyTranscriptFile()` | **sobrevive** | morre (launchWiring) |
| AR4 | conserto 3 | abertura | main | saída antes de `storeFirstPauseMedia(ranBefore: ranBefore)` | **sobrevive** | morre (launchWiring) |
| AR5 | conserto 3 | abertura | main | saída antes de `statusItem = NSStatusBar.system.statusItem(withLength: NSSta` | **sobrevive** | morre (launchWiring) |
| AR6 | conserto 3 | abertura | main | saída antes de `render(.idle)` | **sobrevive** | morre (launchWiring) |
| AR7 | conserto 3 | abertura | main | saída antes de `menu.delegate = self` | **sobrevive** | morre (launchWiring) |
| AR8 | conserto 3 | abertura | main | saída antes de `statusItem.menu = menu` | **sobrevive** | morre (launchWiring) |
| AR9 | conserto 3 | abertura | main | saída antes de `overlay.menu = menu` | **sobrevive** | morre (launchWiring) |
| AR10 | conserto 3 | abertura | main | saída antes de `if let saved = HotkeyMonitor.Trigger.named(UserDefaults.stan` | **sobrevive** | morre (launchWiring) |
| AR11 | conserto 3 | abertura | main | saída antes de `setHandsFreeTrigger(HotkeyMonitor.Trigger.named(UserDefaults` | **sobrevive** | morre (launchWiring) |
| AR12 | conserto 3 | abertura | main | saída antes de `monitor.handsFreeEnabled = Self.handsFreeIsOn` | **sobrevive** | morre (launchWiring) |
| AR13 | conserto 3 | abertura | main | saída antes de `monitor.onEvent = { [weak self] event in self?.handle(event)` | **sobrevive** | morre (launchWiring) |
| AR14 | conserto 3 | abertura | main | saída antes de `recorder.onLevel = { [weak self] level in self?.overlay.push` | **sobrevive** | morre (launchWiring) |
| AR15 | conserto 3 | abertura | main | saída antes de `recorder.onError = { [weak self] message in` | **sobrevive** | morre (launchWiring) |
| AR16 | conserto 3 | abertura | main | saída antes de `monitor.start()` | **sobrevive** | morre (launchWiring) |
| AR17 | conserto 3 | abertura | main | saída antes de `overlay.showIdle()` | **sobrevive** | morre (launchWiring) |
| AR18 | conserto 3 | abertura | main | saída antes de `refreshHoverHint()` | **sobrevive** | morre (launchWiring) |
| AR19 | conserto 3 | abertura | main | saída antes de `logPermissionsIfChanged()` | **sobrevive** | morre (launchWiring) |
| AR20 | conserto 3 | abertura | main | saída antes de `Task { @MainActor in` | morre (launchPermissionsWiring) | morre (launchWiring) |
| AR21 | conserto 3 | abertura | main | saída antes de `Task {` | **sobrevive** | morre (launchWiring) |
| AWP1 | conserto 3 | abertura | main | `if` sempre falso de `guard Self.acquireInstanceLock() else {` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP2 | conserto 3 | abertura | main | `if` sempre falso de `let ranBefore = startLog()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP3 | conserto 3 | abertura | main | `if` sempre falso de `removeLegacyTranscriptFile()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP4 | conserto 3 | abertura | main | `if` sempre falso de `storeFirstPauseMedia(ranBefore: ranBefore)` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP5 | conserto 3 | abertura | main | `if` sempre falso de `statusItem = NSStatusBar.system.statusItem(withLen` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP6 | conserto 3 | abertura | main | `if` sempre falso de `render(.idle)` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP7 | conserto 3 | abertura | main | `if` sempre falso de `menu.delegate = self` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP8 | conserto 3 | abertura | main | `if` sempre falso de `statusItem.menu = menu` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP9 | conserto 3 | abertura | main | `if` sempre falso de `overlay.menu = menu` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP10 | conserto 3 | abertura | main | `if` sempre falso de `if let saved = HotkeyMonitor.Trigger.named(UserDef` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP11 | conserto 3 | abertura | main | `if` sempre falso de `setHandsFreeTrigger(HotkeyMonitor.Trigger.named(Us` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP12 | conserto 3 | abertura | main | `if` sempre falso de `monitor.handsFreeEnabled = Self.handsFreeIsOn` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP13 | conserto 3 | abertura | main | `if` sempre falso de `monitor.onEvent = { [weak self] event in self?.han` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP14 | conserto 3 | abertura | main | `if` sempre falso de `recorder.onLevel = { [weak self] level in self?.ov` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP15 | conserto 3 | abertura | main | `if` sempre falso de `recorder.onError = { [weak self] message in` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP16 | conserto 3 | abertura | main | `if` sempre falso de `monitor.start()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP17 | conserto 3 | abertura | main | `if` sempre falso de `overlay.showIdle()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP18 | conserto 3 | abertura | main | `if` sempre falso de `refreshHoverHint()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP19 | conserto 3 | abertura | main | `if` sempre falso de `logPermissionsIfChanged()` até o fim do bloco P | **sobrevive** | morre (launchWiring) |
| AWP20 | conserto 3 | abertura | main | `if` sempre falso de `Task { @MainActor in` até o fim do bloco P | morre (launchPermissionsWiring) | morre (launchWiring) |
| AWM1 | conserto 3 | abertura | main | `if` sempre falso de `guard Self.acquireInstanceLock() else {` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM2 | conserto 3 | abertura | main | `if` sempre falso de `let ranBefore = startLog()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM3 | conserto 3 | abertura | main | `if` sempre falso de `removeLegacyTranscriptFile()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM4 | conserto 3 | abertura | main | `if` sempre falso de `storeFirstPauseMedia(ranBefore: ranBefore)` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM5 | conserto 3 | abertura | main | `if` sempre falso de `statusItem = NSStatusBar.system.statusItem(withLen` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM6 | conserto 3 | abertura | main | `if` sempre falso de `render(.idle)` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM7 | conserto 3 | abertura | main | `if` sempre falso de `menu.delegate = self` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM8 | conserto 3 | abertura | main | `if` sempre falso de `statusItem.menu = menu` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM9 | conserto 3 | abertura | main | `if` sempre falso de `overlay.menu = menu` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM10 | conserto 3 | abertura | main | `if` sempre falso de `if let saved = HotkeyMonitor.Trigger.named(UserDef` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM11 | conserto 3 | abertura | main | `if` sempre falso de `setHandsFreeTrigger(HotkeyMonitor.Trigger.named(Us` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM12 | conserto 3 | abertura | main | `if` sempre falso de `monitor.handsFreeEnabled = Self.handsFreeIsOn` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM13 | conserto 3 | abertura | main | `if` sempre falso de `monitor.onEvent = { [weak self] event in self?.han` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM14 | conserto 3 | abertura | main | `if` sempre falso de `recorder.onLevel = { [weak self] level in self?.ov` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM15 | conserto 3 | abertura | main | `if` sempre falso de `recorder.onError = { [weak self] message in` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM16 | conserto 3 | abertura | main | `if` sempre falso de `monitor.start()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM17 | conserto 3 | abertura | main | `if` sempre falso de `overlay.showIdle()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM18 | conserto 3 | abertura | main | `if` sempre falso de `refreshHoverHint()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM19 | conserto 3 | abertura | main | `if` sempre falso de `logPermissionsIfChanged()` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AWM20 | conserto 3 | abertura | main | `if` sempre falso de `Task { @MainActor in` até o fim do bloco M | morre (launchPermissionsWiring) | morre (launchWiring) |
| AWM21 | conserto 3 | abertura | main | `if` sempre falso de `Task {` até o fim do bloco M | **sobrevive** | morre (launchWiring) |
| AIP1 | conserto 3 | abertura | main | saída dentro do bloco P, antes de `await LaunchPermissions.run(` | morre (launchPermissionsWiring) | morre (launchWiring) |
| AIP2 | conserto 3 | abertura | main | saída dentro do bloco P, antes de `self.renderResting()` | morre (launchPermissionsWiring) | morre (launchWiring) |
| AIP3 | conserto 3 | abertura | main | saída dentro do bloco P, antes de `self.logPermissionsIfChanged()` | morre (launchPermissionsWiring) | morre (launchWiring) |
| AIP4 | conserto 3 | abertura | main | saída dentro do bloco P, antes de `self.permissionWatch.start()` | morre (launchPermissionsWiring) | morre (launchWiring) |
| AJP1 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco P, de `await LaunchPermissions.run(` ao fim | morre (launchPermissionsWiring) | morre (launchWiring) |
| AJP2 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco P, de `self.renderResting()` ao fim | morre (launchPermissionsWiring) | morre (launchWiring) |
| AJP3 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco P, de `self.logPermissionsIfChanged()` ao fim | morre (launchPermissionsWiring) | morre (launchWiring) |
| AJP4 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco P, de `self.permissionWatch.start()` ao fim | morre (launchPermissionsWiring) | morre (launchWiring) |
| AIM1 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `await transcription.prepare()` | morre (modelLoadWiring) | morre (launchWiring) |
| AIM2 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `let status = await transcription.currentStatus()` | morre (modelLoadWiring) | morre (launchWiring) |
| AIM3 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `self.modelStatus = status` | morre (modelLoadWiring) | morre (launchWiring) |
| AIM4 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `self.log("model: \(status)")` | morre (modelLoadWiring) | morre (launchWiring) |
| AIM5 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `self.modelState = await ModelState.afterLoad(` | morre (modelLoadWiring) | morre (launchWiring) |
| AIM6 | conserto 3 | abertura | main | saída dentro do bloco M, antes de `self.renderResting()` | morre (modelLoadWiring) | morre (launchWiring) |
| AJM1 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `await transcription.prepare()` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| AJM2 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `let status = await transcription.current` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| AJM3 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `self.modelStatus = status` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| AJM4 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `self.log("model: \(status)")` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| AJM5 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `self.modelState = await ModelState.after` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| AJM6 | conserto 3 | abertura | main | `if` sempre falso dentro do bloco M, de `self.renderResting()` ao fim | morre (modelLoadWiring) | morre (launchWiring) |
| NR1 | conserto 3 | menu | main | saída antes de `menu.removeAllItems()` | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NR2 | conserto 3 | menu | main | saída antes de `logPermissionsIfChanged()` | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NR3 | conserto 3 | menu | main | saída antes de `let loginState = loginItemState` | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NR4 | conserto 3 | menu | main | saída antes de `let conditions = MenuLayout.Conditions(` | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NR5 | conserto 3 | menu | main | saída antes de `for row in MenuLayout.rows(for: conditions) {` | **sobrevive** | morre (menuPermissionConditionsWiring) |
| NWL1 | conserto 3 | menu | main | `if` sempre falso de `menu.removeAllItems()` até o fim do bloco L | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NWL2 | conserto 3 | menu | main | `if` sempre falso de `logPermissionsIfChanged()` até o fim do bloco L | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NWL3 | conserto 3 | menu | main | `if` sempre falso de `let loginState = loginItemState` até o fim do bloco L | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NWL4 | conserto 3 | menu | main | `if` sempre falso de `let conditions = MenuLayout.Conditions(` até o fim do bloco L | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| NWL5 | conserto 3 | menu | main | `if` sempre falso de `for row in MenuLayout.rows(for: conditions) {` até o fim do bloco L | **sobrevive** | morre (menuPermissionConditionsWiring) |
| NIL1 | conserto 3 | menu | main | saída dentro do bloco L, antes de `menu.addItem(item(for: row))` | **sobrevive** | morre (menuPermissionConditionsWiring) |
| NJL1 | conserto 3 | menu | main | `if` sempre falso dentro do bloco L, de `menu.addItem(item(for: row))` ao fim | **sobrevive** | morre (menuPermissionConditionsWiring) |
| M9b | conserto 3 | abertura | main | volta o redesenho pelo microfone sozinho, por `MicrophoneAccess.current` (M9 sem `micAuthorized`) | morre (launchPermissionsWiring) | morre (launchWiring) |
| AV3 | conserto 3 | avisos | main | `openAccessibilitySettings` sem `NSWorkspace.shared.open(url)` | **sobrevive** | morre (settingsPagesWiring) |
| AV4 | conserto 3 | avisos | main | `openMicrophoneSettings` sem `NSWorkspace.shared.open(url)` | **sobrevive** | morre (settingsPagesWiring) |
| X-AB1 | reauditoria 2 | abertura | main | saída antes do bloco das permissões | **sobrevive** | morre (launchWiring) |
| X-AB2 | reauditoria 2 | abertura | main | bloco das permissões dentro de `if` sempre falso | **sobrevive** | morre (launchWiring) |
| X-AB3 | reauditoria 2 | abertura | main | saída entre o bloco das permissões e o modelo | **sobrevive** | morre (launchWiring) |
| X-MD1 | reauditoria 2 | modelo | main | `Task` do modelo dentro de `if` sempre falso | **sobrevive** | morre (launchWiring) |
| X-MD2 | reauditoria 2 | modelo | main | saída antes da `Task` do modelo | **sobrevive** | morre (launchWiring) |
| X-MD3 | reauditoria 2 | modelo | main | `self.modelState = .ready` e o resultado do Core descartado | morre (modelLoadWiring) | morre (launchWiring, modelLoadWiring) |
| X-MC1 | reauditoria 2 | modelo | icon | Core: modelo que falhou devolve `.loading` | morre (afterLoadNotLoaded) | morre (afterLoadNotLoaded) |
| X-MC2 | reauditoria 2 | modelo | icon | Core: `ModelState(loaded: metal, …)` no fim | morre (afterLoadNoMetal) | morre (afterLoadNoMetal) |
| X-MC3 | reauditoria 2 | modelo | icon | Core: Metal constante `true`, a leitura descartada | morre (afterLoadNoMetal) | morre (afterLoadNoMetal) |
| X-RC1 | reauditoria 2 | renderResting | icon | `resting`: guarda da permissão negada | morre (grantedAndModelFine, missingPermissionSlashes, redrawAtRest) | morre (grantedAndModelFine, missingPermissionSlashes, redrawAtRest) |
| X-RC2 | reauditoria 2 | renderResting | icon | `.loading` riscado | morre (grantedAndModelFine, redrawAtRest) | morre (grantedAndModelFine, redrawAtRest) |
| X-RC3 | reauditoria 2 | renderResting | icon | `.noMetal` normal | morre (modelFailureKeepsTheSlash, redrawAtRest) | morre (modelFailureKeepsTheSlash, redrawAtRest) |
| X-RC4 | reauditoria 2 | renderResting | icon | `.notLoaded` normal | morre (modelFailureKeepsTheSlash, redrawAtRest) | morre (modelFailureKeepsTheSlash, redrawAtRest) |
| X-RC5 | reauditoria 2 | renderResting | icon | `isComplete` com `\|\|` | morre (completeReading, eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, missingPermissionSlashes, redrawAtRest, startsAgainAfterStopping, stopsWhenGranted) | morre (completeReading, eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, missingPermissionSlashes, redrawAtRest, startsAgainAfterStopping, stopsWhenGranted) |
| X-RC6 | reauditoria 2 | renderResting | icon | `isComplete` aceita microfone não respondido | morre (completeReading, missingPermissionSlashes) | morre (completeReading, missingPermissionSlashes) |
| X-RC7 | reauditoria 2 | renderResting | icon | `redraw` sem a guarda da gravação | morre (noRedrawWhileDictating) | morre (noRedrawWhileDictating) |
| X-PW1 | reauditoria 2 | releitura | icon | `start` com a guarda negada | morre (doesNotStartWhenGranted, eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, startsAgainAfterStopping, stopsWhenGranted) | morre (doesNotStartWhenGranted, eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, startsAgainAfterStopping, stopsWhenGranted) |
| X-PW2 | reauditoria 2 | releitura | icon | para com a leitura incompleta | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, startsAgainAfterStopping, stopsWhenGranted) | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, startsAgainAfterStopping, stopsWhenGranted) |
| X-PW3 | reauditoria 2 | releitura | icon | avisa só a leitura repetida | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, stopsWhenGranted) | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, stopsWhenGranted) |
| X-PW4 | reauditoria 2 | releitura | icon | sem `last = now` | morre (eachChangeOnce, goingBackIsAChange) | morre (eachChangeOnce, goingBackIsAChange) |
| X-PW5 | reauditoria 2 | releitura | icon | sem `onChange(now)` | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, stopsWhenGranted) | morre (eachChangeOnce, goingBackIsAChange, missingForLongIsStillWatched, stopsWhenGranted) |
| X-PW6 | reauditoria 2 | releitura | icon | sem a guarda de já rodando | morre (eachChangeOnce) | morre (eachChangeOnce) |
| X-PW7 | reauditoria 2 | releitura | icon | não sai do laço depois de parar | morre (stopsWhenGranted) | morre (stopsWhenGranted) |
| X-PW8 | reauditoria 2 | releitura | icon | `oneSecond` com 60 s | **sobrevive** | **sobrevive** |
| X-MN1 | reauditoria 2 | menu | main | saída antes de `MenuLayout.rows(for: conditions)` | **sobrevive** | morre (menuPermissionConditionsWiring) |
| X-AV1 | reauditoria 2 | avisos (pre-frente) | main | `openAccessibilitySettings` abre a página do microfone | **sobrevive** | morre (settingsPagesWiring) |
| X-AV2 | reauditoria 2 | avisos (pre-frente) | main | item do menu da Acessibilidade chama `openMicrophoneSettings` | **sobrevive** | morre (menuItemsWiring) |
| L1-S16 | conserto 2 | abertura | main | sem a linha `permissions:` antes da `Task` (S16) | morre (launchPermissionsWiring, permissionLineWiring) | morre (launchWiring, permissionLineWiring) |
| L2 | conserto 2 | abertura | main | `microphone: { MicrophoneAccess.authorized }` (constante) | morre (launchPermissionsWiring) | morre (launchWiring) |
| L3 | conserto 2 | abertura | main | `accessibilityGranted: { true }` (constante) | morre (launchPermissionsWiring) | morre (launchWiring) |
| L4-D1c | conserto 2 | abertura | main | pedido sem `microphoneRequest.ask` (D1c) | morre (launchPermissionsWiring, undeterminedMicrophoneWiring) | morre (launchWiring, undeterminedMicrophoneWiring) |
| L5 | conserto 2 | abertura | main | `requestAccessibility: { }` (chamada apagada) | morre (launchPermissionsWiring) | morre (launchWiring) |
| L6 | conserto 2 | abertura | main | sem `renderResting()` depois dos pedidos | morre (launchPermissionsWiring) | morre (launchWiring) |
| L7 | conserto 2 | abertura | main | sem a segunda linha `permissions:` | morre (launchPermissionsWiring, permissionLineWiring) | morre (launchWiring, permissionLineWiring) |
| L8-M3 | conserto 2 | abertura | main | sem `permissionWatch.start()` (M3) | morre (launchPermissionsWiring) | morre (launchWiring) |
| L9 | conserto 2 | abertura | main | saída antes de `LaunchPermissions.run(` | morre (launchPermissionsWiring) | morre (launchWiring) |
| L10-M10b | conserto 2 | abertura | main | `start()` antes dos pedidos | morre (launchPermissionsWiring) | morre (launchWiring) |
| M9 | conserto 2 | abertura | main | volta `if !self.micAuthorized { self.render(.blocked) }` | morre (launchPermissionsWiring) | não compila |
| M10 | conserto 2 | abertura | main | `start()` só no modelo que falhou (M10) | morre (launchPermissionsWiring, modelLoadWiring) | morre (launchWiring, modelLoadWiring) |
| M14 | conserto 2 | modelo | main | **`if !loaded`** (antes) / `loaded: { !(await didLoad()) }` (depois) | morre (modelLoadWiring) | morre (launchWiring) |
| M14c | conserto 2 | modelo | icon | Core: `guard !(await loaded())` | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| M15 | conserto 2 | modelo | main | **`metalActive = loaded`** (antes) / `metalActive: { await didLoad() }` (depois) | morre (modelLoadWiring) | morre (launchWiring) |
| M15c | conserto 2 | modelo | icon | Core: `metalActive: true` no estado final | morre (afterLoadNoMetal) | morre (afterLoadNoMetal) |
| M5a | conserto 2 | modelo | icon | Core: `.ready` e `.noMetal` trocados | morre (afterLoadNoMetal, afterLoadReady, modelStateFromTheLoad) | morre (afterLoadNoMetal, afterLoadReady, modelStateFromTheLoad) |
| M5b | conserto 2 | modelo | main | Metal negado no `main.swift` | morre (modelLoadWiring) | morre (launchWiring) |
| MD1 | conserto 2 | modelo | main | `loaded` constante `true` | morre (modelLoadWiring) | morre (launchWiring) |
| MD2 | conserto 2 | modelo | main | Metal constante `true` | morre (modelLoadWiring) | morre (launchWiring) |
| MD3 | conserto 2 | modelo | main | saída antes de gravar o `modelState` | morre (modelLoadWiring) | morre (launchWiring) |
| M12 | conserto 2 | modelo | main | sem `renderResting()` depois do modelo | morre (modelLoadWiring) | morre (launchWiring) |
| M16 | conserto 2 | modelo | main | `renderResting()` antes de gravar o estado | morre (modelLoadWiring) | morre (launchWiring) |
| MD4 | conserto 2 | modelo | main | `log: { _ in }` | morre (modelLoadWiring) | morre (launchWiring) |
| MD5 | conserto 2 | modelo | main | `devices: { "" }` (constante) | morre (modelLoadWiring) | morre (launchWiring) |
| MC1 | conserto 2 | modelo | icon | Core: Metal consultado antes do `guard` (sem modelo) | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| MC2 | conserto 2 | modelo | icon | Core: `if metal` (aviso invertido) | morre (afterLoadNoMetal, afterLoadReady) | morre (afterLoadNoMetal, afterLoadReady) |
| MC3 | conserto 2 | modelo | icon | Core: sem o `WARNING` | morre (afterLoadNoMetal) | morre (afterLoadNoMetal) |
| MC4 | conserto 2 | modelo | icon | Core: sem a linha `ggml devices:` | morre (afterLoadNoMetal, afterLoadReady) | morre (afterLoadNoMetal, afterLoadReady) |
| MC5 | conserto 2 | modelo | icon | Core: devices lidos antes do `guard` | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) | morre (afterLoadNoMetal, afterLoadNotLoaded, afterLoadReady) |
| T1 | conserto 2 | gatilho | main | `let microphone = .authorized` (constante) | morre (triggerWiring) | morre (triggerWiring) |
| T2 | conserto 2 | gatilho | main | `let accessibility = true` (constante) | morre (triggerWiring) | morre (triggerWiring) |
| T3 | conserto 2 | gatilho | main | sem a linha `permissions:` no gatilho | morre (triggerWiring) | morre (triggerWiring) |
| T4-M4 | conserto 2 | gatilho | main | sem `permissionWatch.start()` (M4) | morre (triggerWiring) | morre (triggerWiring) |
| M11 | conserto 2 | gatilho | main | `start()` só em `.startRecording` (M11) | morre (triggerWiring) | morre (triggerWiring) |
| T6 | conserto 2 | gatilho | main | saída antes do `switch DictationAttempt.decide(` | morre (triggerWiring) | morre (triggerWiring) |
| T7 | conserto 2 | gatilho | main | `isTranscribing: false` | morre (triggerWiring) | morre (triggerWiring) |
| D1d | conserto 2 | gatilho | main | `microphoneRequestPending: false` (D1d) | morre (triggerWiring, undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| T9 | conserto 2 | gatilho | main | `accessibilityAuthorized: !accessibility` | morre (triggerWiring) | morre (triggerWiring) |
| T10 | conserto 2 | gatilho | main | `microphone: .authorized` na decisão | morre (triggerWiring) | morre (triggerWiring) |
| TA1 | conserto 2 | gatilho | main | Acessibilidade: sem `render(.blocked)` | morre (triggerWiring) | morre (triggerWiring) |
| TA2 | conserto 2 | gatilho | main | Acessibilidade: sem o aviso | morre (triggerWiring) | morre (triggerWiring) |
| TA3 | conserto 2 | gatilho | main | Acessibilidade: `return true` | morre (triggerWiring) | morre (triggerWiring) |
| TA4 | conserto 2 | gatilho | main | Acessibilidade: abre o aviso do microfone (ramos trocados) | morre (triggerWiring) | morre (triggerWiring) |
| S15 | conserto 2 | gatilho | main | indeciso sem `askAgainForMicrophone()` (S15) | morre (triggerWiring, undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TR2 | conserto 2 | gatilho | main | indeciso mostra o aviso de espera (ramos trocados) | morre (triggerWiring, undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TR3 | conserto 2 | gatilho | main | indeciso: sem `render(.blocked)` | morre (triggerWiring) | morre (triggerWiring) |
| D1a | conserto 2 | gatilho | main | pedido aberto sem o aviso de espera (D1a) | morre (triggerWiring, undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| V1 | conserto 2 | gatilho | main | pedido aberto pede de novo (ramos trocados) | morre (triggerWiring, undeterminedMicrophoneWiring) | morre (triggerWiring, undeterminedMicrophoneWiring) |
| TW3 | conserto 2 | gatilho | main | pedido aberto: sem `render(.blocked)` | morre (triggerWiring) | morre (triggerWiring) |
| S14 | conserto 2 | gatilho | main | negado sem `showMicrophoneRequiredAlert()` (S14) | morre (microphoneWiring, triggerWiring) | morre (microphoneWiring, triggerWiring) |
| S14c | conserto 2 | gatilho | main | a chamada do aviso comentada (S14c) | morre (microphoneWiring, triggerWiring) | morre (microphoneWiring, triggerWiring) |
| S17v | conserto 2 | gatilho | main | saída antes do aviso do negado, no gatilho | morre (triggerWiring) | morre (triggerWiring) |
| TM4 | conserto 2 | gatilho | main | negado: sem `render(.blocked)` | morre (triggerWiring) | morre (triggerWiring) |
| TS1 | conserto 2 | gatilho | main | `.startRecording` devolve `false` (saída antes de gravar) | morre (triggerWiring) | morre (triggerWiring) |
| TS2 | conserto 2 | gatilho | main | `.waitForTranscription` vira `break` (grava durante a transcrição) | morre (triggerWiring) | morre (triggerWiring) |
| AG1 | conserto 2 | askAgain | main | `request: { }` | morre (askAgainWiring, undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| D1b | conserto 2 | askAgain | main | `onNoAnswer: { }` (D1b) | morre (askAgainWiring, undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| AG3 | conserto 2 | askAgain | main | sem `renderResting()` | morre (askAgainWiring) | morre (askAgainWiring) |
| AG4-L6 | conserto 2 | askAgain | main | `render(.idle)` no lugar da regra (L6) | morre (askAgainWiring) | morre (askAgainWiring) |
| M6 | conserto 2 | askAgain | main | sem `permissionWatch.start()` (M6) | morre (askAgainWiring) | morre (askAgainWiring) |
| AG6 | conserto 2 | askAgain | main | saída antes do `askAgain(` | morre (askAgainWiring) | morre (askAgainWiring) |
| AG7 | conserto 2 | askAgain | main | sem a linha `permissions:` | morre (askAgainWiring) | morre (askAgainWiring) |
| MA1 | conserto 2 | askAgain | main | item do menu sem `askAgainForMicrophone()` | morre (askAgainWiring, undeterminedMicrophoneWiring) | morre (askAgainWiring, undeterminedMicrophoneWiring) |
| AF1 | conserto 2 | askAgain | main | `requestAccess(for: .video)` | morre (askAgainWiring) | morre (askAgainWiring) |
| M8a | conserto 2 | permissionsChanged | main | `if reading.isComplete { return }` antes do redesenho (M8) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC2 | conserto 2 | permissionsChanged | main | sem a linha `permissions:` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC3 | conserto 2 | permissionsChanged | main | leitura constante no redesenho | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| PC4 | conserto 2 | permissionsChanged | main | sem `renderResting(reading)` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M2a | conserto 2 | renderResting | main | `recording: !recorder.isRecording` (M2) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M1b | conserto 2 | renderResting | main | mapeamento invertido no `render` (M1) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M13 | conserto 2 | renderResting | main | `transcribing: false` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR4 | conserto 2 | renderResting | main | `model: .ready` (constante) | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR5 | conserto 2 | renderResting | main | padrão do parâmetro constante no lugar de `.current` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR6 | conserto 2 | renderResting | main | sem `render(visual)` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| RR7 | conserto 2 | renderResting | main | saída antes do `StatusIcon.redraw(` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| M2c | conserto 2 | renderResting | icon | Core: guarda sem a transcrição | morre (noRedrawWhileDictating) | morre (noRedrawWhileDictating) |
| M8c | conserto 2 | renderResting | icon | Core: `if permissions.isComplete { return nil }` | morre (redrawAtRest) | morre (redrawAtRest) |
| M1a | conserto 2 | renderResting | icon | Core: `StatusIcon.visual` invertido | morre (redrawAtRest, restingVisual) | morre (redrawAtRest, restingVisual) |
| LW1 | conserto 2 | linha permissions | main | sem `log(line)` | morre (permissionLineWiring, permissionLineWriterWiring) | morre (permissionLineWiring, permissionLineWriterWiring) |
| LW2 | conserto 2 | linha permissions | main | padrão `microphone: .authorized` | morre (permissionLineWriterWiring) | morre (permissionLineWriterWiring) |
| LW3 | conserto 2 | linha permissions | main | padrão `accessibility: true` | morre (permissionLineWriterWiring) | morre (permissionLineWriterWiring) |
| LW4 | conserto 2 | linha permissions | main | `accessibilityGranted: true` na linha | morre (permissionLineWriterWiring) | morre (permissionLineWriterWiring) |
| P1 | conserto 2 | releitura | main | `read:` constante completa | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| P2 | conserto 2 | releitura | main | `onChange: { _ in }` | morre (permissionWatchWiring) | morre (permissionWatchWiring) |
| P3 | conserto 2 | releitura | main | intervalo de 60 s na propriedade | não compila | não compila |
| PR1 | conserto 2 | releitura | icon | Core: `PermissionReading.current` com microfone constante | morre (currentReadsTheSystem) | morre (currentReadsTheSystem) |
| PR2 | conserto 2 | releitura | icon | Core: `PermissionReading.current` com Acessibilidade constante | morre (currentReadsTheSystem) | morre (currentReadsTheSystem) |
| W1 | conserto 2 | warnIfAccessibilityMissing | main | `guard HotkeyMonitor.hasAccessibilityPermission` (negado) | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| W2 | conserto 2 | warnIfAccessibilityMissing | main | sem `render(.blocked)` | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| W3 | conserto 2 | warnIfAccessibilityMissing | main | sem `requestAccessibilityPermission()` | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| W4 | conserto 2 | warnIfAccessibilityMissing | main | saída antes do pedido | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| G1 | conserto 2 | avisos | main | Acessibilidade: `guard !permissionAlertGate.begin()` | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| G2 | conserto 2 | avisos | main | microfone: sem o `defer` do portão | morre (microphoneWiring) | morre (microphoneWiring) |
| D1f | conserto 2 | avisos | main | espera: sem o portão (D1f) | morre (undeterminedMicrophoneWiring) | morre (undeterminedMicrophoneWiring) |
| R1 | conserto 2 | avisos | main | Acessibilidade: `runModal() !=` | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| R2 | conserto 2 | avisos | main | microfone: sem `openMicrophoneSettings()` | morre (microphoneWiring) | morre (microphoneWiring) |
| R3 | conserto 2 | avisos | main | Acessibilidade abre a página do microfone (ramos trocados) | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| R4 | conserto 2 | avisos | main | microfone: `runModal() !=` | morre (microphoneWiring) | morre (microphoneWiring) |
| D1e | conserto 2 | avisos | main | espera: saída antes do `runModal` (D1e) | morre (undeterminedMicrophoneWiring) | morre (undeterminedMicrophoneWiring) |
| S17 | conserto 2 | avisos | main | `if microphoneRequest.isPending { return }` antes do aviso do negado (S17) | morre (microphoneWiring) | morre (microphoneWiring) |
| R5 | conserto 2 | avisos | main | Acessibilidade: saída antes do aviso | morre (accessibilityWarningWiring) | morre (accessibilityWarningWiring) |
| GC1 | conserto 2 | avisos | dict | Core: `begin()` sempre verdadeiro | morre (warningPresentationRejectsReentry) | morre (warningPresentationRejectsReentry) |
| GC2 | conserto 2 | avisos | dict | Core: `end()` vazio | morre (warningPresentationRejectsReentry) | morre (warningPresentationRejectsReentry) |
| MC1m | conserto 2 | menu | main | `microphone: .authorized` (constante) | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| MC2m | conserto 2 | menu | main | `accessibilityAuthorized: true` (constante) | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| MC3m | conserto 2 | menu | main | Acessibilidade negada | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| MC4m | conserto 2 | menu | main | sem a linha `permissions:` ao abrir | morre (menuPermissionConditionsWiring) | morre (menuPermissionConditionsWiring) |
| ML1 | conserto 2 | menu | menu | Core: `if conditions.accessibilityAuthorized` (negado) | morre (accessibilityMissing, bothPermissionsMissing, handsFreeOff, microphoneMissing, nothingTranscribedYet, optionShowsTheDiagnostics, theDefaultMenu, undeterminedMicrophoneAsksAgain) | morre (accessibilityMissing, bothPermissionsMissing, handsFreeOff, microphoneMissing, nothingTranscribedYet, optionShowsTheDiagnostics, theDefaultMenu, undeterminedMicrophoneAsksAgain) |
| ML2 | conserto 2 | menu | menu | Core: indeciso oferece a página (ramos trocados) | morre (bothPermissionsMissing, undeterminedMicrophoneAsksAgain) | morre (bothPermissionsMissing, undeterminedMicrophoneAsksAgain) |

### Marco E4: prova final (10:20)
* `swift build`: exit 0. `swift test`: exit 0, **298 testes em 32 suítes, passou** (296 da reauditoria 2 mais `menuItemsWiring` e `settingsPagesWiring`; `launchPermissionsWiring` renomeado para `launchWiring`, `modelLoadWiring` encolhido, não somados).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Build limpo `swift build --build-tests --scratch-path <scratchpad>/conserto3-1b/build-clean` (exit 0) + `python3 scripts/count-swift-warnings.py <log>`: **4**, a mesma lista (`AudioRecorder.swift` 1:1, 402:29, 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* Travessão e aspas curvas nas linhas adicionadas em `Sources` e `Tests`: 0.
* `git status --short`: `estado-consultado.md`, este progresso, `main.swift` e `MenuLayoutTests.swift` modificados; `?? models`. `git diff --stat` em `docs/`, `scripts/`, `Package.swift`, README, `Sources/NeverTypeCore/` e `Tests/NeverTypeCoreTests/Audit/`: vazio. Sondas d0eca29d e b05faa3d, intactas e verdes.

### Decisões do conserto 3
* Corpo inteiro, não janela: os três oráculos (`launchWiring`, `menuPermissionConditionsWiring`, `menuItemsWiring`) comparam `codeLines(body)` com a lista completa, como o `handle` e o `expectAlert`. O custo é o mesmo que a reauditoria 2 descreveu: mudar qualquer linha de código de `applicationDidFinishLaunching`, `rebuildMenu` ou `item(for:)`, inclusive o que não é de permissão (o texto do menu, o `log("ready…")`), pede mudar a lista no mesmo commit. Comentário só de linha não conta (o `body(of:)` já os tira); comentário no fim de uma linha presa deixa o teste vermelho.
* Uma lista para cada corpo, sem repetir: a janela do modelo e a das permissões deixaram de existir à parte, e `modelLoadWiring` ficou só com a conferência de que o `modelState` é gravado num lugar só (essa olha o arquivo inteiro, não o corpo).
* A condição das mutações novas é `ProcessInfo.processInfo.processIdentifier` (sempre maior que zero), e não `statusItem`, porque vale antes de o `statusItem` existir: assim a saída e o `if` cabem em todo ponto, da trava de instância em diante.
* Comportamento do app: sem mudança. B8 é comentário; B9 tira uma propriedade privada sem chamador (o build passa e nenhuma linha de código dos corpos presos mudou); os testes só leem o fonte. Nada a declarar como ressalva.
* Sondas presas à forma: nenhuma das sondas da auditoria olha o `main.swift`; nada a registrar.

### Fora da parte (conserto 3)
* B1 (X-PW8 e P3, o intervalo de um segundo) segue sem prova possível sem relógio; B3, B4 e B6 seguem como tarefa.
* `micAuthorized` ainda aparece em documentos históricos fora do perímetro: `.vibeflow/specs/abrir-com-o-sistema.md` (181), `.vibeflow/prds/abrir-com-o-sistema.md` (110) e `.vibeflow/prompt-packs/titulo-do-hands-free-com-a-segunda-tecla.md` (55). São registro de quando foram escritos; se a orquestração quiser, vira tarefa.
* `MicrophoneAccess.current` (parte 1) segue sem oráculo de texto, como o conserto 2 já anotou.

### Comandos de prova (conserto 3)
* `cd ~/Projects/apps/never-type-permissoes && swift test --filter "StatusIconTests|MenuLayoutTests|PermissionsTests|DictationAttemptTests|PermissionsPart1AuditTests|PermissionsPart1bAuditTests"`
* `cd ~/Projects/apps/never-type-permissoes && python3 -I <scratchpad>/conserto3-1b/sweep.py depois <scratchpad>/conserto3-1b/bak1 <saida>.jsonl [ids]` (e o mesmo com `conserto3-1b/re2/sweep.py` e `conserto3-1b/c2/sweep.py`; `SWEEP_FILTER=.` roda a suíte inteira; tabela por `conserto3-1b/table.py`)
* `cd ~/Projects/apps/never-type-permissoes && swift build && swift test`
* `cd ~/Projects/apps/never-type-permissoes && python3 scripts/test-count-swift-warnings.py`

## Estado do conserto 3: FEITO (o teste manual do TCC segue com o Pedro)
