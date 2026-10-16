# never-type-permissoes · parte 1b · reauditoria 1

Reauditor em sessão limpa, 16/10/2026, depois do conserto 1. Branch `fix/permissoes-icone`, base do conserto `e6d9431`, conserto não commitado. Shas conferidos no início (09:10) e no fim (09:18), iguais aos do briefing: `main.swift` fad16d7a, `StatusIcon.swift` b4d425d9, `MenuLayoutTests.swift` e38fdb2f, `StatusIconTests.swift` f9c39d90. Backup meu, novo, em `<scratchpad>/reaudit1b/bak/`. Nenhuma sabotagem ficou aplicada. Li só o diff do conserto (pacote `never-type-permissoes-1b-pacote-conserto-1.md`, 565 linhas), mais o código em volta dos pontos de redesenho do `main.swift` para o cenário da mudança de comportamento. O conserto ficou no escopo dos achados, então não houve auditoria inteira de novo.

## Veredito: PARTIAL

O A1 fecha pelo critério escrito: as seis sabotagens morrem, cada uma em duas ou três formas, por teste vermelho e com o build verde. O B5 fecha. Sobra um buraco novo em código de risco, o A2, com a mesma causa do A1: o oráculo do fim do carregamento do modelo confere duas linhas por presença (`contains`), e não confere o `if loaded {` que separa as duas. Inverter essa condição deixa o ícone riscado para sempre em todo Mac que funciona, e a suíte inteira passa: 285 testes verdes.

**Para o PG (princípio 8):** o A2 tem a mesma causa do A1, um oráculo que prende presença de texto e não efeito, num trecho que o conserto reescreveu e deixou fora do molde linha a linha. A decisão de tratá-lo como "o mesmo achado voltando pela mesma causa" é sua.

## Achados

### A1 · buraco em código de risco · **fechado**
A decisão saiu para o Core, com teste de comportamento: `ModelState(loaded:metalActive:)` (`StatusIcon.swift` 42 a 50), `StatusIcon.visual` (82 a 87) e `StatusIcon.redraw(permissions:recording:transcribing:model:)` (89 a 99). A ligação que ficou no `main.swift` se prova linha a linha em `MenuLayoutTests.permissionWatchWiring`: os corpos inteiros de `permissionsChanged` e `renderResting`, o `start()` dentro da `Task` das permissões logo depois dos pedidos e uma vez só na abertura, e o gatilho exato até o `switch DictationAttempt.decide(`. Reescrevi as seis mutações na forma nova com definições minhas (`<scratchpad>/reaudit1b/sabs.py`), umas iguais às do executor e outras diferentes:

| id | onde | sabotagem | resultado |
|---|---|---|---|
| M8a | `main.swift`, `permissionsChanged` | `if reading.isComplete { return }` antes de `renderResting(reading)` | morre (`MenuLayoutTests`) |
| M8b | `main.swift`, `renderResting` | `guard !permissions.isComplete else { return }` no topo | morre (`MenuLayoutTests`) |
| M8c | Core, `redraw` | `if permissions.isComplete { return nil }` | morre (`StatusIconTests`, 4 issues) |
| M2a | `main.swift`, `renderResting` | `recording: !recorder.isRecording` | morre (`MenuLayoutTests`) |
| M2b | Core, `redraw` | `guard recording \|\| transcribing` | morre (29 issues) |
| M2c | Core, `redraw` | `guard !recording` (sem a transcrição) | morre (8 issues, `noRedrawWhileDictating`) |
| M10a | abertura | `start()` sai da `Task` das permissões e vai para o ramo `if !metalActive {` do modelo | morre (`MenuLayoutTests`) |
| M10b | abertura | `start()` sai da `Task` das permissões e vai para antes do `modelState =` | morre (`MenuLayoutTests`) |
| M11a | gatilho | `start()` só em `case .startRecording:` | morre (`MenuLayoutTests`) |
| M11b | gatilho | `start()` só em `case .showAccessibilityWarning:` | morre (`MenuLayoutTests`) |
| M1a | Core, `visual` | mapeamento invertido | morre (`restingVisual`, `redrawAtRest`) |
| M1b | `main.swift`, `renderResting` | `render(visual == .blocked ? .idle : .blocked)` | morre (`MenuLayoutTests`) |
| M5a | Core, `ModelState.init` | `.ready` e `.noMetal` trocados | morre (`modelStateFromTheLoad`) |
| M5b | `main.swift`, modelo | `metalActive: !metalActive` | morre (`MenuLayoutTests`, 2 issues) |
| M16 | `main.swift`, modelo | `renderResting()` antes de gravar o `modelState` | morre (`MenuLayoutTests`) |
| **M14** | `main.swift`, modelo | `if loaded {` vira `if !loaded {` | **sobrevive à suíte inteira** (A2) |
| **M15** | `main.swift`, modelo | `metalActive = loaded` antes do `ModelState(...)` | **sobrevive à suíte inteira** (A2) |

