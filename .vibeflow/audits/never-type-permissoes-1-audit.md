# never-type-permissoes · parte 1 · auditoria

Estado: CONCLUÍDA (15/10/2026, por volta das 23:40)

## Veredito: PARTIAL

Cinco dos seis itens "pronto quando" estão cumpridos e provados. O núcleo (`DictationAttempt`, `MicrophoneAccess`, `LaunchPermissions`, `PermissionLog`) está certo, e o `verify-install.sh` se comporta como prometido nos quatro estados do microfone, nos dois da Acessibilidade e sem linha nenhuma. O que segura o PASS:
* **D1 (defeito):** com o microfone não decidido, o gatilho continua sem nenhum retorno visível do app. Se o pedido do sistema não aparece (o caso de origem) ou já está aberto desde a abertura, o gatilho mostra só o ícone, que é o defeito de origem. O executor cumpriu o item 2 do contrato ao pé da letra, então o conserto mexe no contrato, que é decisão de produto e vai ao Pedro antes de qualquer conserto (dev-remoto, princípio 8).
* **B1 (buraco em código de risco):** a ligação do `main.swift` (aviso, novo pedido no gatilho, linha de log) não tem prova. O oráculo de texto do executor passa com a chamada do aviso apagada.
* **B2 (buraco em código de risco, só o Mac real prova):** o plano B (menu, INSTALL, verify) manda a pessoa ligar o NeverType na página do Microfone também no estado não decidido, quando o app talvez nem esteja na lista.

Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-microfone`, base `832264a`, rodada não commitada. Nada do executor foi alterado: as quatro fontes sabotadas voltaram aos shas de antes (`Permissions.swift` 53bdcf43, `DictationAttempt.swift` e4eeb7ce, `verify-install.sh` 06317946, `main.swift` 24e00d82), conferidos depois da última sabotagem e de novo no fim.

## Os seis itens "pronto quando"

1. **`DictationAttempt` distingue microfone não decidido de negado, com teste: CUMPRIDO.** `decide(microphone:accessibilityAuthorized:isTranscribing:)` devolve `.requestMicrophoneAccess` para `.notDetermined` e `.showMicrophoneWarning` para `.denied`/`.restricted` (`DictationAttempt.swift`). Testes `undeterminedMicrophoneAsksAgain` e `refusedMicrophoneWarns`; as sabotagens S1, S2 e S2b morreram no teste do executor.
2. **A ordem dos pedidos na abertura sai de uma peça do Core exercitada por teste: CUMPRIDO.** `LaunchPermissions.run` (`Permissions.swift` 51 a 66), testado por `accessibilityWaitsForTheMicrophone`, que segura o pedido aberto e confere que a Acessibilidade nem é consultada. S6 e S18 morreram. A ligação no `main.swift` (linhas 289 a 298) só tem o oráculo que conta `LaunchPermissions.run(` uma vez (ver B1).
3. **O aviso e a ação de menu do microfone existem, com teste em `MenuLayoutTests`: CUMPRIDO NA EXISTÊNCIA, COM BURACO B1.** A linha `.openMicrophoneSettings` está em `MenuLayout.swift` 160 e 161, e `microphoneMissing`/`bothPermissionsMissing` a testam. O aviso existe em `main.swift` 919 a 932. O oráculo que deveria provar que o gatilho chega ao aviso é vazio (S14).
4. **O formato da linha `permissions:` tem teste: CUMPRIDO.** `lineFormat` compara a linha inteira nos quatro estados, e S10 morreu. As sondas desta auditoria agora prendem também o outro lado do contrato: o script lê a linha que o Core formata.
5. **INSTALL nos dois idiomas e `verify-install.sh` atualizados, com o script provado num diretório temporário com log falso nos quatro casos: CUMPRIDO.** Os dois INSTALL ganharam o plano B espelhado e o verify ganhou a seção "Permissions (as NeverType last read them)". Reproduzi a prova (cenário 8) e ela agora está na suíte. Há imprecisões de texto (L1, L2, L3) e uma dúvida de fundo que só o Mac real tira (B2).
6. **`swift build && swift test` verde e a contagem de warnings não sobe: CUMPRIDO.** A suíte deu 257 testes em 30 suítes, verde (250 do executor mais 7 sondas). O build limpo com `--scratch-path` separado teve 4 warnings, os mesmos quatro da linha de base (`AudioRecorder.swift` 1:1, 402:29 e 402:41, `PasteTarget.swift` 159:28), e nenhum do arquivo de sondas.

## Achados

### D1. Defeito: o gatilho com microfone não decidido volta a não mostrar nada além do ícone

* **Evidência:** `main.swift` 398 a 409. No caso `.requestMicrophoneAccess` o app só faz `render(.blocked)`, escreve no log e chama `askForMicrophone()` (858 a 871), que espera `AVCaptureDevice.requestAccess` sem limite. Todo retorno visível depende do pedido do sistema aparecer, e foi justamente isso que falhou na origem ("o macOS mostrou o pedido de Acessibilidade e não o do Microfone"). A causa no Mac da pessoa segue sem confirmação (o briefing do executor diz "a conferir").
* **Caminhos concretos:**
  * O pedido da abertura ainda está pendente (na tela, escondido ou não desenhado) e a pessoa aperta o gatilho. O segundo `requestAccess` se junta ao primeiro, não abre pedido novo, e o gatilho mostra só o ícone. Cada toque a mais abre mais uma `Task` esperando.
  * O pedido do sistema não aparece de jeito nenhum: todo gatilho mostra só o ícone, para sempre. É o sintoma de origem, idêntico.
  * Na primeira instalação as duas permissões faltam. Como a abertura segura a Acessibilidade até o microfone responder, um gatilho apertado enquanto o pedido do microfone está aberto cai em `.showAccessibilityWarning` (a Acessibilidade vem antes em `decide`), abre o aviso modal e, com "Open System Settings", põe os Ajustes por cima do pedido do microfone. Isso remonta pelo gatilho a mesma corrida que a parte tirou da abertura. Só o Mac real mostra se o pedido do TCC fica coberto.
* **Por que defeito:** o objetivo da parte é que o gatilho sem microfone nunca fique mudo, e no estado não decidido ele fica mudo exatamente quando o pedido do sistema falha, que é o cenário que originou a frente. O item 2 do contrato ("estado não decidido pede de novo") não prevê o pedido que não aparece.
* **Conserto possível (decisão do Pedro, porque muda o item 2):** no gatilho com microfone não decidido, mostrar um aviso do app quando já houver pedido pendente ou quando o pedido não for respondido, com o plano B. Também dá para ligar um limite de espera ao pedido da abertura. Sem teste possível aqui: o comportamento do TCC é passo manual.

### B1. Buraco em código de risco: a ligação do `main.swift` não tem prova, e o oráculo de texto é vazio

* **Evidência:** `MenuLayoutTests.swift` 175, `#expect(source.contains("showMicrophoneRequiredAlert()"))`, casa com a própria declaração `private func showMicrophoneRequiredAlert() {` (`main.swift` 919). Com a chamada apagada do caso negado (S14), o teste continua verde. `case .requestMicrophoneAccess:` (também conferido pelo oráculo) existe por obrigação do `switch` exaustivo e não prova nada.
* **Sabotagens sobreviventes, todas no código de risco listado no briefing:** S14 (gatilho negado sem aviso), S15 (gatilho não decidido sem novo pedido), S16 (sem a linha `permissions:` da abertura) e S17 (aviso que retorna antes de aparecer).
* **O que falta:** o oráculo precisa prender o local da chamada (por exemplo `self?.showMicrophoneRequiredAlert()` dentro do caso `.showMicrophoneWarning`, ou a contagem de ocorrências), e o resto da ligação entra no teste manual. Não escrevi essa sonda: oráculo de texto de fonte é sonda de estado pela régua deste briefing, então fica aqui como recomendação para o conserto.

### B2. Buraco em código de risco (só o Mac real prova): o plano B pode não ter saída no estado não decidido

* **Evidência:** `MenuLayout.swift` 159 a 162 mostra "Open Microphone Settings…" para qualquer microfone não autorizado, inclusive o não decidido. O plano B dos dois INSTALL e a mensagem `notDetermined` do verify (`verify-install.sh` 164 a 167) mandam a pessoa "turn on NeverType" na página do Microfone. Ao contrário da Acessibilidade, a página do Microfone não tem botão "+": se o app ainda não estiver na lista, não há o que ligar.
* **Contraprova parcial:** na origem a pessoa ligou o microfone nos Ajustes à mão, então no Mac dela o NeverType estava na lista. Isso sugere que lá o estado era negado, não indeciso, e nesse caso a parte resolve, com o aviso modal.
* **Decide:** o passo manual 3 abaixo. Se o app não estiver na lista com o estado indeciso, isto vira defeito e o plano B precisa de outra saída. A saída da lista (`tccutil reset`) é do Pedro, não do app.

### Buracos em código de risco fechados por esta auditoria (não seguram o PASS)

O teste do executor não pegava estes, e as sondas agora pegam:
* `MicrophoneAccess.init(_:)` nunca era exercitado. S3 (indeciso lido como negado) e S4 (`@unknown default` lido como indeciso) sobreviviam às 37 verdes.
* `PermissionLog` lembrando todas as linhas em vez da última (S9) passava.
* O `verify-install.sh` não tinha teste na suíte, só a prova manual do executor. S11 (sem `|| true`, o script morre sob `pipefail` no log sem linha), S12 (negado vira `problem`) e S13 (`head` no lugar de `tail`) passavam.

### Baixo risco (viram tarefa)

* **L1:** `docs/reference.md` 331 a 335 seguem dizendo "The microphone has no item of its own: macOS asks for it once, at the first launch". Ficou falso com esta parte, e o perímetro do executor não liberava essa linha.
* **L2:** `verify-install.sh` 200 a 203 diz "With either one missing, a trigger is blocked before recording and an alert offers to open the right System Settings page", o que é falso para o microfone indeciso (o gatilho pede de novo, sem aviso). Na mensagem `notDetermined` (166), "Hold the trigger once: the app asks again" também não vale com a Acessibilidade faltando, porque o gatilho mostra antes o aviso da Acessibilidade.
* **L3:** `scripts/install.sh` 124 ("Open the app and macOS will ask for both") só tem saída para a Acessibilidade e nenhum plano B para o microfone. Está fora do perímetro da parte e é lido pelo agente que instala.
* **L4:** `PermissionsTests.answeredMicrophoneIsNotAsked` trava em vez de falhar quando a regra volta a pedir microfone já respondido (S5: a continuação nunca é retomada; matei o processo de teste depois de 10 min). Falta `.timeLimit`.
* **L5:** a abertura espera `requestAccess` sem limite. Se o pedido nunca volta, a Acessibilidade não é mais pedida na abertura (antes sempre era). A saída existe, mas é outra: o aviso do gatilho e o passo manual da Acessibilidade no INSTALL. Também entra no passo manual 1.
* **L6:** `main.swift` 406 desenha `.idle` depois do novo pedido concedido mesmo quando o ícone estava `.blocked` por outro motivo (modelo ou Metal). O padrão vem de antes (a abertura antiga fazia igual).

## Cenários do briefing

1. **Pessoa no gatilho com microfone indeciso:** ver D1. No primeiro gatilho, com a Acessibilidade concedida: só o ícone cortado, mais um pedido ao sistema que pode ou não aparecer. No segundo: o mesmo. Existe caminho mudo, e é o de origem.
2. **"Open Microphone Settings…" com microfone indeciso:** ver B2.
3. **`docs/reference.md` 331 a 335:** baixo (L1).
4. **`TranscriptionSessionTests.swift`:** confirmado. Só os rótulos mudaram, `microphoneAuthorized: true` para `microphone: .authorized`, nas duas chamadas, que são semanticamente iguais. As asserções (`== .waitForTranscription`, `!startsRecording`, `startsRecording`) ficaram intactas e com a mesma força.
5. **`PermissionLog` não decide nada:** confirmado. `lastWritten` é `private` (`Permissions.swift` 79). O único uso de `permissionLog` no app é `lineIfChanged` dentro de `logPermissionsIfChanged` (`main.swift` 878 a 880), e o retorno só vai para `log(_:)`. Toda decisão lê `MicrophoneAccess.current` e `HotkeyMonitor.hasAccessibilityPermission` na hora (`main.swift` 217, 292, 293, 377, 378, 945).
6. **Armadilha do `requestAccess`:** não sobrou chamada com closure. `grep -n requestAccess` acha só `main.swift` 870, a API async. As closures entregues a `LaunchPermissions.run` não são passadas a API de sistema: o `run` é `@MainActor` e as chama de dentro do próprio isolamento. Tirar o `@MainActor` do `run` não compila (S19: "sending value of non-Sendable type"). A sonda `answerFromBackgroundQueue` faz a resposta chegar por uma fila de fundo, como chega a do TCC, e confere que a Acessibilidade é pedida depois dela e na main. É o caminho indeciso que o pitfall diz que teste com permissão concedida não mostra.
7. **Segunda abertura com o app rodando:** não trunca. `acquireInstanceLock()` roda antes de `startLog()` (`main.swift` 240 a 248). Quem perde o `flock` ativa a cópia viva e chama `NSApp.terminate` sem tocar no log, e não há `applicationWillTerminate`. Prova só por leitura: o alvo executável não tem teste.
8. **`verify-install.sh` em HOME temporário:** com 9 logs falsos no formato medido (`nevertype: ` em toda linha), com e sem modelo (`cp -c` do modelo real), o código de saída deu 1 em todos sem modelo e 0 em todos com modelo. Cada estado recebeu o aviso certo, valeu a última linha, a linha sem o prefixo foi ignorada e o `grep` sem resultado sob `set -euo pipefail` não derruba o script. Script em `scratchpad/verify/run.sh`; os HOMEs foram apagados.

## Sabotagens

Cada uma aplicada por `scratchpad/sab/sab.py` (substitui, compila, roda as suítes do trecho, restaura por cópia do backup e confere o sha). Todas restauradas com o sha conferido.

| id | trecho | mutação | executor | sondas |
|---|---|---|---|---|
| S1 | `decide` | indeciso vira aviso | morta | — |
| S2 | `decide` | restrito começa a gravar | morta | — |
| S2b | `decide` | `isTranscribing` depois da Acessibilidade | morta | — |
| S3 | `MicrophoneAccess.init` | indeciso vira negado | **sobrevive** | morta |
| S4 | `MicrophoneAccess.init` | `@unknown default` vira indeciso | **sobrevive** | morta |
| S5 | `LaunchPermissions.run` | pede de novo o negado e o restrito | trava (L4) | — |
| S6 | `LaunchPermissions.run` | Acessibilidade antes do microfone | morta | morta |
| S18 | `LaunchPermissions.run` | sai cedo com a Acessibilidade concedida | morta | morta |
| S19 | `LaunchPermissions.run` | sem `@MainActor` | não compila | — |
| S8 | `PermissionLog` | não guarda a última linha | morta | — |
| S9 | `PermissionLog` | lembra todas as linhas (Set) | **sobrevive** | morta |
| S10 | `PermissionLog.line` | `accessibility=` vira `ax=` | morta | morta |
| S11 | verify | sem `\|\| true` | **sobrevive** | morta |
| S12 | verify | negado vira `problem` | **sobrevive** | morta (depois do reforço da sonda) |
| S13 | verify | `head -n 1` | **sobrevive** | morta |
| S14 | `main.swift` | gatilho negado sem chamar o aviso | **sobrevive** | — (B1) |
| S15 | `main.swift` | gatilho indeciso sem novo pedido | **sobrevive** | — (B1) |
| S16 | `main.swift` | sem a linha `permissions:` da abertura | **sobrevive** | — (B1) |
| S17 | `main.swift` | aviso retorna antes de aparecer | **sobrevive** | — (B1) |

S12 sobreviveu à primeira versão da sonda do código de saída: sem modelo no HOME temporário toda rodada já sai com 1. A sonda passou a comparar também a contagem "N check(s) failed", e aí S12 morreu.

## Sondas (`Tests/NeverTypeCoreTests/Audit/PermissionsPart1AuditTests.swift`, 7 testes)

Todas em swift-testing, sem tocar o TCC real (usam as costuras por parâmetro e `AVAuthorizationStatus` construído).

1. **`systemStatusMapsOneToOne`**: protege que cada status do sistema vira a sua resposta. É derrubada por um braço trocado no `init` (S3). O executor não pega porque os testes dele constroem `MicrophoneAccess` pelos casos e nunca passam pelo `init`.
2. **`unknownStatusIsDenied`**: protege que um status desconhecido nunca grava nem deixa o gatilho mudo (vira negado, com aviso). É derrubada por um `@unknown default` mudado (S4). O executor não pega porque não tem caso com status desconhecido.
3. **`answerFromBackgroundQueue`**: protege que, com a resposta do microfone chegando por fila de fundo (como chega a do TCC), a Acessibilidade é pedida depois e na main. É derrubada por uma refatoração do `run` que saia da main sem o compilador reclamar (closures `@Sendable` e `run` não isolado) e pela troca de ordem (S6). O executor não pega porque o teste dele retoma o pedido de dentro da main e não confere a thread. Na forma mais simples dessa regressão o compilador pega antes (S19).
4. **`returningReadingIsWritten`**: protege que voltar a uma leitura anterior (concedido, negado, concedido) é mudança e vai para o log. É derrubada por um log que lembra todas as linhas (S9). O executor não pega porque a sequência dele nunca volta a um valor já escrito.
5. **`exitCodeIgnoresPermissions`**: protege que nenhuma leitura de permissão muda o código de saída nem a contagem de problemas do verify (o `update.sh` roda o verify) e que toda rodada chega ao fim. É derrubada por S11 e S12. O executor não pega porque nenhum teste dele roda o script.
6. **`scriptReadsTheCoreLine`**: protege que o script entende a linha que o Core formata, nos quatro estados. É derrubada por um nome renomeado de um lado só (S10, ou um caso novo no enum sem braço no script). O executor não pega porque a prova dele foi manual, com linhas digitadas, e nada na suíte liga os dois lados.
7. **`lastLineWins`**: protege que vale a última linha da sessão. É derrubada por S13. O executor não pega pelo mesmo motivo da sonda 5.

Poda: escrevi e retirei uma oitava sonda ("Acessibilidade concedida, microfone indeciso, só o pedido do microfone"). As regressões que ela pegaria (S18 e variantes) já derrubam o diário de passos do executor, então ela ficaria duplicada. Nenhuma sonda velha do repositório ficou falsa com esta parte: procurei frases e nomes velhos em `Tests/`, `scripts/`, `docs/` e `.vibeflow/`.

## Para o teste manual do Pedro

Num Mac real, com o app desta branch instalado (o `build-app.sh`, o `install.sh` e o `tccutil` são passos dele):

1. **Primeira abertura com os dois indecisos** (`tccutil reset Microphone com.nevertype.app` e `tccutil reset Accessibility com.nevertype.app`, depois abrir o app). Tem que aparecer primeiro o pedido do microfone, sozinho, e o da Acessibilidade só depois de responder. No `nevertype.log`, a linha `permissions: microphone=notDetermined accessibility=missing` vem antes de `ready.`, e depois aparece outra linha com o microfone respondido. Conferir também (L5) que, deixando o pedido do microfone sem resposta por 1 minuto, o da Acessibilidade não aparece, e anotar isso.
2. **Gatilho com o pedido do microfone ainda aberto** (D1, terceiro caminho). Repetir o passo 1 e, sem responder ao microfone, apertar o gatilho. Deve vir o aviso "NeverType needs Accessibility". Clicar "Open System Settings" e ver se o pedido do microfone continua visível ou fica coberto pelos Ajustes. Responder ao microfone depois disso e ver se a Acessibilidade ainda é pedida.
3. **Plano B com o microfone indeciso** (B2). Com o microfone resetado e o pedido ainda sem resposta (ou dispensado sem clicar), abrir Ajustes › Privacidade e Segurança › Microfone pelo item "Open Microphone Settings…" do menu e ver se o NeverType está na lista. Se não estiver, B2 vira defeito.
4. **Gatilho com microfone indeciso e Acessibilidade concedida** (D1). Resetar só o microfone, abrir o app, ignorar o pedido e apertar o gatilho duas vezes. Hoje o esperado é só o ícone cortado e a linha `microphone not answered yet: recording did not start, asking again` no log, sem pedido novo enquanto o primeiro estiver pendente. É isso que o D1 diz ser o defeito.
5. **Microfone negado.** Negar no pedido e apertar o gatilho: tem que aparecer o aviso modal "NeverType needs Microphone access" com "Recording did not start…". "Open System Settings" tem que abrir a página do Microfone. Apertar o gatilho de novo com o aviso aberto não pode empilhar um segundo aviso.
6. **Menu.** Com o microfone faltando, o menu mostra "Microphone: missing" e embaixo "Open Microphone Settings…", que abre a página do Microfone. Concedido, as duas linhas somem.
7. **Linha de log na mudança.** Com o app aberto, ligar o microfone nos Ajustes e abrir o menu: aparece uma linha `permissions:` nova com `microphone=authorized`. Abrir o menu de novo não repete a linha.
8. **Verify.** Com o app vivo, `bash scripts/verify-install.sh` mostra a seção "Permissions (as NeverType last read them)" coerente com o passo anterior e sai com 0.
9. **Segunda abertura** (cenário 7). Com o app vivo, `open /Applications/NeverType.app`: a cópia viva é ativada, o `nevertype.log` não encolhe (`wc -l` antes e depois) e a última linha `permissions:` continua lá.

## Comandos rodados

* `git status --short`, `git diff` dos 10 arquivos, leitura de `Permissions.swift` e `PermissionsTests.swift`: rodada igual à descrita no briefing (mais o meu arquivo de sondas e este relatório).
* `bash scratchpad/verify/run.sh scratchpad/verify`: 18 rodadas, saída 1 em todas as sem modelo e 0 em todas as com modelo, aviso certo em cada estado.
* `swift build --build-tests` e `swift test --skip-build --filter PermissionsPart1AuditTests`: 7 testes verdes, 0,78 s.
* `python3 scratchpad/sab/sab.py ...`, 20 sabotagens: resultados na tabela; todas restauradas com o sha conferido.
* `swift build && swift test` (uma vez, no fim): exit 0, 257 testes em 30 suítes, verde (pulos: as suítes condicionais de transcrição local e de ditado longo gravado).
* `swift build --build-tests --scratch-path scratchpad/build-audit` + `python3 scripts/count-swift-warnings.py`: build exit 0, **4** warnings, os mesmos quatro da linha de base. O scratch foi apagado depois.
* `shasum` das quatro fontes sabotadas no fim: 53bdcf43, e4eeb7ce, 06317946 e 24e00d82, iguais aos backups.
