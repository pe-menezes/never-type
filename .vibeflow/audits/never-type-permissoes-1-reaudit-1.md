# never-type-permissoes · parte 1 · reauditoria 1

Estado: CONCLUÍDA (16/10/2026)

## Veredito: PASS

Os seis achados que o conserto 1 devia fechar (D1, B1, B2, L1, L2, L4) estão fechados, cada um com prova na suíte. A metade do B2 que fala do `verify-install.sh` estava sem prova (a sabotagem V5 sobrevivia); escrevi uma sonda de comportamento para ela, que mata V5 e passa no código entregue. Nenhum defeito novo no diff do conserto. Ficam quatro achados de baixo risco (N1 a N4), que viram tarefa e não seguram o PASS. Um deles (N3) só o Mac real decide: se o passo manual 4 mostrar o gatilho mudo, ele vira defeito.

Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-microfone`, base da reauditoria `bb3c25c`, conserto não commitado. Nenhuma fonte do executor foi alterada: depois da última sabotagem e de novo no fim, os shas são `main.swift` 1e97f72e, `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da, `MenuLayout.swift` 1c7a6dec e `verify-install.sh` aaff595d, iguais aos do briefing e aos meus backups. Escrevi só neste relatório e em `Tests/NeverTypeCoreTests/Audit/PermissionsPart1AuditTests.swift` (uma sonda nova).

## Escopo
Li o diff inteiro do conserto (pacote `never-type-permissoes-1-pacote-conserto-1.md`, 13 arquivos). Tudo o que mudou responde a D1, B1, B2, L1, L2 ou L4, e L3, L5 e L6 não foram tocados. Por isso não refiz a auditoria inteira.

## Achados da auditoria

### D1 (defeito): FECHADO
* **Core:** `DictationAttempt.decide` ganhou `microphoneRequestPending`. Com o microfone `notDetermined` e um pedido em andamento, a decisão é `.showMicrophoneWaitingAlert`, que vem antes da Acessibilidade (`DictationAttempt.swift` 33 a 35). `MicrophoneRequest` (`Permissions.swift` 85 a 129) guarda o pedido em andamento do processo. Com um pedido já aberto, `askAgain` avisa na hora e não pede de novo. Sem pedido aberto, ele pede e avisa uma vez se a espera, que entra por parâmetro, acabar antes da resposta. A permissão continua lida do sistema a cada vez.
* **Testes que seguram o pedido aberto e encerram a espera pelo parâmetro, sem relógio:** `askingAgainWhilePendingAlertsAtOnce`, `noAnswerWithinTheWaitAlerts`, `answerWithinTheWaitIsSilent` e `launchRequestIsInFlight` em `PermissionsTests`; `pendingRequestShowsTheWaitingAlert` (com e sem Acessibilidade), `noPendingRequestKeepsAccessibilityFirst`, `answeredMicrophoneIgnoresThePendingFlag` e `transcriptionWaitsBeforeThePendingRequest` em `DictationAttemptTests`.
* **Ligação no `main.swift`:** a abertura pede por `microphoneRequest.ask`, o gatilho passa `microphoneRequest.isPending`, o caso `.showMicrophoneWaitingAlert` chama o aviso, e `askAgainForMicrophone` liga o `onNoAnswer` ao aviso. O aviso tem o título, o texto e o botão único decididos, atrás do mesmo `permissionAlertGate`. As sabotagens D1a, D1b, D1d, V1, V2 e V8 morreram (tabela abaixo).

### B1 (buraco em código de risco): FECHADO
S14, S15, S16 e S17 deixam a suíte vermelha, cada uma, e cada caminho novo do D1 também (D1a: aviso com pedido em andamento; D1b: aviso depois da espera). Os oráculos agora procuram a chamada dentro do corpo do `case` ou da função que tem de fazê-la (`MenuLayoutTests.body(of:in:)`), e não mais em qualquer lugar do arquivo. O limite que sobra, típico de oráculo de texto, está em N2.