Cada sabotagem de `main.swift` passou por `swift build` com exit 0 e 0 `error:`, então toda morte é teste vermelho e não falha de compilação. Cada uma foi desfeita por cópia do meu `bak/`, com o sha conferido (log em `<scratchpad>/reaudit1b/sab.log`).

### A2 · buraco em código de risco · novo, mesma causa do A1 · o fim do carregamento do modelo ainda é conferido por presença
`main.swift` 329 a 342: `let loaded = await self.transcription.didLoad()`, `var metalActive = false`, `if loaded {` … `metalActive = await self.transcription.isMetalActive()` … `}`, e depois `self.modelState = ModelState(loaded: loaded, metalActive: metalActive)` e `self.renderResting()`. O oráculo (`MenuLayoutTests.swift` 340 a 349) prende a linha do `modelState`, o `renderResting()` logo depois dela e, por `launchLines.contains(...)`, as linhas do `didLoad()` e do `isMetalActive()`. O `if loaded {` e o que acontece com `metalActive` entre a leitura e o `ModelState` ficam sem prova.

* **M14** (`if !loaded {`): com o modelo carregado, `metalActive` fica `false`, o estado vira `.noMetal` e o ícone fica riscado em todo Mac que funciona, com as duas permissões concedidas. É o sintoma das 08:28, agora permanente, e a linha `ggml devices:` some do log. Suíte inteira: 285 testes, verde.
* **M15** (`metalActive = loaded`): o `.noMetal` nunca é gravado, e o risco de Metal some. Suíte inteira: 285 testes, verde.
* Por que é a causa do A1: é a mesma família do M5 (o estado do modelo no ramo errado), que o relatório da auditoria pedia para prender "cada `modelState` no seu ramo". O conserto levou os ramos para o Core, mas deixou no `main.swift` a condição que alimenta o Core, conferida por `contains`, fora do molde do `expectAlert` que ele mesmo usou no resto.
* O que fecha (decisão do conserto): prender linha a linha o trecho do `let loaded` até o `self.renderResting()`, ou levar ao Core também a derivação (ler Metal só com o modelo carregado). Fecha quando M14 e M15 deixam a suíte vermelha.
* Reprodução: `bash <scratchpad>/reaudit1b/sab.sh M14` (e `M15`; `M14full` e `M15full` rodam a suíte inteira).

### B5 · baixo · **fechado**
`docs/reference.md` 342 a 348: o "about a second … with no key press and no relaunch" vale só para a Acessibilidade. Para o microfone, a referência diz que o macOS oferece **Quit & Reopen** e que o app reaberto lê a permissão na abertura. `grep` por "about a second" em `docs/`, nos README e em `Sources/`: sobram os dois INSTALL, que falam só da Acessibilidade (fora do perímetro, intocados), e um comentário de `logPermissionsIfChanged` (`main.swift` 947), que não é promessa ao usuário. É sonda de estado (frase de doc) e fica neste relatório.

### B7 · baixo · novo · a guarda da transcrição descarta um redesenho que ninguém repete
O conserto pôs a guarda do ditado em `StatusIcon.redraw`, e com isso ela vale para os quatro chamadores de `renderResting`, não só para a releitura (ver "Mudança de comportamento"). Durante a transcrição, o ícone da barra já é o normal: o `.released` desenha `render(.idle)` (`main.swift` 474), e quem mostra "transcrevendo" é a pílula. No caminho de sucesso, o fim da transcrição não redesenha (`deliver`, `.inserted`). O comentário de `StatusIcon.redraw` ("it says recording or transcribing then, and the end of the dictation redraws it", `StatusIcon.swift` 90 e 91) só vale para a gravação. Consequência: se o fim do carregamento do modelo cair durante uma transcrição com o resultado `.noMetal`, o risco de Metal não é desenhado e não volta. Antes do conserto, o `render(.blocked)` direto desenhava o risco e ele ficava. A janela é estreita: o `TranscriptionService` é um ator com `prepare`, `transcribe`, `didLoad` e `isMetalActive` síncronos (`main.swift` 39 a 89). Se a transcrição entra na fila do ator antes de uma das leituras do modelo, ela termina e o `finish` roda na main antes do `modelState`, e o redesenho acontece. O caso ruim exige o gatilho solto entre a última leitura do ator e a continuação na main, coisa de milissegundos, e só num Mac sem Metal. Vira tarefa junto com o B3: redesenhar pela regra no fim do ditado e da transcrição.

