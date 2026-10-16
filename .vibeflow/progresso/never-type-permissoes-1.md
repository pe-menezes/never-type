# never-type-permissoes · parte 1 · progresso do executor

Briefing: vault `.claude/threads/never-type-permissoes-executor-1-briefing.md`. Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-microfone`, base `832264a`.

## Marco 0: leitura e linha de base (15/10)
* Lidos: briefing, CLAUDE.md, `.vibeflow/index.md`, `conventions.md`, padrões `estado-consultado` e `nucleo-testavel`, `docs/pitfalls.md` (requestAccess), dev-remoto princípios 1, 3, 4 e 6.
* Linha de base de warnings: `swift build --build-tests --scratch-path <scratchpad>/build-base` (build limpo, exit 0) e `python3 scripts/count-swift-warnings.py <log>` = **4** (AudioRecorder.swift 1:1, 402:29, 402:41; PasteTarget.swift 159:28).

## Marco 1: vermelho (15/10)
* Testes novos/alterados: `DictationAttemptTests` (não decidido pede de novo; negado e restrito avisam; Acessibilidade na frente), `MenuLayoutTests` (linha `openMicrophoneSettings`, oráculo de texto do `main.swift`), `PermissionsTests` novo (ordem da abertura com o pedido do microfone segurado aberto pelo teste; formato e escrita-na-mudança da linha `permissions:`).
* Para o vermelho ser de comportamento e não de compilação, entrou primeiro um esboço com o comportamento de hoje (`Permissions.swift` sem esperar o microfone, `decide` com um caso só, linha de menu que não aparece).
* `swift test --filter "DictationAttemptTests|MenuLayoutTests|PermissionsTests"`: **34 testes, 23 issues, falhou**. Entre eles: `(decision → .showMicrophoneWarning) == .requestMicrophoneAccess`; a ordem de hoje reproduzida `["check accessibility", "ask accessibility", "ask microphone"]`; o menu sem `openMicrophoneSettings`; o oráculo de texto acha as duas chamadas lado a lado.
* Fora do perímetro tocado: `Tests/NeverTypeCoreTests/TranscriptionSessionTests.swift`, só o rótulo `microphoneAuthorized: true` → `microphone: .authorized` nas duas chamadas de `decide` (a assinatura mudou; asserção igual).

## Marco 2: verde no código (15/10)
* `Sources/NeverTypeCore/Permissions.swift` (novo): `MicrophoneAccess` (quatro respostas, `current` consultado no sistema), `LaunchPermissions.run` (espera o microfone antes de olhar a Acessibilidade; chamadas de sistema por parâmetro), `PermissionLog` (formato da linha e escrita só quando muda; guarda só a última linha escrita, nunca decide permissão).
* `DictationAttempt.decide(microphone:accessibilityAuthorized:isTranscribing:)`: `.notDetermined` → `.requestMicrophoneAccess`; `.denied/.restricted` → `.showMicrophoneWarning`; Acessibilidade continua na frente.
* `MenuLayout`: `.openMicrophoneSettings` logo abaixo de `.microphoneMissing`.
* `main.swift`: abertura por `LaunchPermissions.run` dentro de um `Task @MainActor`; `askForMicrophone()` com a API async (armadilha do `requestAccess` preservada no comentário); gatilho pede de novo (não decidido) ou abre o aviso modal com "Open System Settings" para `Privacy_Microphone` (negado/restrito); item de menu "Open Microphone Settings…"; linha `permissions:` na abertura, depois dos pedidos, em cada gatilho e a cada abertura do menu; o portão de aviso virou um só para as duas permissões (`permissionAlertGate`).
* `swift test --filter "DictationAttemptTests|MenuLayoutTests|PermissionsTests|TranscriptionSessionTests"`: **37 testes em 4 suítes, passou**.

## Marco 3: instalação e script (15/10)
* `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md`: abertura pede um de cada vez (microfone primeiro); plano B no passo do microfone (sem pedido em uns 10 s, Ajustes › Privacidade e Segurança › Microfone e ligar o NeverType); passo 5 diz que o verify lê a linha `permissions:` como aviso, sem mudar o código de saída.
* `scripts/verify-install.sh`: seção "Permissions (as NeverType last read them)" antes da contagem de problemas, lê a última linha `^nevertype: permissions: ` de `$HOME/Library/Application Support/NeverType/nevertype.log` e usa só `ok`/`warn`. Sem variável nova: a prova troca o `HOME`.
* `docs/reference.md`: só a linha do verify na tabela de scripts.
* Prova do script num diretório temporário (scratchpad, apagado no fim), `HOME=<tmp> bash scripts/verify-install.sh`, seis logs falsos × com e sem modelo (modelo por `cp -c`, clone APFS; o link simbólico falhou porque `stat -f%z` mede o link):
  * sem log: aviso "no permissions line"; authorized/granted: dois ok; notDetermined: aviso com o plano B dos 10 s; denied + accessibility missing: dois avisos; restricted: aviso "ask whoever manages this Mac"; várias linhas: vale a última.
  * código de saída: **0 nos seis com modelo, 1 nos seis sem modelo**. A permissão nunca mexe no código.

## Marco 4: prova final (15/10)
* `swift build && swift test`: exit 0, **250 testes em 29 suítes, passou** (pulos são as suítes condicionais de sempre: transcrição local e ditado longo gravado).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Warnings em build limpo (`swift build --build-tests --scratch-path <scratchpad>/build-final` + `count-swift-warnings.py`): **4, igual à linha de base**, os mesmos quatro.
* Travessão e aspas curvas: nenhum nas linhas novas (grep no diff e nos arquivos novos).

## Decisões
* `decide` trocou o `Bool` por `MicrophoneAccess` (sem sobrecarga com `Bool`, que esconderia de novo a diferença). Custo: o rótulo em `TranscriptionSessionTests.swift`, fora do perímetro escrito.
* `PermissionLog` guarda a última linha escrita para não repetir no log a cada tecla. Não é estado de permissão: nunca decide nada, toda leitura vem do sistema na hora. Se o Pedro ler "nunca guardada" de forma estrita, a alternativa é escrever a linha em todo gatilho e abertura de menu.
* "Sempre que mudar" = nos momentos em que o app olha (abertura, resposta de cada pedido, cada gatilho, cada abertura do menu). Sem timer e sem notificação do sistema; mudança feita nos Ajustes aparece no próximo desses momentos.
* Um portão de aviso só para as duas permissões (`permissionAlertGate`, antes `accessibilityAlertGate`): nunca dois modais empilhados.
* Microfone restrito mostra o mesmo aviso do negado (como pede o briefing), embora o interruptor dos Ajustes não seja da pessoa nesse caso; o verify diz isso com todas as letras.

## Fora da parte
* `docs/reference.md` linhas ~331 a 335 ainda dizem que o microfone não tem item próprio no menu e que o macOS pede uma vez; ficou falso. O perímetro só liberava a linha do verify.
* `docs/pitfalls.md` não ganhou a lição: a causa no Mac da pessoa segue sem log (a conferir); vale registrar depois do teste manual.
* "Open Microphone Settings…" com o microfone **não decidido**: o NeverType pode nem estar na lista dos Ajustes até o primeiro pedido; talvez o item devesse pedir de novo nesse caso. Não mexi.
* Teste manual do Pedro (fora do meu alcance: `build-app.sh`, `install.sh`, `tccutil` proibidos): abrir com microfone não decidido e ver os pedidos em sequência; negar e apertar o gatilho para ver o aviso; conferir a linha `permissions:` no `nevertype.log`.

## Comandos de prova
* `cd ~/Projects/apps/never-type-permissoes && swift test --filter "DictationAttemptTests|MenuLayoutTests|PermissionsTests|TranscriptionSessionTests"`
* `cd ~/Projects/apps/never-type-permissoes && swift build && swift test`
* `cd ~/Projects/apps/never-type-permissoes && python3 scripts/test-count-swift-warnings.py`
* verify: criar `<tmp>/Library/Application Support/NeverType/` com `nevertype.log` falso (e `models/` com `cp -c` do modelo real para o caso de saída 0) e rodar `HOME=<tmp> bash scripts/verify-install.sh`

## Estado: FEITO COM RESSALVA (ver Decisões e Fora da parte)

## Conserto 1 (16/10)
Briefing: vault `.claude/threads/never-type-permissoes-conserto-1-briefing.md`. Achados D1, B1, B2, L1, L2, L4 do relatório `.vibeflow/audits/never-type-permissoes-1-audit.md`; L3, L5, L6 fora (decisão do briefing).

### Marco C0: leitura
* Lidos: briefing do conserto, relatório da auditoria, este progresso, CLAUDE.md, pitfalls 120 a 155, padrões `nucleo-testavel`, `estado-consultado`, `verificacao-estrutural`, dev-remoto princípios 1, 6 e 7.
* `git log --oneline -3` (16/10): `bb3c25c`, `00632a4`, `832264a`; `git status --short`: só `?? models` (link do PG).
* Plano: peça nova `MicrophoneRequest` em `Permissions.swift` (pedido em andamento, espera por parâmetro), `decide` ganha `microphoneRequestPending` e o caso `.showMicrophoneWaitingAlert`; `MenuLayout.Conditions` recebe `MicrophoneAccess`; oráculos de texto do `main.swift` por corpo de caso e de função.

### Marco C1: vermelho (16/10)
* Testes novos: `DictationAttemptTests` (pedido em andamento mostra o aviso de espera com e sem Acessibilidade; sem pedido a Acessibilidade fica na frente; microfone já respondido ignora a marca; transcrição espera antes), `PermissionsTests` (`launchRequestIsInFlight`, `askingAgainWhilePendingAlertsAtOnce`, `noAnswerWithinTheWaitAlerts`, `answerWithinTheWaitIsSilent`; a espera de 10 s é uma continuação que o teste retoma, sem relógio), `MenuLayoutTests` (`undeterminedMicrophoneAsksAgain`, `microphoneMissing` com denied e restricted, `bothPermissionsMissing` com os dois estados, oráculos por corpo: `microphoneWiring` reescrito, `undeterminedMicrophoneWiring` e `permissionLineWiring` novos).
* Esboço com o comportamento de hoje (`MicrophoneRequest` que nunca marca pendente e só pede, `decide` ignorando a marca, menu com Settings para todo não autorizado) para o vermelho ser de comportamento.
* `swift test --skip-build --filter "DictationAttemptTests|MenuLayoutTests|PermissionsTests"`: vermelho em 10 testes (decide devolveu `.requestMicrophoneAccess`/`.showAccessibilityWarning` em vez de `.showMicrophoneWaitingAlert`; `isPending` falso; menu com `openMicrophoneSettings` no indeciso; oráculos sem `askAgainForMicrophone`, sem o aviso e sem "Ask for Microphone Access…"; espera nunca iniciada). `permissionLineWiring` passou no esboço: é endurecimento e se prova pela sabotagem S16.
* **Medido no vermelho:** `askingAgainWhilePendingAlertsAtOnce` travou no esboço e o `.timeLimit(.minutes(1))` NÃO o derrubou: 4 min 11 s sem o issue de limite, processo morto por `kill`. Continuação nunca retomada segura o grupo de tarefas do swift-testing. Por isso o L4 virou duas coisas: `.timeLimit` como pede o briefing e, de verdade, testes que não esperam continuação que pode não voltar (`Journal.holdsAnswer: false` onde nenhum pedido deveria acontecer, segundo pedido volta na hora, espera por voltas em vez de `await running.value`).

### Marco C2: verde (16/10)
* `Permissions.swift`: `MicrophoneRequest` (`@MainActor`), `isPending` do processo; `ask(_:)` para a abertura, sem limite (L5); `askAgain(request:wait:onNoAnswer:)`: com pendente chama o aviso na hora e não pede; sem pendente pede e, se a espera (`wait`, padrão `MicrophoneRequest.tenSeconds` = `Task.sleep(10 s)`) acabar com o pedido aberto, chama o aviso uma vez; resposta antes cancela a espera.
* `DictationAttempt`: caso `.showMicrophoneWaitingAlert`, parâmetro `microphoneRequestPending` (padrão `false`, então `TranscriptionSessionTests` não mudou). Com microfone `notDetermined` e pendente, o aviso vem antes da Acessibilidade.
* `MenuLayout`: `Conditions.microphone: MicrophoneAccess` no lugar do booleano; linha `.askForMicrophone` no indeciso, `.openMicrophoneSettings` no negado e no restrito.
* `main.swift`: `microphoneRequest`; abertura pede por `microphoneRequest.ask`; `decide` recebe `microphoneRequest.isPending`; caso `.showMicrophoneWaitingAlert` mostra o aviso; caso `.requestMicrophoneAccess` e o item "Ask for Microphone Access…" chamam `askAgainForMicrophone()`; aviso `showMicrophoneWaitingAlert()` com o título, o texto e o botão OK do briefing, no mesmo `permissionAlertGate`.
* `swift test --skip-build --filter "DictationAttemptTests|MenuLayoutTests|PermissionsTests|TranscriptionSessionTests"`: **48 testes em 4 suítes, passou**. `--filter PermissionsPart1AuditTests`: **7 testes, passou** (com a linha reescrita abaixo).

### Marco C3: script e docs (16/10)
* `verify-install.sh`, `notDetermined`: "Quit NeverType and open it again: it asks for the microphone at launch." mais a frase de que os Ajustes podem não listar o app; saiu o "Hold the trigger once". Texto final (L2): o aviso abre os Ajustes só para Acessibilidade e microfone negado; no indeciso diz para fechar e abrir.
* INSTALL nos dois idiomas: o plano B saiu do bloco de fala e virou instrução ao agente: rodar `bash scripts/verify-install.sh` e seguir; nunca respondido, fechar e abrir; negado, Ajustes › Microfone. Parágrafo seguinte descreve o aviso de espera e as duas linhas do menu por estado.
* `docs/reference.md` (L1): linhas do microfone por estado. A linha do verify na tabela continua certa e não mudou.
* Sonda autorizada, `PermissionsPart1AuditTests.scriptReadsTheCoreLine`, linha `notDetermined`:
  * antes: `(.notDetermined, true, ["microphone: never answered", "about\n      10 seconds", "ok accessibility: granted"])`
  * depois: `(.notDetermined, true, ["microphone: never answered", "Quit NeverType and open it again: it asks for the microphone at launch.", "ok accessibility: granted"])`
  * força igual: continua exigindo o veredito, uma frase que só o braço `notDetermined` imprime e o `ok accessibility: granted`.
* Texto final do verify: "denied or restricted" (o restrito também mostra o aviso com os Ajustes).
* Rodada real do script, `HOME=<scratchpad>/vhome bash scripts/verify-install.sh` com log `microphone=notDetermined accessibility=granted`: imprime o aviso novo e `ok accessibility: granted`; saída 1 por falta de modelo no HOME temporário, como antes. HOME apagado.

### Marco C4: sabotagens (16/10)
Script `<scratchpad>/sab/sab.py`: substitui o trecho, `swift build --build-tests`, roda `DictationAttemptTests|MenuLayoutTests|PermissionsTests|TranscriptionSessionTests|PermissionsPart1AuditTests`, restaura por cópia do backup e confere o sha. Shas no fim, iguais aos backups: `main.swift` 1e97f72e, `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da, `MenuLayout.swift` 1c7a6dec.