### B2 (buraco em código de risco): FECHADO, com uma sonda desta reauditoria
* **Menu:** com o microfone `notDetermined` aparece `.askForMicrophone` ("Ask for Microphone Access…"), que pede de novo pelo mesmo caminho do gatilho. Negado e restrito seguem com "Open Microphone Settings…". Provado por `undeterminedMicrophoneAsksAgain` e `bothPermissionsMissing`, e a sabotagem C6 do executor morre. O item "Ask…" apontado para os Ajustes (B2m) também morre em `microphoneWiring`.
* **INSTALL nos dois idiomas** (sonda de estado, fica no relatório): `grep` de "turn on NeverType" e "ligue o NeverType" só acha o braço **denied** (`INSTALL.md` 175, `INSTALL.pt-BR.md` 170) e o passo da Acessibilidade (`INSTALL.pt-BR.md` 190). O braço "never answered" manda fechar e abrir o app e diz por que não mandar aos Ajustes.
* **`verify-install.sh`, `notDetermined`** (linhas 165 a 167): "Quit NeverType and open it again: it asks for the microphone at launch." A frase dos Ajustes saiu. **Faltava prova:** a sonda da auditoria só exige a frase nova e não confere que a velha sumiu. A sabotagem V5, que põe de volta "open System Settings › Privacy & Security › Microphone and turn on NeverType" no braço `notDetermined`, sobrevivia à suíte. Escrevi a sonda `neverAnsweredIsNotSentToTheMicrophonePage` (abaixo): ela mata V5 e passa no código entregue.
* Fica para o Mac real se o "feche e abra de novo" faz o macOS mostrar o pedido (passo manual 9).

### L1: FECHADO
`docs/reference.md` 331 a 340 descreve as linhas por estado: Acessibilidade com "Open Accessibility Settings…"; microfone nunca respondido com "Ask for Microphone Access…" e o aviso de espera de botão único; negado ou restrito com "Open Microphone Settings…". A descrição bate com o `MenuLayout` e o `main.swift`.

### L2: FECHADO
`verify-install.sh` 201 a 205: os Ajustes só são oferecidos para a Acessibilidade e para o microfone negado ou restrito; para o nunca respondido, o texto diz que o app pede de novo e, sem resposta, manda fechar e abrir. Isso bate com o código. A quebra de linha ficou torta (N4).

### L4: FECHADO
`.timeLimit(.minutes(1))` em todo teste de `PermissionsTests` que espera continuação. Os testes também deixaram de depender dele: `Journal.holdsAnswer: false` onde nenhum pedido deveria acontecer, o segundo pedido volta na hora, e a espera conta voltas em vez de esperar `running.value`. Reapliquei S5, a sabotagem que travou a suíte por 10 min na auditoria: morre em 0,71 s. Também S5b (pede sempre, qualquer que seja o estado): morre em 0,73 s. Nenhuma das minhas 17 sabotagens travou.

### L3, L5, L6
Ficaram fora do conserto por decisão escrita no briefing dele. Não reabri.

## As duas notas do executor

1. **"O `.timeLimit` não derruba teste preso numa continuação que nunca volta."** Não reproduzi a medida (4 min 11 s): ela é do executor. O que conferi foi o que importa para a suíte, que nenhum teste novo espera uma continuação que pode não voltar. Os testes de `MicrophoneRequest` rodam o pedido numa `Task` solta, esperam por voltas limitadas e retomam o que abriram. Sobram dois `await` sobre continuação. `accessibilityWaitsForTheMicrophone` espera `running.value`, mas o próprio teste retoma o pedido e um segundo pedido volta na hora. A sonda `answerFromBackgroundQueue` é retomada por `DispatchQueue.global()` dentro do mesmo fecho, então sempre volta. Nas 17 sabotagens nada travou.
2. **"O plano B saiu do bloco de fala e foi para o texto do agente."** A regra de língua é respeitada: `INSTALL.md` em inglês, `INSTALL.pt-BR.md` em português, espelhados frase a frase com o mesmo conteúdo nos dois braços (nunca respondido: fechar e abrir, sem mandar aos Ajustes, com o motivo; negado: Ajustes › Microfone). O pt-BR acrescenta entre parênteses as palavras em inglês que o verify imprime (`never answered`, `denied`), o que ajuda o agente a casar a saída. O bloco de fala continua existindo (só "clique em Permitir"), então a contagem de blocos lidos em voz alta do `CLAUDE.md` não muda. Consequência registrada, que não é achado: no plano B, o que se diz à pessoa agora é improvisado pelo agente a partir da instrução, e não lido literalmente.

