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
