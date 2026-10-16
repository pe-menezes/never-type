# never-type-permissoes · parte 1b · auditoria

Auditor em sessão limpa, 16/10/2026. Base `e2fa8bb`, branch `fix/permissoes-icone`, rodada não commitada. Shas conferidos no início e no fim (iguais aos do briefing): `main.swift` a9ba508c, `StatusIcon.swift` d8a0c7a0, `MenuLayoutTests.swift` 7c503291; `StatusIconTests.swift` 65f18a76. Nenhuma sabotagem ficou aplicada.

## Veredito: PARTIAL

O Core está certo e bem provado: a regra do ícone e a releitura fazem o que o contrato pede, e 13 das 15 sabotagens nelas morrem nos testes do executor. Há um buraco em código de risco (A1). O oráculo de texto da ligação no `main.swift` confere se as chamadas aparecem no texto, mas não confere se elas têm efeito. Seis sabotagens nessa ligação passam com a suíte verde, e duas delas trazem de volta exatamente o defeito das 08:28: ícone riscado com as duas permissões concedidas, até o primeiro gatilho.

## Os quatro itens "pronto quando"

1. **Peça do Core decide o ícone, com teste: cumprido.** `StatusIcon.resting(permissions:model:)` (`StatusIcon.swift` 51 a 57). Os testes `grantedAndModelFine`, `modelFailureKeepsTheSlash` e `missingPermissionSlashes` matam C1 (falha do modelo vira normal), C2 (sem a guarda da permissão), C3 (`||` no `isComplete`) e C12 (carregando risca).
2. **Releitura com intervalo por parâmetro, sem relógio: cumprido.** As três provas pedidas estão em `StatusIconTests`: `stopsWhenGranted`, `doesNotStartWhenGranted` e `eachChangeOnce`. C4 a C10 e C14 morrem. Duas regressões da mesma promessa ("cada mudança chega uma vez", "relê enquanto faltar") passavam nos testes do executor: C15, voltar a uma leitura já vista, e C16, desistir depois de 30 releituras. As duas sondas da auditoria fecham esse buraco (seção Sondas).
3. **Oráculo da ligação no `main.swift` e `body(of:in:)` sem chamada comentada: cumprido na letra, com o buraco A1.** O oráculo `permissionWatchWiring` existe. O N2 da parte 1 está fechado: S14c (M7, a chamada do aviso do negado comentada) agora morre, e B1 e B2 também. Mas M1, M2, M5, M8, M10 e M11 sobrevivem (A1).
4. **`swift build && swift test` verde e os mesmos quatro warnings: cumprido.** Medido agora: 281 testes em 32 suítes, verde (os 279 do executor mais as 2 sondas). `scripts/test-count-swift-warnings.py` OK. Build limpo com `--scratch-path` separado: exit 0 e 4 warnings, os mesmos pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).

As quatro entregas do pedido: (1) a releitura está ligada na abertura, no gatilho e no pedido de novo. A mudança escreve a linha `permissions:` e redesenha por `renderResting`. (2) A regra mantém o risco de modelo e de Metal, e o `.idle` do `askAgainForMicrophone` virou `renderResting()` (L6 fechado nesse caminho). (3) A ordem dos pedidos não mudou: `Permissions.swift` não tem diff, e a chamada de `LaunchPermissions.run` no `main.swift` está intacta. (4) `docs/reference.md` e os dois INSTALL ganharam a frase do ícone, em espelho. Travessão e aspas curvas nas linhas adicionadas e nos arquivos novos: 0.

## Achados

### A1 · buraco em código de risco · o oráculo da ligação prende presença de texto, não efeito
`MenuLayoutTests.permissionWatchWiring` (`MenuLayoutTests.swift` 288 a 331) confere se cada chamada aparece em algum lugar do corpo da função. Não confere se ela roda no caminho que importa. As seis sabotagens abaixo, em `Sources/NeverType/main.swift`, que nenhum teste executa, deixam `MenuLayoutTests` verde:

| id | sabotagem | efeito no app |
|---|---|---|
| M8 | `if reading.isComplete { return }` antes de `renderResting(reading)` em `permissionsChanged` (925) | **volta o defeito das 08:28**: as duas concedidas e o ícone segue riscado até o gatilho |
| M2 | `guard recorder.isRecording, …` (sem o `!`) em `permissionsChanged` (925) | a releitura nunca redesenha em repouso: o mesmo defeito |
| M10 | `self.permissionWatch.start()` sai da `Task` das permissões (316) e vai para o ramo `.notLoaded` do modelo | a releitura só começa na abertura quando o modelo falha; o caso relatado não se resolve sem gatilho |
| M11 | `permissionWatch.start()` sai de antes do `DictationAttempt.decide` (405) e vai para `case .startRecording:` | o gatilho só começa a releitura quando nada falta, ou seja, nunca |
| M1 | `== .normal ? .blocked : .idle` em `renderResting` (932) | ícone invertido em todo repouso |
| M5 | troca de `.ready` e `.noMetal` nos ramos do `prepare` (333 e 336) | sem Metal fica gravado como pronto, e conceder permissão apaga o risco de Metal (L6 de volta pelo outro lado) |

Por que o oráculo não pega: `afterPrompts.contains("self.permissionWatch.start()")` aceita qualquer lugar depois de `LaunchPermissions.run(`, inclusive a `Task` do modelo. `handle.contains("permissionWatch.start()")` aceita qualquer `case`. `changed.contains("renderResting(reading)")` não vê uma saída antecipada antes da chamada. `resting.contains("render(")` não vê o mapeamento, e as três gravações de `modelState` são conferidas sem o ramo onde estão. O `expectAlert` do mesmo arquivo já faz melhor para os avisos: compara linha a linha e recusa `return` antes da chamada (S17 da parte 1).

O que fecha o achado é decisão do conserto. Uma saída é tirar a decisão do `main.swift` para o Core: uma função pura que recebe a leitura, o estado de gravação e transcrição e o `modelState` e devolve o que desenhar, com teste de comportamento. Pelo padrão `nucleo-testavel`, é a saída preferida. A outra é apertar o oráculo nos moldes do `expectAlert`: as linhas exatas do `permissionsChanged` e do `renderResting`, nenhuma saída antes do redesenho, o `start()` dentro da `Task` das permissões e antes do `switch DictationAttempt.decide(`, e cada `modelState` no seu ramo.

Reprodução: `<scratchpad>/audit1b/sab.sh M8` (e M2, M10, M11, M1, M5). O script aplica a troca, roda `swift test --filter MenuLayoutTests`, desfaz pela cópia e confere o sha.

### B1 · baixo · o valor de um segundo não tem teste
C11 (`Task.sleep(for: .seconds(60))` em `PermissionWatch.oneSecond`, `StatusIcon.swift` 120) sobrevive. Provar o valor exigiria relógio real, o que é proibido, ou um oráculo de texto, que é sonda de estado e fica neste relatório. Hoje, a frase "about a second" do `docs/reference.md` e dos INSTALL depende só da leitura de código. O texto atual diz `.seconds(1)`, medido agora por leitura.

### B2 · baixo · custo da releitura enquanto o microfone falta
Com o microfone negado para sempre, o laço acorda a cada segundo pela vida do processo. É o que o contrato pede, e o log não repete linha (o `PermissionLog` deduplica). O custo medido agora, num binário de linha de comando com o microfone `notDetermined` (o app instalado não foi tocado): `AVCaptureDevice.authorizationStatus` custa 14,4 ms de mediana por leitura (mínimo 13,7, p95 17,9, máximo 24,6, em 200 leituras). `AXIsProcessTrusted` custa 0,014 ms. Se o app pagar o mesmo, são cerca de 14 ms da main actor por segundo, perto de 1,4%. Isso não é defeito. Vale a conferência no teste manual (passo 5) antes de decidir se precisa de recuo, por exemplo um intervalo maior depois de um minuto.

### B3 · baixo · os `render(.idle)` fora da regra
Já registrado pelo executor em "Fora da parte". O fim do ditado (`.released`, 470), `discardRecording` (542) e `flashIdle` (635) desenham o ícone normal sem a regra. Assim, sem Metal, um ditado bem-sucedido apaga o risco de Metal para sempre. O `flashIdle` também pode desenhar normal com uma permissão faltando: com a Acessibilidade faltando e a releitura viva, uma recusa do "Open at Login" (1285) desenha `.blocked` e depois `.idle` em 2 s, e a releitura só redesenha na próxima mudança de leitura. Fora do contrato desta parte, que limitou o item 2 à releitura e ao `askAgainForMicrophone`. Vira tarefa: trocar por `renderResting()`.