## Achados novos (todos baixo risco, viram tarefa)

* **N1 (baixo): a duração da espera não tem prova.** As sabotagens V3 (`askAgainForMicrophone` passa `wait: { }`, e o aviso aparece na hora em todo novo pedido, por cima do pedido do sistema) e V4 (`tenSeconds` vira `.seconds(600)`, e o gatilho fica 10 min sem retorno) sobrevivem. Os dois caminhos do D1 estão provados; o valor de 10 s e o uso do padrão no `main.swift` não. As duas regressões exigem editar de propósito uma constante com nome ou acrescentar um argumento. Um teste do valor precisaria de relógio, que a régua proíbe; resta um oráculo de texto que confira a ausência de `wait:` no corpo de `askAgainForMicrophone`.
* **N2 (baixo): o oráculo de texto aceita chamada comentada.** S14c (`// self?.showMicrophoneRequiredAlert()`) sobrevive, porque `body(of:in:)` procura por substring. É o limite conhecido do padrão `verificacao-estrutural`. Ignorar linhas que começam com `//` no `body(of:in:)` fecharia este caso.
* **N3 (baixo, o Mac real decide): pedido que volta sem resposta não mostra aviso.** `askAgain` trata "o pedido voltou" como "a pessoa respondeu": se `AVCaptureDevice.requestAccess` voltar sem mostrar nada e o estado continuar `notDetermined`, a espera é cancelada e cada gatilho mostra só o ícone e a linha `microphone not answered yet: recording did not start, asking again`. Não conheço um mecanismo que produza isso com o build desta frente: o `build-app.sh` assina com `com.apple.security.device.audio-input` (linhas 407 a 419), e a contraprova da auditoria sugere que na origem o estado era negado. Endurecimento possível: em `askAgainForMicrophone`, depois do pedido, mostrar o aviso de espera se `MicrophoneAccess.current` ainda for `notDetermined`. **Se o passo manual 4 mostrar esse caminho, vira defeito.**
* **N4 (baixo, texto):** `verify-install.sh` 204 tem 109 colunas no texto impresso à pessoa ("alert says to quit NeverType and open it again. The menu also says …"), enquanto o resto do bloco quebra em cerca de 80.

## Sabotagens desta reauditoria

Script `scratchpad/reaudit1/scripts/rsab.py`, com backups meus em `scratchpad/reaudit1/bk/`. Antes de cada mutação o script confere o sha da fonte contra o backup. Depois aplica, compila, roda `DictationAttemptTests|MenuLayoutTests|PermissionsTests|TranscriptionSessionTests|PermissionsPart1AuditTests` com limite de 240 s, restaura por cópia e confere o sha. Saídas em `scratchpad/reaudit1/rsab.txt`, `rsab-v5.txt` e `rsab-s5.txt`.

| id | mutação | resultado | quem pegou |
|---|---|---|---|
| S14 | gatilho negado sem `showMicrophoneRequiredAlert()` | morta | `microphoneWiring` |
| S15 | gatilho indeciso sem `askAgainForMicrophone()` | morta | `undeterminedMicrophoneWiring` |
| S16 | sem a linha `permissions:` antes dos pedidos da abertura | morta | `permissionLineWiring` |
| S17 | `if microphoneRequest.isPending { return }` antes do aviso do negado (variante minha) | morta | `microphoneWiring` |
| D1a | caso `.showMicrophoneWaitingAlert` sem o aviso | morta | `undeterminedMicrophoneWiring` |
| D1b | `onNoAnswer: { }` | morta | `undeterminedMicrophoneWiring` |
| D1d | `microphoneRequestPending: false` no gatilho | morta | `undeterminedMicrophoneWiring` |
| V1 | caso `.showMicrophoneWaitingAlert` pede de novo em vez de avisar | morta | `undeterminedMicrophoneWiring` |
| V2 | `ask` sem `defer { isPending = false }` | morta | `launchRequestIsInFlight` |
| V8 | `askAgain` com pedido aberto retorna sem avisar | morta | `askingAgainWhilePendingAlertsAtOnce` |
| S5 | abertura pede de novo o negado e o restrito | morta em 0,71 s, sem travar | `answeredMicrophoneIsNotAsked` |
| S5b | abertura pede sempre | morta em 0,73 s | `answeredMicrophoneIsNotAsked`, `grantedAccessibilityIsNotAsked` |
| V5 | verify `notDetermined` volta a mandar aos Ajustes › Microfone | sobrevivia; **morta** com a sonda nova | `neverAnsweredIsNotSentToTheMicrophonePage` |
| S14c | chamada do aviso do negado comentada | **sobrevive** | N2 |
| V3 | `wait: { }` em `askAgainForMicrophone` | **sobrevive** | N1 |
| V4 | `tenSeconds` vira 600 s | **sobrevive** | N1 |

