# never-type-permissoes · parte 2b · executor

Estado: FEITO COM RESSALVA (05/11/2026), nada commitado; falta a conferência de fora e a auditoria, em outras sessões. Briefing: `.claude/threads/never-type-permissoes-executor-2b-briefing.md` no vault, mais o ajuste do PG descrito abaixo. Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-icone-fim-do-ditado`. `<rascunho>` abaixo é `<rascunho da sessão>`.

## Ajuste do PG, antes da auditoria

A primeira entrega levantou como ressalva que nenhum fim de ditado religava a releitura. O PG decidiu que isso vira conserto: permissão tirada durante um ditado e devolvida deixaria o ícone riscado com as duas concedidas, o defeito de 16/10 às 08:28 por outra entrada. O perímetro de arquivos não mudou; a função é nova em `main.swift`.

## O que mudou

* **`main.swift`, função nova `settleIcon()`:** lê `PermissionReading.current` uma vez, chama `renderResting(reading)` e, se `!reading.isComplete`, chama `permissionWatch.start()`. Com tudo concedido, nenhuma leitura a mais, porque `start()` é quem releria.
* **`main.swift`, os quatro pontos:** `.released`, `discardRecording`, `flashIdle` (sem o `if`) e o sucesso da transcrição, depois de `self.overlay.hide()` e antes de `self.deliver(corrected)`, chamam `settleIcon()`.
* **Fora de `renderResting`, de propósito:** a carga do modelo chama `renderResting` durante os pedidos da abertura, e a releitura só começa depois deles.
* **Ficam como estavam:** o `render(.idle)` da abertura, os `render(.blocked)` e o `.blocked` do `.failure`.
* **Comentários:** `settleIcon`, `renderResting`, `flashIdle`, `StatusIcon.redraw` (só comentário no Core; a regra cobriu todos os casos e não mudou) e o do `.failure`, que dizia "back to normal". Esse perdeu o travessão, porque a linha foi reescrita.
* **`docs/reference.md`:** a frase dos dois segundos diz que o ícone volta ao normal, a não ser que permissão faltando, modelo sem carregar ou falta de Metal o mantenham riscado. A das falhas de abertura diz que nem conceder permissão nem terminar um ditado apagam o risco.
* **`MenuLayoutTests.swift`:** seis oráculos, listados abaixo.

| oráculo | prende |
|---|---|
| `idleIsDrawnOnlyAtLaunch` | `render(.idle)` uma vez só nas linhas de código, e essa é a da abertura |
| `releaseWiring` | de `case .released:` até `overlay.transcribing()`, linha a linha |
| `transcriptionEndWiring` | de `guard ...finish(session)` até o `self.render(.blocked)` do `.failure`, linha a linha |
| `discardWiring` | o corpo inteiro de `discardRecording` |
| `flashIdleWiring` | o corpo inteiro de `flashIdle` |
| `settleIconWiring` | o corpo inteiro de `settleIcon` |

**Decisão:** o briefing pedia a linha nova antes de `deliver`. Prendi a janela maior, do `finish` até o `.blocked` da falha, porque ela também pega uma saída antes do redesenho e a troca do `.blocked` da falha pela regra (item 4 do briefing). Custo: mudar o texto das linhas de log desse trecho exige mudar o oráculo.

## Vermelho e verde

Primeira rodada (`renderResting()` nos quatro pontos):
* Vermelho: `swift test --filter MenuLayoutTests`, 48 testes, **falhou com 5 issues**, os cinco novos. `render(.idle)` contado **4** vezes.
* Verde: `swift test --filter "MenuLayoutTests|StatusIconTests|PermissionsPart"`, 77 testes em 5 suítes, passou.

Ajuste (`settleIcon()`):
* Vermelho: `swift test --filter MenuLayoutTests`, 49 testes, **falhou com 5 issues**: os quatro pontos pela linha `renderResting()` e `settleIconWiring` por não achar a função.
* Verde: `swift test --filter "MenuLayoutTests|StatusIconTests|PermissionsPart"`, **78 testes em 5 suítes, passou**.

## Sabotagens

`python3 -I <rascunho>/sab2b.py`, no estado entregue: troca exata com contagem 1, `swift build` verde, `swift test --filter MenuLayoutTests`, volta por cópia com sha conferido. No fim, restaurado com o sha inicial, `main.swift` 02c30933. **25 de 25 mortas, todas com build verde.**

| id | sabotagem | quem pegou |
|---|---|---|
| **SET-NOSTART** | **`settleIcon` sem o `start()`, pedida pelo PG** | `settleIconWiring` |
| **SET-INVERT** | **condição invertida, pedida pelo PG** | `settleIconWiring` |
| SET-ALWAYS | `start()` sem condição, a leitura a mais com tudo concedido | `settleIconWiring` |
| SET-EXIT | saída antes de redesenhar quando completo | `settleIconWiring` |
| SET-NODRAW | sem o redesenho | `settleIconWiring` |
| SET-REREAD | `renderResting()` com leitura própria | `settleIconWiring` |
| SET-CONST | leitura constante, tudo concedido | `settleIconWiring` |
| IN-REST | `start()` dentro de `renderResting` | `permissionWatchWiring` |
| REL-IDLE, DISC-IDLE, FLASH-IDLE, END-IDLE | o ponto volta a `render(.idle)` | o oráculo do ponto e `idleIsDrawnOnlyAtLaunch` |
| REL-REST, DISC-REST, FLASH-REST, END-REST | o ponto volta a `renderResting()`, sem a releitura | o oráculo do ponto |
| REL-GONE, DISC-GONE, FLASH-GONE, END-GONE | o ponto sem redesenho | o oráculo do ponto |
| REL-AFTER | redesenho depois do `guard url != nil` | `releaseWiring` |
| FLASH-GUARD | condição de volta em volta do redesenho | `flashIdleWiring` |
| END-ORDER | ordem invertida com `deliver` | `transcriptionEndWiring` |
| END-EXIT | saída antes do redesenho | `transcriptionEndWiring` |
| FAIL-RULE | `.failure` pela regra em vez de `.blocked` | `transcriptionEndWiring` |

## Prova final, uma vez, no estado entregue

* `swift build`: Build complete.
* `swift test`: **316 testes em 33 suítes, passou**, 15,1 s (310 mais os 6 novos; saída do XCTest: 0 testes, como sempre neste repositório).
* `swift build --build-tests --scratch-path <rascunho>/clean2` e `python3 scripts/count-swift-warnings.py <rascunho>/clean2.log`: **4**, os mesmos pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `grep` por `render(.idle)`, `settleIcon()`, `renderResting(` e `permissionWatch.start()` em `main.swift`: `render(.idle)` só na 258; `settleIcon()` nos quatro pontos (457, 502, 534, 628) e na definição; `start()` na abertura, no gatilho, em `askAgainForMicrophone` e em `settleIcon`.
* `git status --short`: os quatro arquivos do perímetro, este progresso e `models`, que continua fora.

## Ressalvas

1. **Não rodei o app.** Os oráculos são de texto e a regra é provada no Core. O caso que motivou o ajuste, permissão tirada e devolvida, depende do TCC real e não foi visto: está no teste manual abaixo. Script de instalação é proibido nesta parte.
2. **O fato do briefing sobre o custo fica maior:** são duas leituras novas por ditado que chega ao fim da transcrição, não uma (`.released` e sucesso), mais uma no `flashIdle` quando há falha. Com o custo de 14,4 ms da auditoria 1b, ainda a conferir no app, são cerca de 29 ms de main actor por ditado, e os 14 ms da segunda leitura vêm antes da colagem, sobre os ~600 ms de um ditado. Não medi no app. O ajuste não acrescenta leitura com tudo concedido; com uma faltando, `start()` lê mais uma vez.
3. **"Nada muda para quem usa" vale para a tela, não para o log:** com tudo certo, o `render` escreve uma linha `icon → brand` a cada desenho, sem deduplicar, então um ditado com sucesso ganha uma linha a mais.
4. **O log não explica esse risco, por leitura de código.** `settleIcon` não escreve a linha `permissions:`, e a releitura parte da leitura já sem a permissão, então a perda não é entregue como mudança. O log fica com `icon → brand.slash` sem a causa até o próximo gatilho ou a próxima abertura do menu. Quando a permissão volta, o ícone redesenha, mas a linha não aparece se a última escrita já era a completa. O desenho do PG não pede essa linha, então não a acrescentei.
5. **Janela conhecida, por leitura:** se a permissão voltar entre a leitura de `settleIcon` e a de `start()`, no mesmo turno da main actor, o risco fica até a próxima tecla. É a mesma observação da auditoria 1b para a abertura.

## Fora da parte

* Permissão tirada em repouso, sem ditado e sem falha, com a releitura parada: o ícone segue normal até a próxima tecla. É o B4 da auditoria 1b, decisão de produto, e continua igual.
* Falha da transcrição (`.failure`): o `.blocked` fica sem `settleIcon`, como manda o briefing, então não religa a releitura. O risco ali é o da falha e vai até o próximo redesenho, e o `.released` do mesmo ditado já religou se a permissão faltava naquela hora.
* `docs/reference.md` 309 e 324 falam de "two-second slash" em recusas do menu. Seguem certas na duração do sinal da recusa, e não as mudei.

## Para o teste manual do Pedro

1. **Sem Metal ou com o modelo indisponível:** dite com sucesso. O risco fica, com `icon → brand.slash` no log depois de `transcribed in`.
2. **Permissão tirada durante o ditado:** com as duas concedidas, comece um ditado em mãos livres, desligue a Acessibilidade nos Ajustes e termine. O ícone fica riscado. Ligue de novo sem apertar a tecla: o risco some em cerca de um segundo.
3. **Tudo certo:** dite normalmente. O ícone segue normal, e a releitura não sobe: nenhuma linha `permissions:` nova e o app perto de 0% de CPU em repouso.

## Para retomar

Nada em aberto nesta parte. A varredura repete com `cd ~/Projects/apps/never-type-permissoes && python3 -I <rascunho>/sab2b.py`.

## Conserto 1

Estado: FEITO COM RESSALVA (05/11/2026), nada commitado; falta a reauditoria, em outra sessão. Partida `72f5f8d`. Briefing: `.claude/threads/never-type-permissoes-conserto-2b-briefing.md` no vault. Relatório: `.vibeflow/audits/never-type-permissoes-2b-audit.md`.

### O que mudou

* **L1:** `settleIcon` chama `logPermissionsIfChanged(microphone: reading.microphone, accessibility: reading.accessibilityGranted)` logo depois de `let reading = PermissionReading.current`. Nenhuma leitura a mais, porque os dois argumentos vêm da leitura que já existia. O comentário diz o porquê e `settleIconWiring` prende a linha e a ordem.
* **L3:** `transcriptionEndWiring` vai até o `}` que fecha o `switch result`. O comentário do oráculo diz o motivo.
* **L6:** `docs/reference.md`, a frase de "Clicked mid-dictation" diz que o risco fica até o fim da gravação ou da transcrição. As palavras seguintes não mudaram, mas a quebra de linha mudou até o fim do item.
* **L7:** o comentário de `settleIcon` deixou de dizer "the watch only starts after them", e o motivo agora é que a carga do modelo não tem por que iniciar a releitura. `renderResting` e `StatusIcon.redraw` deixaram de dizer "every end of a dictation" e nomeiam as duas exceções, a falha da transcrição e o erro do gravador.
* **L2, L4 e L5:** não consertados, como manda o briefing.
* **Título de teste:** o de `settleIconWiring` passou a dizer "logs and redraws", porque a linha nova é parte do que ele prende.

### Vermelho e verde

* Vermelho: `swift test --filter MenuLayoutTests`, com os oráculos novos e o código de hoje: 49 testes, **falhou com 1 issue**, `settleIconWiring`. `transcriptionEndWiring` passou, como se espera de teste de endurecimento, que se prova pela sabotagem.
* Verde: `swift test --filter "MenuLayoutTests|StatusIconTests|PermissionsPart"`: **79 testes em 6 suítes, passou**.

### Sabotagens

`python3 -I <rascunho>/sab-conserto1.py`: troca exata com contagem 1, `swift build` verde, `swift test --filter MenuLayoutTests`, volta por cópia com sha conferido. Sha de `main.swift`, no começo e no fim: 69990bf8. **3 de 3 mortas.** A primeira rodada parou em L1-GONE, porque o trecho casava duas vezes (`permissionsChanged` tem as mesmas duas linhas); ancorei em `let reading = PermissionReading.current` e repeti as três.

| id | sabotagem | quem pegou |
|---|---|---|
| FAIL-AFTER | `self.settleIcon()` logo depois do `self.render(.blocked)` do `.failure` (sobrevivia na auditoria) | `transcriptionEndWiring` |
| L1-GONE | `settleIcon` sem a linha nova | `settleIconWiring` |
| L1-AFTER | a linha nova depois do `renderResting` | `settleIconWiring` |

### Prova final, uma vez, no estado entregue

* `swift build`: Build complete.
* `swift test`: **317 testes em 34 suítes, passou** (saída do XCTest: 0 testes, como sempre neste repositório).
* `swift build --build-tests --scratch-path <rascunho>/conserto1-limpo` com o log em arquivo, e `python3 scripts/count-swift-warnings.py <rascunho>/conserto1-limpo.log`: **4**, a mesma lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `git status --short`: os quatro arquivos do perímetro e `models`, que continua fora. Este progresso não aparece porque foi escrito depois desse comando.
* `shasum` no estado entregue: `main.swift` 69990bf8, `StatusIcon.swift` c3c55c01, `MenuLayoutTests.swift` db86b113, `docs/reference.md` 3f5a251f.

**Contagem descartada:** a primeira contagem deu 0, em `<rascunho>/clean`. Essa pasta já existia desde 06:05, de outra rodada, então o build foi incremental e não compilou os arquivos com warning. Repeti numa pasta nova e vale o 4.

### Ressalvas

1. **Não rodei o app.** A linha `permissions:` no fim do ditado é prova de texto, e a deduplicação vem do Core. O caso real depende do TCC, e está no teste manual abaixo.
2. **O rascunho é compartilhado com rodadas anteriores.** Esta rodada sobrescreveu `<rascunho>/main.swift.orig`, sobrescreveu `<rascunho>/clean.log` e recompilou em `<rascunho>/clean`. Nada disso está no repositório, mas quem for repetir uma sabotagem antiga não deve usar essa cópia como referência.
3. **Comando composto:** o primeiro comando da sessão encadeou `git status`, `git log` e `wc` com `&&`, contra o bloco Comandos do briefing. Só leitura, sem efeito, e os seguintes foram um por chamada.
4. **Sonda presa à forma:** nenhuma caiu. As sondas de `Tests/NeverTypeCoreTests/Audit/` não mudaram e estão verdes na suíte.

### Fora do perímetro, autorizado depois pelo PG

Os dois estavam fora do perímetro do briefing. Apontei na entrega e o PG autorizou por mensagem, só eles, sem nenhuma linha de código.

* `main.swift`, comentário de `logPermissionsIfChanged`: a lista de quando a linha é escrita passou a citar o fim de um ditado, que o L1 acrescentou.
* `main.swift`, comentário junto do `render(.blocked)` de "Check for Updates": deixou de dizer "the same two-second slash" e diz o mesmo que a frase corrigida em `docs/reference.md`, que o risco fica até o fim da gravação ou da transcrição.

Prova, depois dessa mudança:
* `diff` de `main.swift` contra a cópia do estado anterior, conferida por sha (69990bf8): só as duas trocas de comentário.
* `swift test`, uma vez: **317 testes em 34 suítes, passou** (saída do XCTest: 0 testes).
* `shasum` de `main.swift` no estado entregue: 57034112. Ele substitui o 69990bf8 da prova final acima; os outros três arquivos não mudaram.
* Não repeti as sabotagens nem a contagem de warnings, porque só comentário mudou e o pedido foi a suíte uma vez.

### Achados N1 e N2 da reauditoria

Só texto, a pedido do PG, pelo relatório `.vibeflow/audits/never-type-permissoes-2b-reaudit-1.md`.

* `main.swift`, comentário de `renderResting`, e `StatusIcon.swift`, comentário de `redraw`: "those paths" passou a ser o fim de um ditado, no passado, com as citações das auditorias mantidas.
* Este progresso: tirei a afirmação de que o git ignora `.vibeflow/`, que estava errada. A pasta é versionada (`git check-ignore` no arquivo sai com 1, e o `git status --short` agora mostra este progresso). O arquivo não aparecia na lista daquele `git status` porque foi escrito depois dele.
* `swift test`, uma vez: **317 testes em 34 suítes, passou** (saída do XCTest: 0 testes).
* `shasum` no estado entregue: `main.swift` c2251f4d, `StatusIcon.swift` 182a3e2b. Eles substituem os anteriores; `MenuLayoutTests.swift` e `docs/reference.md` não mudaram nesta troca.

### Para o teste manual do Pedro

Muda o passo 2 da auditoria: com a permissão tirada durante o ditado, o log agora mostra a linha `permissions:` com a perda logo antes de `icon → brand.slash`, e outra linha `permissions:` com a volta. Com tudo concedido, nenhuma linha `permissions:` nova a cada ditado.