| id | mutação | resultado | quem pegou |
|---|---|---|---|
| S14 | gatilho negado sem `showMicrophoneRequiredAlert()` | morta | `microphoneWiring` |
| S15 | gatilho indeciso sem `askAgainForMicrophone()` | morta | `undeterminedMicrophoneWiring` |
| S16 | sem a linha `permissions:` antes dos pedidos da abertura | morta | `permissionLineWiring` |
| S16b | `logPermissionsIfChanged` sem `log(line)` | morta | `permissionLineWiring` |
| S17 | `return` antes do aviso do microfone negado aparecer | morta | `microphoneWiring` |
| D1a | caso `.showMicrophoneWaitingAlert` sem chamar o aviso (pedido em andamento) | morta | `undeterminedMicrophoneWiring` |
| D1b | `onNoAnswer: { }` (aviso depois dos 10 s) | morta | `undeterminedMicrophoneWiring` |
| D1c | abertura pede sem `microphoneRequest.ask` (pendente nunca marcado) | morta | `undeterminedMicrophoneWiring` |
| D1d | `microphoneRequestPending: false` no gatilho | morta | `undeterminedMicrophoneWiring` |
| D1e | `return` antes do `runModal` do aviso de espera | morta | `undeterminedMicrophoneWiring` |
| D1f | aviso de espera sem o `permissionAlertGate` | morta | `undeterminedMicrophoneWiring` |
| B2m | "Ask for Microphone Access…" abrindo os Ajustes | morta | `microphoneWiring` |
| C1 | pendente depois da Acessibilidade em `decide` | morta | `pendingRequestShowsTheWaitingAlert` |
| C1b | pendente sem exigir `notDetermined` | morta | `answeredMicrophoneIgnoresThePendingFlag` |
| C2 | `askAgain` sem o atalho do pendente | morta | `askingAgainWhilePendingAlertsAtOnce` |
| C3 | espera sem conferir cancelamento e pendente | morta | `answerWithinTheWaitIsSilent` |
| C4 | `ask` sem marcar pendente | morta | `launchRequestIsInFlight`, `askingAgainWhilePendingAlertsAtOnce` |
| C5 | `askAgain` sem limpar o pendente | morta | `noAnswerWithinTheWaitAlerts`, `answerWithinTheWaitIsSilent` |
| C6 | menu indeciso com "Open Microphone Settings…" | morta | `undeterminedMicrophoneAsksAgain`, `bothPermissionsMissing` |
| S5 | abertura pede de novo o negado e o restrito (a que travou a suíte 10 min) | morta em 0,75 s, sem travar | `answeredMicrophoneIsNotAsked` |