### B1, B2, B3, B4, B6
Ficam abertos como tarefa, por decisão escrita no briefing do conserto. Não reabri.

## Mudança de comportamento declarada pelo executor

**Está no escopo do A1, por consequência, e foi declarada.** O briefing do conserto pediu ao Core a decisão "o que desenhar depois de uma leitura da releitura (a leitura, gravando ou não, transcrevendo ou não, `modelState`)". O fim do carregamento do modelo é exatamente o lugar do M5, e os dois `render(.blocked)` diretos de lá saíram para a regra. Passar a regra a ser o único caminho do repouso (`renderResting` chama `StatusIcon.redraw`) é a forma natural de fechar o M5 e o M1 juntos. Não há mudança nova de produto.

Os quatro chamadores de `renderResting` e o efeito da guarda em cada um:
1. **Fim dos pedidos da abertura** (`main.swift` 311). Não há ditado possível antes de as duas permissões existirem, e os pedidos só existem quando falta uma. Sem efeito prático.
2. **`askAgainForMicrophone`** (918). Só roda com o microfone sem resposta, quando o gatilho não grava. Sem efeito prático.
3. **`permissionsChanged`** (928). A guarda já estava lá antes do conserto. Durante um ditado as duas estão concedidas, então a releitura entrega no máximo a leitura completa, e o ícone já está certo.
4. **Fim do carregamento do modelo** (342). Aqui a mudança é real:
   * Modelo termina **durante a gravação** (o caso plausível: tecla apertada nos primeiros segundos da abertura). Antes, `.notLoaded` ou `.noMetal` pintavam o risco por cima da onda de gravação. Agora a onda fica. No fim, o `.released` desenha o normal direto (B3), igual a antes. Com `.notLoaded`, a transcrição falha e o `TRANSCRIPTION FAILED` desenha o risco. Com `.noMetal`, o risco se perde, como já se perdia antes (B3). Melhorou durante a gravação e não piorou depois.
   * Modelo termina **durante a transcrição**: janela de milissegundos em que o risco de Metal se perde e antes ficava (B7).
   * Modelo pronto, em repouso: agora desenha o normal mais uma vez, o que antes não acontecia. O log ganha uma linha `icon → brand` depois de `model:`.

**Algum caminho fica sem redesenho depois do ditado?** Sim, dois, e nenhum é de permissão: o risco de Metal (ou de modelo) que chega durante a gravação e é apagado pelo `.released` (B3, já existia) e o que chega durante a transcrição com sucesso (B7, janela estreita). Nenhum caminho deixa o ícone riscado com as duas permissões e o modelo bons.

## Sondas

Não escrevi sonda nova. `Tests/NeverTypeCoreTests/Audit/PermissionsPart1bAuditTests.swift` está inalterado (b05faa3d) e verde.
* O A1 fechou com prova na suíte do executor: comportamento em `StatusIconTests` (`restingVisual`, `modelStateFromTheLoad`, `redrawAtRest`, `noRedrawWhileDictating`) e oráculo linha a linha em `MenuLayoutTests`.
* O B5 é frase de doc, sonda de estado, e fica aqui.
* O A2 está aberto: a prova é trabalho do conserto, e o alvo executável não é importável por teste, então o que existe dele é oráculo de texto, e oráculo de texto é do executor. A reprodução está no `sab.sh`.
* O B7 vive no `main.swift`, numa corrida entre o ator e a main, e não se exercita por teste. A parte que é do Core (nada desenhado durante o ditado) está provada por `noRedrawWhileDictating`.

Sondas presas à forma: nenhuma das sondas da auditoria olha o `main.swift`. O executor confirmou isso e eu também.

## Para o teste manual do Pedro (revisto para depois do conserto)