### B4 · baixo · permissão tirada com a releitura parada
A releitura para quando as duas estão concedidas e só volta num gatilho ou num pedido de novo. Se a Acessibilidade for desligada nos Ajustes com o app parado, ou durante um ditado, o ícone fica normal até a próxima tecla. O menu mostra "Accessibility: missing" ao abrir, mas não redesenha o ícone. A decisão do Pedro ("relê enquanto o ícone estiver riscado") fica cumprida. A letra do item 1 do briefing ("enquanto faltar uma permissão") não cobre esse caso. O comportamento já existia antes da parte. Decisão de produto, não conserto.

### B5 · baixo · a promessa do microfone no `docs/reference.md` não está medida
O parágrafo novo (`docs/reference.md`, depois da linha 340) promete que o risco some "about a second after the switch is turned on in System Settings, with no key press and no relaunch" para as duas permissões. Para o microfone, o próprio executor anota que `authorizationStatus` pode não mudar dentro do processo, e o vídeo 2 do Pedro mostrou o "Quit & Reopen". Só o passo 3 do teste manual decide se a frase vale para o microfone. Os INSTALL só falam da Acessibilidade e estão certos.

### B6 · baixo · `body(of:in:)` ainda tem limites
B3, o filtro trocado por "descarta toda linha que contém `//`", sobrevive. Esse filtro apagaria código com comentário no fim e faria oráculos de ausência (`!x.contains`) passarem sem ver a linha. Nenhum teste tem linha de código com comentário no fim. Comentário de bloco (`/* */`) e comentário no fim da linha continuam aceitos, como o executor anotou. O cenário 5 do briefing foi conferido por script (`<scratchpad>/audit1b/bodies.py`): para os 16 marcadores de `main.swift` usados pelos oráculos, o corpo com o filtro tem exatamente as mesmas linhas de código que o corpo sem ele. Só saíram linhas de comentário (por exemplo, 105 para 65 linhas em `applicationDidFinishLaunching` e 136 para 108 em `handle`). Nenhum oráculo antigo ficou vazio nem passou a casar com outro trecho.

## Cenários do briefing

1. **Acessibilidade ligada com o app aberto e o microfone autorizado.** Pelo código, a releitura seguinte entrega a leitura completa: `permissionsChanged` escreve `permissions: microphone=authorized accessibility=granted`, redesenha por `renderResting` (com `modelState` `.ready` ou `.loading` dá `.idle`) e para (`loop = nil` depois de entregar). No Core está provado por `stopsWhenGranted`. A ligação depende do A1. O TCC real fica para o passo 1 do teste manual.
2. **Microfone negado para sempre.** Ver B2. A sonda `missingForLongIsStillWatched` prende que o laço não desiste e lê uma vez por intervalo.
3. **Modelo falho ou sem Metal com as duas permissões.** A regra mantém o risco (C1 morre). A ordem entre as duas `Task` da abertura não importa, porque as duas rodam na main actor e `renderResting` lê `modelState` na hora. Os `render(.idle)` de fora desfazem o risco depois: B3.
4. **Permissão tirada durante um ditado.** A releitura está parada nessa hora, porque um ditado exige as duas concedidas. O fim do ditado desenha normal. A colagem sem Acessibilidade falha e cai no `flashIdle`, que volta ao normal em 2 s. Ninguém relê até o próximo gatilho: B4. Quando a releitura está viva, ela só redesenha na mudança de leitura: B3.
5. **`body(of:in:)` ignorando comentário.** Ver B6. S14c morre (M7).
6. **Isolamento.** `PermissionWatch` é `@MainActor`. A `Task { @MainActor [weak self] in … }` nasce dentro de um método `@MainActor`, e as três closures (`read`, `interval`, `onChange`) são tipadas `@MainActor`. Nenhuma delas é callback de API do sistema entregue em fila de fundo, então o pitfall da closure que herda o `@MainActor` (o callback do TCC) não se aplica: a releitura usa as leituras síncronas (`authorizationStatus`, `AXIsProcessTrusted`), sem `requestAccess`. A `var last` capturada e mutada dentro da `Task` compila sem warning novo no Swift 6 estrito (4 warnings, os de antes), porque só a `Task` a toca depois de criada. `[weak self]`: o laço não segura a `PermissionWatch` enquanto dorme. C13, o laço segurando o dono, sobrevive porque nenhum teste solta a releitura. Não é achado: o app guarda a releitura pela vida do `AppDelegate`, e nenhum contrato fala do tempo de vida.

