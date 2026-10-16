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