O que só o TCC de um Mac real prova. O log fica em `~/Library/Application Support/NeverType/nevertype.log`. No log, o ícone aparece como `icon → brand` (normal) e `icon → brand.slash` (riscado). O `render` escreve uma linha a cada desenho, sem deduplicar.

1. **O caso das 08:28.** Microfone autorizado, Acessibilidade desligada, app aberto e parado. Ligue a Acessibilidade nos Ajustes e não aperte a tecla. Deve aparecer: o risco some em cerca de um segundo, e o log ganha `permissions: microphone=authorized accessibility=granted` seguido de `icon → brand (monochrome)…`.
2. **A releitura parou.** Depois do passo 1, espere um minuto sem mexer. Deve aparecer: nenhuma linha nova `icon →` nem `permissions:` no log, e o NeverType perto de 0% de CPU no Monitor de Atividade.
3. **O microfone, como a referência diz agora.** Com o app aberto e o microfone desligado, ligue o microfone nos Ajustes. Deve aparecer o **Quit & Reopen** do macOS. Escolha **Quit & Reopen**: o app reabre com o ícone normal, e o log da abertura tem `permissions: microphone=authorized …`. Opcional: repita escolhendo **Later**. Se o risco sumir sozinho em cerca de um segundo, a referência poderia dizer mais. Se não sumir, ela já está certa. Nos dois casos não há conserto.
4. **A ordem dos pedidos.** Numa primeira abertura, ou depois de revogar as duas pelos Ajustes (sem `tccutil`), o pedido do microfone vem primeiro e o da Acessibilidade depois de responder.
5. **Custo com o microfone negado (B2).** Microfone negado, app aberto e parado por um minuto. Deve aparecer: a CPU do NeverType perto de 0%. Se ficar visivelmente acima do normal em repouso, o B2 vira conserto.
6. **Abertura com tudo certo (novo no conserto).** Abra o app com as duas permissões e o modelo instalado. Deve aparecer, depois da linha `model: Metal · …`, mais uma linha `icon → brand`, e o ícone normal o tempo todo.
7. **Opcional, o risco do modelo fica.** Com o modelo indisponível na instalação, o passo 1 deixa o ícone riscado, e o log tem `model:` com a falha.
8. **Opcional, ditado durante o carregamento (novo no conserto).** Com o modelo indisponível, abra o app e segure a tecla logo em seguida, por uns três segundos. Deve aparecer: a onda de gravação até soltar, sem risco por cima dela no meio da gravação, e o risco depois que a transcrição falha (`TRANSCRIPTION FAILED` no log).
9. **Permissão tirada com o app parado (B4).** Com as duas concedidas e o ícone normal, desligue a Acessibilidade nos Ajustes. Hoje o esperado é: o ícone segue normal até a próxima tecla, que risca e mostra o aviso. Confirme se é aceitável.

## Comandos rodados

* `shasum` dos quatro arquivos da parte, no início (09:10) e no fim (09:18): os mesmos do briefing. Backup em `<scratchpad>/reaudit1b/bak/`, conferido por `shasum`.
* `swift build && swift test`: exit 0, **285 testes em 32 suítes, verde** (09:12 a 09:13).
* `swift test --filter "PermissionsPart1bAuditTests|PermissionsPart1AuditTests"`: 10 testes em 2 suítes, verde.
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK.
* `bash <scratchpad>/reaudit1b/sab.sh <id>` para M8a, M8b, M8c, M2a, M2b, M2c, M10a, M10b, M11a, M11b, M1a, M1b, M5a, M5b, M14, M15 e M16, com filtro `MenuLayoutTests` para o `main.swift` e `StatusIconTests|PermissionsPart1bAuditTests` para o Core: resultado na tabela. `M14full` e `M15full` (filtro `.`, suíte inteira): 285 testes, verde, as duas sobrevivem.
* `swift build --build-tests --scratch-path <scratchpad>/reaudit1b/build-clean` e `python3 scripts/count-swift-warnings.py`: exit 0 e **4**, a mesma lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28). Scratch apagado depois.
* `git diff -U0 e6d9431 | grep '^+' | grep -cE "—|–|“|”|‘|’"`: 0.
* `git diff --stat e6d9431` nos INSTALL, nos README e em `Tests/NeverTypeCoreTests/Audit`: vazio (perímetro respeitado). `git status --short`: os seis arquivos do conserto, mais `models` e este relatório.