### Marco C5: prova final (16/10)
* `swift build && swift test`: exit 0, **268 testes em 30 suítes, passou** (257 da rodada auditada mais 11 novos; pulos são as suítes condicionais de sempre).
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* Build limpo `swift build --build-tests --scratch-path <scratchpad>/build-c1` (exit 0) + `count-swift-warnings.py`: **4**, os mesmos quatro (`AudioRecorder.swift` 1:1, 402:29, 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* Nenhuma sonda da auditoria ficou vermelha além da linha autorizada (as 7 de `PermissionsPart1AuditTests` passam).
* Travessão e aspas curvas: nenhum nas linhas adicionadas (`git diff -U0 | grep`).
* `git status --short`: só os 13 arquivos do perímetro e `?? models`.

### Decisões do conserto
* A peça do D1 é `MicrophoneRequest` em `Permissions.swift`, e não só `decide`: a espera e o "uma vez só" precisam de estado do processo entre a chamada e a resposta. `decide` decide o caso (pendente na frente da Acessibilidade); `MicrophoneRequest` decide pedir ou avisar e quando.
* A marca de pendente só vale com o sistema dizendo `notDetermined`: se a resposta já chegou e o pedido ainda não voltou, a leitura do sistema ganha (`answeredMicrophoneIgnoresThePendingFlag`).
* O item "Ask for Microphone Access…" usa o mesmo caminho do gatilho (pede, ou avisa na hora com pedido aberto, ou avisa depois dos 10 s).
* O aviso de espera escreve `microphone: waiting alert shown` no log, depois do portão, para o diagnóstico ver que ele apareceu.
* O plano B dos INSTALL saiu do bloco de fala (lido à pessoa) e foi para o texto do agente, porque "rode o verify" é instrução ao agente. O bloco de fala ficou só com "clique em Permitir".

### Fora da parte
* `.timeLimit` não termina teste preso em continuação nunca retomada (medido no vermelho: 4 min 11 s sem o issue). A sonda `answerFromBackgroundQueue` e `accessibilityWaitsForTheMicrophone` ainda esperam continuação; a segunda ficou à prova da regressão de pedir duas vezes, a sonda está fora do perímetro. Vale uma linha em `docs/pitfalls.md`.
* Teste manual do Pedro para o conserto (o TCC real não entra em teste): (1) microfone resetado, abrir o app, não responder ao pedido e apertar o gatilho: aviso "NeverType is waiting for the microphone answer" na hora, um só, também com a Acessibilidade faltando; (2) pedido dispensado sem resposta e sem pedido aberto: gatilho pede de novo e, sem resposta em 10 s, o mesmo aviso; (3) menu com o microfone indeciso mostra "Ask for Microphone Access…"; negado mostra "Open Microphone Settings…"; (4) ver se o `NSApp.activate` do aviso cobre o pedido do sistema.
* L3, L5 e L6 ficaram como o briefing manda.

## Estado do conserto 1: FEITO (ver Fora da parte: o teste manual do TCC é do Pedro)