## Sonda nova (`PermissionsPart1AuditTests.neverAnsweredIsNotSentToTheMicrophonePage`)

O teste roda o `verify-install.sh` num HOME temporário com a linha que o Core formata, uma vez para `notDetermined` e uma vez para `denied`. Ele exige que a seção de permissões do caso nunca respondido não contenha "Privacy & Security › Microphone" nem "turn on NeverType", e que o caso negado, que é o controle, contenha a página.
* **Contrato que protege:** B2. Com o microfone nunca respondido, nada manda a pessoa à página do Microfone, onde o app pode não estar e não existe botão "+".
* **Regressão que a derruba:** alguém devolve ao braço `notDetermined` a frase de plano B que estava lá até este conserto (sabotagem V5, morta). Se o braço negado perder a página, o controle falha, e a sonda não passa vazia.
* **Por que o teste do executor não pega:** nenhum teste do executor roda o script, e a sonda `scriptReadsTheCoreLine` só exige a presença da frase nova, nunca a ausência da velha.

`checa-sondas.py --pasta Tests/NeverTypeCoreTests/Audit`: 0 trecho suspeito.

## Para o teste manual do Pedro

Num Mac real, com o app desta branch instalado. O `build-app.sh`, o `install.sh` e o `tccutil` são passos dele.