Observação sem severidade: a abertura e o `askAgainForMicrophone` leem as permissões três vezes seguidas (`renderResting`, `logPermissionsIfChanged`, `start`). Se a permissão mudasse entre a primeira e a terceira, no mesmo turno da main actor, o ícone ficaria riscado sem releitura até o gatilho. A janela é de microssegundos. Fica registrado, sem tarefa.

## Sabotagens

Todas aplicadas por troca exata com contagem 1 e desfeitas por cópia, com o sha conferido depois de cada uma (`<scratchpad>/audit1b/sab.sh`, definições em `sabs.py`, log em `sab.log`). Filtro: `StatusIconTests` (mais `PermissionsPart1bAuditTests` onde indicado) para o Core, e `MenuLayoutTests` para o `main.swift` e o `body(of:in:)`.

| id | onde | sabotagem | resultado |
|---|---|---|---|
| C1 | `resting` | `.notLoaded, .noMetal` dão normal | morre |
| C2 | `resting` | sem `guard permissions.isComplete` | morre |
| C3 | `isComplete` | `&&` vira `\|\|` | morre |
| C4 | `start` | começa com tudo concedido | morre |
| C5 | laço | não zera `loop` ao parar | morre |
| C6 | laço | não sai depois de completo | morre |
| C7 | laço | entrega toda leitura | morre |
| C8 | laço | não atualiza `last` | morre |
| C9 | `start` | sem `guard loop == nil` (dois laços) | morre |
| C10 | laço | para antes de entregar a leitura completa | morre |
| C11 | `oneSecond` | 60 s | **sobrevive** (B1) |
| C12 | `resting` | carregando risca | morre |
| C13 | laço | laço segura o dono | **sobrevive** (sem contrato, cenário 6) |
| C14 | `start` | base fixa em vez da leitura do sistema | morre |
| C15 | laço | não reentrega leitura já vista | sobrevive aos testes do executor; **morre na sonda** `goingBackIsAChange` |
| C16 | laço | desiste depois de 30 releituras | sobrevive aos testes do executor; **morre na sonda** `missingForLongIsStillWatched` |
| M1 | `renderResting` | mapeamento invertido | **sobrevive** (A1) |
| M2 | `permissionsChanged` | guarda invertida | **sobrevive** (A1) |
| M3 | abertura | sem `permissionWatch.start()` | morre |
| M4 | gatilho | sem `permissionWatch.start()` | morre |
| M5 | `prepare` | `.ready` e `.noMetal` trocados | **sobrevive** (A1) |
| M6 | `askAgainForMicrophone` | `start()` comentado | morre |
| M7 | gatilho | S14c: aviso do negado comentado | morre (N2 fechado) |
| M8 | `permissionsChanged` | sai antes de redesenhar quando completo | **sobrevive** (A1) |
| M9 | abertura | volta o `if !self.micAuthorized { self.render(.blocked) }` | morre |
| M10 | abertura | `start()` só no ramo do modelo que falhou | **sobrevive** (A1) |
| M11 | gatilho | `start()` só em `.startRecording` | **sobrevive** (A1) |
| B1 | `body(of:in:)` | sem o filtro | morre |
| B2 | `body(of:in:)` | filtra só `///` | morre |
| B3 | `body(of:in:)` | filtra toda linha com `//` | **sobrevive** (B6) |

## Sondas

`Tests/NeverTypeCoreTests/Audit/PermissionsPart1bAuditTests.swift`, swift-testing, sem relógio e sem TCC (leitura e intervalo pelas costuras `read` e `interval`). Verdes no entregue. As sondas de `PermissionsPart1AuditTests.swift` não mudaram.

* **`goingBackIsAChange`**: a leitura que volta a uma já entregue (Acessibilidade ligada e desligada de novo, com o microfone negado) chega de novo.
  * Contrato: item 2, "cada mudança de leitura chega uma vez", e a linha `permissions:` acompanha o sistema, como na sonda `returningReadingIsWritten` da parte 1 para o `PermissionLog`.
  * Regressão que a derruba: deduplicar contra tudo que já foi visto, e não contra a última leitura (C15).
  * Por que o teste do executor não pega: `eachChangeOnce` só percorre leituras sempre novas.
