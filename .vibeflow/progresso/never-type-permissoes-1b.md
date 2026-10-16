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