1. **Primeira abertura com os dois indecisos.** Faça: `tccutil reset Microphone com.nevertype.app` e `tccutil reset Accessibility com.nevertype.app`, depois abra o app. Deve ver: primeiro o pedido do microfone, sozinho, e o da Acessibilidade só depois de responder. No `nevertype.log`, `permissions: microphone=notDetermined accessibility=missing` antes de `ready.`, e outra linha `permissions:` depois da resposta. Deixando o pedido do microfone sem resposta por 1 minuto, o da Acessibilidade não aparece. Isso é o L5, decidido assim.
2. **Gatilho com o pedido da abertura aberto e a Acessibilidade faltando** (D1, primeiro caminho). Faça: repita o passo 1 e, sem responder ao microfone, aperte o gatilho; com o aviso aberto, aperte de novo. Deve ver: o aviso "NeverType is waiting for the microphone answer", com o texto "Recording did not start. The macOS prompt may be behind other windows…" e um botão só, OK. Não deve aparecer o aviso da Acessibilidade nem os Ajustes. O segundo toque não empilha outro aviso. No log: `microphone request still open: recording did not start` e `microphone: waiting alert shown`. Anote se o aviso cobre o pedido do sistema (o aviso chama `NSApp.activate`) e se, depois do OK, dá para responder ao pedido. Respondido o microfone, o pedido da Acessibilidade vem em seguida.
3. **O mesmo com a Acessibilidade concedida.** Faça: resete só o microfone, abra o app, não responda e aperte o gatilho. Deve ver: o mesmo aviso de espera, na hora.
4. **Gatilho sem pedido aberto** (D1, segundo caminho, e N3). Faça: com o app aberto e o microfone já respondido, rode `tccutil reset Microphone com.nevertype.app` e aperte o gatilho. Deve ver: o pedido do sistema, e nenhum aviso se você responder em menos de 10 s. Repita o reset e não responda: em cerca de 10 s, o aviso de espera, uma vez só. **Se o pedido não aparecer, nenhum aviso vier e o log só repetir `microphone not answered yet: recording did not start, asking again` com o estado ainda `notDetermined`, N3 vira defeito.**
5. **Menu por estado** (B2). Faça: abra o menu com o microfone nunca respondido, depois negado, depois concedido. Deve ver: "Microphone: missing" com "Ask for Microphone Access…" embaixo, que mostra o pedido do sistema (ou o aviso de espera se já houver pedido aberto); negado, "Microphone: missing" com "Open Microphone Settings…", que abre a página do Microfone; concedido, nenhuma das duas linhas.
6. **Microfone negado.** Faça: negue no pedido e aperte o gatilho; com o aviso aberto, aperte de novo. Deve ver: o aviso "NeverType needs Microphone access", com "Open System Settings" abrindo a página do Microfone, e o segundo toque sem segundo aviso.
7. **Linha de log na mudança.** Faça: com o app aberto, ligue o microfone nos Ajustes e abra o menu duas vezes. Deve ver: uma linha `permissions:` nova com `microphone=authorized` na primeira abertura, e nenhuma repetição na segunda.
8. **Verify.** Faça: com o app vivo, rode `bash scripts/verify-install.sh` em cada estado. Deve ver: a seção "Permissions (as NeverType last read them)" coerente com o estado. No nunca respondido, "Quit NeverType and open it again: it asks for the microphone at launch.", sem mandar aos Ajustes. No negado, a página do Microfone. O código de saída não muda com a permissão.
9. **O plano B novo funciona?** Faça: com o microfone nunca respondido (reset), feche o NeverType pelo menu e abra de novo. Deve ver: o pedido do microfone na abertura. É a saída que os INSTALL e o verify agora dão: se o pedido não vier nem assim, o plano B não tem saída e isso volta para a frente. Aproveite para abrir Ajustes › Privacidade e Segurança › Microfone e anotar se o NeverType está na lista nesse estado (a pergunta de fundo do B2).
10. **Segunda abertura.** Faça: com o app vivo, `open /Applications/NeverType.app`. Deve ver: a cópia viva ativada, o `nevertype.log` sem encolher (`wc -l` antes e depois) e a última linha `permissions:` ainda lá.

## Comandos rodados

* `git status --short` (início e fim): os 13 arquivos do conserto, `?? models` e, no fim, este relatório. O arquivo de sondas já constava como modificado pelo conserto (linha autorizada) e agora tem também a minha sonda.
* `shasum` das fontes e `cp -p` para `scratchpad/reaudit1/bk/`: 1e97f72e, 44236b27, a3aa59da, 1c7a6dec e aaff595d, iguais ao briefing.
* `swift build && swift test` antes da sonda: exit 0, **268 testes em 30 suítes, passou** (pulos: as suítes condicionais de transcrição local e de ditado gravado).
* `swift test --skip-build --filter PermissionsPart1AuditTests` antes da sonda: exit 0, **7 testes, passou**; depois da sonda: **8 testes, passou**.
* `python3 -I scratchpad/reaudit1/scripts/rsab.py scratchpad/reaudit1/bk [ids]`, três rodadas, 17 mutações: resultados na tabela. Todas restauradas, com o sha conferido em cada uma e no fim.
* `swift build && swift test` depois da sonda (uma vez): exit 0, **269 testes em 30 suítes, passou**.
* `python3 <vault>/.claude/scripts/loop-dev/checa-sondas.py --pasta Tests/NeverTypeCoreTests/Audit .`: 1 arquivo, 0 trecho suspeito.
* `swift build --build-tests --scratch-path scratchpad/reaudit1/build-clean` + `python3 scripts/count-swift-warnings.py`: build exit 0, **4** warnings, os mesmos quatro (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28). Scratch apagado.
* `git diff -U0 bb3c25c` nas linhas adicionadas: 0 travessão e 0 aspas curvas.
* `grep` de "turn on NeverType", "ligue o NeverType" e "Microphone" em `docs/`, `README*` e `scripts/`, e `awk` de largura no `verify-install.sh`: ver B2 e N4.