* **`missingForLongIsStillWatched`**: com o microfone negado, 60 intervalos seguidos, a releitura segue viva, lê uma vez por intervalo, não entrega nada, e a concessão no fim ainda chega e para o laço.
  * Contrato: item 1, "enquanto faltar uma permissão, relê", e a promessa do `docs/reference.md` de que o risco some sozinho quando a permissão chega, demore o que demorar.
  * Regressão que a derruba: um teto de tentativas ou um recuo que desiste, a resposta mais provável ao custo do B2 (C16). Também derruba quem fizer mais de uma leitura por intervalo.
  * Por que o teste do executor não pega: nenhum teste passa de cinco intervalos.

Sondas de estado que ficam só aqui: o valor `.seconds(1)` (B1), os shas e a contagem de warnings.

## Para o teste manual do Pedro

O que só o TCC de um Mac real prova. Log em `~/Library/Application Support/NeverType/nevertype.log`. O ícone aparece no log como `icon → brand` (normal) e `icon → brand.slash` (riscado). O progresso do executor diz `icon → idle`, mas o nome no log é `brand`.

1. **O caso das 08:28.** Microfone autorizado, Acessibilidade desligada, app aberto e parado. Ligue a Acessibilidade nos Ajustes e não aperte a tecla. Deve aparecer: o risco some em cerca de um segundo, e o log ganha `permissions: microphone=authorized accessibility=granted` seguido de `icon → brand (monochrome)…`.
2. **A releitura parou.** Depois do passo 1, espere um minuto sem mexer. Deve aparecer: nenhuma linha nova `icon →` nem `permissions:` no log, e o NeverType perto de 0% de CPU no Monitor de Atividade.
3. **O microfone sem reabrir (B5).** Com o app aberto, desligue o microfone nos Ajustes. Aperte a tecla: o ícone fica riscado e aparece o aviso. Ligue o microfone de novo e, no "Quit & Reopen", escolha "Later" (Mais tarde). Deve aparecer, se a frase do `docs/reference.md` vale para o microfone: o risco some em cerca de um segundo, com `permissions: microphone=authorized …` no log. Se o risco ficar até reabrir, a frase precisa dizer isso.
4. **A ordem dos pedidos.** Numa primeira abertura (ou depois de revogar as duas pelos Ajustes, sem `tccutil`), o pedido do microfone vem primeiro e o da Acessibilidade depois de responder.
5. **Custo com o microfone negado (B2).** Microfone negado, app aberto e parado por um minuto. Deve aparecer: a CPU do NeverType no Monitor de Atividade perto de 0%. Se ficar visivelmente acima do normal em repouso, o B2 vira conserto.
6. **Opcional, o risco do modelo fica.** Com o modelo indisponível na instalação, o passo 1 deixa o ícone riscado, e o log tem `model:` com a falha.
7. **Permissão tirada com o app parado (B4).** Com as duas concedidas e o ícone normal, desligue a Acessibilidade nos Ajustes. O esperado hoje: o ícone segue normal até a próxima tecla, que risca e mostra o aviso. Confirma se é aceitável.

## Comandos rodados

* `shasum` dos quatro arquivos da parte, no início e no fim: os mesmos do briefing
* `swift build --build-tests` e `swift test --skip-build --filter "StatusIconTests|MenuLayoutTests|PermissionsPart1AuditTests"`: 43 testes em 3 suítes, verde
* `python3 -I bodies.py`: corpos dos 16 marcadores, com e sem filtro, mesmas linhas de código
* `sab.sh` para C1 a C16, M1 a M11, B1 a B3: resultado na tabela; cada uma desfeita, com o sha conferido
* `swift test --filter PermissionsPart1bAuditTests`: 2 testes, verde
* binário `swiftc -O` no scratchpad medindo `AXIsProcessTrusted` e `AVCaptureDevice.authorizationStatus`: números do B2
* `swift build && swift test`: exit 0, 281 testes em 32 suítes, verde
* `python3 scripts/test-count-swift-warnings.py`: OK
* `swift build --build-tests --scratch-path <scratchpad>/audit1b/build-clean` e `python3 scripts/count-swift-warnings.py`: exit 0, 4, a mesma lista (scratch apagado depois)
* `grep -cE "—|–|“|”|‘|’"` nos arquivos novos e nas linhas adicionadas: 0
