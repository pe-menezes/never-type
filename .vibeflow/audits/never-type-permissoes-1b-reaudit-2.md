# never-type-permissoes · parte 1b · reauditoria 2

Reauditor em sessão limpa, 16/10/2026, a partir das 09:46, depois do conserto 2. Branch `fix/permissoes-icone`, base do conserto `bbfec96`, conserto não commitado. Shas conferidos no início e no fim, iguais aos do briefing: `main.swift` ca37b8f9, `StatusIcon.swift` ac60fa3e, `MenuLayoutTests.swift` 99020d81, `StatusIconTests.swift` a33cab34. Sondas da auditoria intactas: `PermissionsPart1bAuditTests.swift` b05faa3d, `PermissionsPart1AuditTests.swift` d0eca29d. Backup meu, novo, em `<scratchpad>/reaudit2-1b/bak/` (os quatro acima, mais `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da e `MenuLayout.swift` 1c7a6dec), conferido por `shasum`. Toda mutação foi desfeita por cópia dessa pasta, com o sha conferido depois de cada uma. Nenhuma ficou aplicada. Li só o diff do conserto (pacote `never-type-permissoes-1b-pacote-conserto-2.md`, 868 linhas). O conserto ficou no escopo dos achados. Enquanto as varreduras rodavam, o `main.swift` do worktree estava mutado, então li o código só na cópia `bak/`.

## Veredito: PARTIAL

**Para a orquestração, com todas as letras: a classe do A2 ainda deixa sobreviventes, e a causa é a mesma do A1 e do A2.** Os oráculos novos prendem uma janela de linhas achada por âncora (`firstIndex(of:)` mais `prefix(n)`). Isso prova que o texto está dentro da função. Não prova que ele roda em toda abertura. Um `if` ou uma saída logo fora da janela desliga o bloco inteiro, e a suíte inteira passa: 296 testes verdes. É o A2 de novo, numa forma menor. Lá o `if loaded {` ficava fora das linhas presas por `contains`. Aqui o `if` fica fora da janela presa linha a linha. Pelo briefing, a frente para aqui.

O que fechou: M14 e M15 morrem, nas duas formas (no `main.swift` e no Core), e a decisão do fim do modelo foi para o Core (`ModelState.afterLoad`), com teste de comportamento. A varredura do executor, rodada de novo, bate com a dele mutação por mutação: 109 mortas, 0 sobreviventes, 1 sem build. O B7 fecha.

## Achados

### A2 e a classe · buraco em código de risco · **M14 e M15 fechados, a classe segue aberta**

**O que fechou.** `ModelState.afterLoad(loaded:devices:metalActive:log:)` (`StatusIcon.swift` 52 a 72) recebe as leituras como chamadas, só consulta o Metal com o modelo carregado e escreve as duas linhas de log de antes. `StatusIconTests` (`afterLoadNotLoaded`, `afterLoadReady`, `afterLoadNoMetal`) conta as leituras e confere o estado e o log. O `main.swift` (321 a 336) só grava o resultado e redesenha. `MenuLayoutTests.modelLoadWiring` prende a `Task` do modelo linha a linha. M14 e M15 morrem no `main.swift` (`modelLoadWiring`), e M14c e M15c morrem no Core (`afterLoad*`). As minhas X-MC1 a X-MC3 também morrem: falha virando `.loading`, `loaded: metal` no estado final e Metal constante.

**O que sobrevive.** Seis mutações minhas em três ligações da classe, todas com build verde e a suíte inteira verde (`SWEEP_FILTER=.`, 296 testes em 32 suítes):

| id | ligação | mutação | efeito no app | resultado |
|---|---|---|---|---|
| X-AB1 | abertura | `if statusItem != nil { return }` antes de `logPermissionsIfChanged()` (`main.swift` 304) | nenhum pedido de permissão, nenhuma releitura, nenhum modelo carregado | **sobrevive** |
| X-AB2 | abertura | `if statusItem == nil {` antes da linha 304 e `}` depois da `Task` das permissões | o bloco das permissões nunca roda: sem pedido do microfone, sem releitura. O caso das 08:28 volta: Acessibilidade ligada nos Ajustes, o ícone riscado até a primeira tecla | **sobrevive** |
| X-AB3 | abertura | `if statusItem != nil { return }` entre a `Task` das permissões e a do modelo | o modelo nunca carrega e o ícone fica normal (`.loading`). Toda transcrição falha | **sobrevive** |
| X-MD1 | modelo | `if statusItem == nil {` antes da `Task {` do modelo (321) e `}` depois dela | o mesmo do X-AB3, sem saída: `modelState` fica `.loading` para sempre | **sobrevive** |
| X-MD2 | modelo | `if statusItem != nil { return }` antes da `Task {` do modelo | o mesmo | **sobrevive** |
| X-MN1 | menu | `if statusItem != nil { return }` antes de `for row in MenuLayout.rows(for: conditions) {` (1048) | o menu abre vazio, sem as linhas de permissão e sem Quit | **sobrevive** |

* `statusItem` já existe nesse ponto da abertura (linha 267), então o `if` é sempre verdadeiro (ou sempre falso). A forma da sabotagem é a mesma "saída antes" que o executor usou em L9, MD3, T6 e AG6. A diferença é o lugar: as dele ficam dentro da janela presa, as minhas logo fora dela.
* Por que passa: `launchPermissionsWiring` (`MenuLayoutTests.swift`) confere `lines[(run - 2)...].prefix(11)`, e nada antes do `logPermissionsIfChanged()` nem depois do `}` da `Task`. `modelLoadWiring` confere `lines[(prepare - 1)...].prefix(12)` e o mesmo vale para ele. `permissionLineWiring` só confere a ordem por `range(of:)`. `menuPermissionConditionsWiring` confere `prefix(6)` e as linhas que contêm `conditions`. A linha nova não contém essa palavra.
* As ligações em que o oráculo começa na primeira linha do corpo e vai até o fim (ou até `try recorder.start()`) não têm esse buraco: gatilho, `askAgainForMicrophone`, `permissionsChanged`, `renderResting`, `logPermissionsIfChanged`, `warnIfAccessibilityMissing`, os três avisos e a propriedade da releitura. Nelas, nenhuma mutação, nem minha nem do executor, sobreviveu.
* O que fecharia (decisão do conserto, não minha): prender o corpo inteiro de `applicationDidFinishLaunching` do ponto em que o `statusItem` existe até o fim, ou provar que nenhuma linha entre o começo do corpo e cada janela abre bloco ou sai. No menu, prender o corpo de `rebuildMenu` inteiro, ou pelo menos até o `for row`.
* Reprodução: `cd ~/Projects/apps/never-type-permissoes && SWEEP_FILTER=. python3 -I <scratchpad>/reaudit2-1b/mine/sweep.py depois <scratchpad>/reaudit2-1b/bak <saida>.jsonl X-AB2` (e os outros ids). As mutações estão em `<scratchpad>/reaudit2-1b/mine/muts.py`. O `sweep.py` é o do executor, copiado sem mudança.

### B7 · baixo · **fechado**
O comentário de `StatusIcon.redraw` (`StatusIcon.swift` 112 a 116) agora diz o que é verdade. Na gravação, o `.released` desenha o normal fora da regra (B3). Na transcrição com sucesso, nada redesenha, e a leitura que chega nesse meio espera o próximo redesenho. Conferi contra o `main.swift`: o `.released` chama `render(.idle)`, e `deliver` no `.inserted` não redesenha. É frase de comentário, sonda de estado, e fica neste relatório.

### B8 · baixo · novo · o mesmo texto falso do B7 continua no `main.swift`
O comentário de `renderResting` (`main.swift` 924 a 928) ainda diz "nothing drawn while dictating, where the icon says recording and the end of the dictation redraws it". A frase é a mesma que o B7 corrigiu no Core. Durante a transcrição o ícone não diz "recording", e o fim da transcrição com sucesso não redesenha. O conserto 2 só tinha a linha do Core no escopo. Vira tarefa junto com o B3.

### B9 · baixo · novo · `micAuthorized` ficou sem uso
`main.swift` 232 a 234: a propriedade `micAuthorized` não tem mais chamador desde o conserto 1, e o Swift não avisa propriedade privada sem uso. Não muda nada no app. O custo é que a volta do redesenho pelo microfone sozinho (M9) cabe numa linha que compila. Hoje o M9 morre em `launchPermissionsWiring`. Vira tarefa: apagar a propriedade.

### B10 · baixo · fora da classe · a página da Acessibilidade não tem prova
Duas mutações minhas em código de antes da frente sobrevivem à suíte inteira:
* X-AV1: `openAccessibilitySettings` (`main.swift` 1260) abre `Privacy_Microphone` no lugar de `Privacy_Accessibility`.
* X-AV2: o item do menu `Open Accessibility Settings…` (1062) chama `openMicrophoneSettings`.

O aviso da Acessibilidade está preso inteiro e chama `openAccessibilitySettings()`, mas a página que essa função abre não é conferida. Para o microfone, a URL é conferida (`opener`). As duas linhas vêm de antes da frente (estão em `main`), então ficam fora da classe pelo briefing do conserto. Vira tarefa: prender a URL da Acessibilidade e o seletor do item, como já se faz com o microfone.

### B1 · baixo · segue aberto
X-PW8 (`oneSecond` com 60 s, no Core) sobrevive. É o mesmo C11 da auditoria e o mesmo P3 do executor, que nem compila na forma dele. Segue como tarefa, sem reabrir.

### B3, B4, B6
Seguem como tarefa, por decisão escrita no briefing. Não reabri.

## A ressalva do executor: o oráculo que prende o texto exato do log e dos avisos

**Classificação: é prova de estrutura, do tipo que o repositório aceita para o alvo executável (`conventions.md`, "Janela no alvo executável tem oráculo de texto"). Não é sonda de estado. A frase entra presa como efeito colateral, não como alvo.** O teste não existe para conferir que a frase é tal. Ele existe para conferir que a ligação é aquela, linha por linha, e as linhas de log estão no meio dela. Sonda de estado (princípio 7) é a que prende a frase como fato a conferir, e isso não está acontecendo aqui. Dois casos à parte:
* Os títulos, textos e botões dos avisos já estavam presos com o texto exato desde a parte 1 (`expectAlert`). Isso é texto de produto que a pessoa lê, e prender é comportamento visível. O conserto 2 não acrescentou custo novo a eles.
* As linhas de log em `afterLoad*` (Core) são saída da função, e conferir é prova de comportamento. Elas também são o contrato do teste manual: `ggml devices:` e o `WARNING` sem Metal.

**O que o conserto 2 acrescentou de frase presa:** oito linhas de log no `MenuLayoutTests`. São os cinco casos do gatilho, o `Accessibility not granted: dictation is blocked…` de `warnIfAccessibilityMissing`, o `microphone: waiting alert shown` e o `model: \(status)`.

**Quanto custa mudar uma frase depois:** uma linha no array esperado, no mesmo commit. O teste fica vermelho com o corpo inteiro na mensagem, então a falha é barulhenta e nunca silenciosa. O risco real é outro: quem muda a frase pode atualizar o array colando o corpo novo sem ler, e o oráculo vira retrato. É o risco de todo oráculo inteiro. A alternativa (casar `log(` por prefixo) deixaria de pegar uma linha de log trocada de caso. Não é achado, e não pede conserto.

## Varreduras

**A do executor, rodada de novo no estado entregue:** `python3 -I <scratchpad>/conserto2-1b/sweep.py depois <scratchpad>/reaudit2-1b/bak <scratchpad>/reaudit2-1b/exec-depois.jsonl`. Resultado: **109 mortas, 0 sobreviventes, 1 sem build (P3)**. Toda morta tem build verde e o teste que a pegou nomeado. Comparei com o `depois.jsonl` do executor, id por id: 0 diferenças, nem de resultado nem de teste nomeado. A tabela dele no progresso (marco D4) vale como está.

**As minhas, 27, nas ligações e nas formas que a lista dele não cobre** (`<scratchpad>/reaudit2-1b/mine/muts.py`, filtro das seis suítes da parte; os sobreviventes rodaram de novo com a suíte inteira):

| id | ligação | arquivo | mutação | resultado |
|---|---|---|---|---|
| X-AB1 | abertura | main | saída antes do bloco das permissões | **sobrevive** (A2, classe) |
| X-AB2 | abertura | main | bloco das permissões dentro de `if` sempre falso | **sobrevive** (A2, classe) |
| X-AB3 | abertura | main | saída entre o bloco das permissões e o modelo | **sobrevive** (A2, classe) |
| X-MD1 | modelo | main | `Task` do modelo dentro de `if` sempre falso | **sobrevive** (A2, classe) |
| X-MD2 | modelo | main | saída antes da `Task` do modelo | **sobrevive** (A2, classe) |
| X-MD3 | modelo | main | `self.modelState = .ready` e o resultado do Core descartado | morre (modelLoadWiring) |
| X-MC1 | modelo | icon | Core: modelo que falhou devolve `.loading` | morre (afterLoadNotLoaded) |
| X-MC2 | modelo | icon | Core: `ModelState(loaded: metal, …)` no fim | morre (afterLoadNoMetal) |
| X-MC3 | modelo | icon | Core: Metal constante `true`, a leitura descartada | morre (afterLoadNoMetal) |
| X-RC1 | renderResting | icon | `resting`: guarda da permissão negada | morre (grantedAndModelFine, missingPermissionSlashes, redrawAtRest) |
| X-RC2 | renderResting | icon | `.loading` riscado | morre (grantedAndModelFine, redrawAtRest) |
| X-RC3 | renderResting | icon | `.noMetal` normal | morre (modelFailureKeepsTheSlash, redrawAtRest) |
| X-RC4 | renderResting | icon | `.notLoaded` normal | morre (modelFailureKeepsTheSlash, redrawAtRest) |
| X-RC5 | renderResting | icon | `isComplete` com `\|\|` | morre (8 testes, 2 deles sondas da auditoria) |
| X-RC6 | renderResting | icon | `isComplete` aceita microfone não respondido | morre (completeReading, missingPermissionSlashes) |
| X-RC7 | renderResting | icon | `redraw` sem a guarda da gravação | morre (noRedrawWhileDictating) |
| X-PW1 | releitura | icon | `start` com a guarda negada | morre (6 testes) |
| X-PW2 | releitura | icon | para com a leitura incompleta | morre (5 testes) |
| X-PW3 | releitura | icon | avisa só a leitura repetida | morre (4 testes) |
| X-PW4 | releitura | icon | sem `last = now` | morre (goingBackIsAChange, eachChangeOnce) |
| X-PW5 | releitura | icon | sem `onChange(now)` | morre (4 testes) |
| X-PW6 | releitura | icon | sem a guarda de já rodando | morre (eachChangeOnce) |
| X-PW7 | releitura | icon | não sai do laço depois de parar | morre (stopsWhenGranted) |
| X-PW8 | releitura | icon | `oneSecond` com 60 s | **sobrevive** (B1, conhecido) |
| X-MN1 | menu | main | saída antes de `MenuLayout.rows(for: conditions)` | **sobrevive** (A2, classe) |
| X-AV1 | avisos, antes da frente | main | `openAccessibilitySettings` abre a página do microfone | **sobrevive** (B10) |
| X-AV2 | avisos, antes da frente | main | item do menu da Acessibilidade chama `openMicrophoneSettings` | **sobrevive** (B10) |

Placar: **18 mortas e 9 sobreviventes**. Os sobreviventes são seis da classe (X-AB1 a X-AB3, X-MD1, X-MD2 e X-MN1), um conhecido (X-PW8, o B1) e dois de antes da frente (X-AV1 e X-AV2). Com a suíte inteira (`SWEEP_FILTER=.`), os oito de `main.swift` passam em 296 testes de 32 suítes. Toda mutação teve build verde (0 `error:`), e depois de cada uma o arquivo voltou ao sha da minha cópia.

## Mudança de comportamento no conserto 2

Nenhuma, como o executor declarou. As linhas `ggml devices:` e `WARNING: without Metal…` saem na mesma ordem e nas mesmas condições: a lista de devices é lida antes de escrever a linha, como antes. `didLoad` é lido uma vez, e o Metal só com o modelo carregado. O estado gravado e o redesenho seguem iguais aos do conserto 1. O `afterLoad` é `@MainActor` e roda dentro da `Task` criada no `applicationDidFinishLaunching`, que já era da main.

## Sondas

Não escrevi sonda nova, e `Tests/NeverTypeCoreTests/Audit/PermissionsPart1bAuditTests.swift` está inalterado (b05faa3d) e verde.
* M14 e M15 fecharam com prova na suíte do executor: comportamento em `StatusIconTests.afterLoad*` e oráculo em `MenuLayoutTests.modelLoadWiring`.
* O B7 é frase de comentário, sonda de estado, e fica aqui.
* Os sobreviventes da classe são achado aberto. A prova deles é trabalho do conserto, e o alvo executável só se prova por oráculo de texto, que é do executor. A reprodução está no `mine/muts.py`.

Sondas presas à forma: nenhuma das sondas da auditoria olha o `main.swift`. Elas olham o comportamento do Core, e duas delas (`goingBackIsAChange`, `missingForLongIsStillWatched`) ajudaram a matar X-RC5 e as X-PW.

## Para o teste manual do Pedro (mantido da reauditoria 1)

O conserto 2 não muda nenhum passo, e o log da abertura sai igual. O log fica em `~/Library/Application Support/NeverType/nevertype.log`. No log, o ícone aparece como `icon → brand` (normal) e `icon → brand.slash` (riscado). O `render` escreve uma linha a cada desenho, sem deduplicar.

1. **O caso das 08:28.** Microfone autorizado, Acessibilidade desligada, app aberto e parado. Ligue a Acessibilidade nos Ajustes e não aperte a tecla. Deve aparecer: o risco some em cerca de um segundo, e o log ganha `permissions: microphone=authorized accessibility=granted` seguido de `icon → brand (monochrome)…`.
2. **A releitura parou.** Depois do passo 1, espere um minuto sem mexer. Deve aparecer: nenhuma linha nova `icon →` nem `permissions:` no log, e o NeverType perto de 0% de CPU no Monitor de Atividade.
3. **O microfone, como a referência diz agora.** Com o app aberto e o microfone desligado, ligue o microfone nos Ajustes. Deve aparecer o **Quit & Reopen** do macOS. Escolha **Quit & Reopen**: o app reabre com o ícone normal, e o log da abertura tem `permissions: microphone=authorized …`. Opcional: repita escolhendo **Later**. Se o risco sumir sozinho em cerca de um segundo, a referência poderia dizer mais. Se não sumir, ela já está certa. Nos dois casos não há conserto.
4. **A ordem dos pedidos.** Numa primeira abertura, ou depois de revogar as duas pelos Ajustes (sem `tccutil`), o pedido do microfone vem primeiro e o da Acessibilidade depois de responder.
5. **Custo com o microfone negado (B2).** Microfone negado, app aberto e parado por um minuto. Deve aparecer: a CPU do NeverType perto de 0%. Se ficar visivelmente acima do normal em repouso, o B2 vira conserto.
6. **Abertura com tudo certo.** Abra o app com as duas permissões e o modelo instalado. Deve aparecer, depois da linha `model: Metal · …`, a linha `ggml devices: …` e mais uma `icon → brand`, e o ícone normal o tempo todo.
7. **Opcional, o risco do modelo fica.** Com o modelo indisponível na instalação, o passo 1 deixa o ícone riscado, e o log tem `model:` com a falha e nenhuma linha `ggml devices:`.
8. **Opcional, ditado durante o carregamento.** Com o modelo indisponível, abra o app e segure a tecla logo em seguida, por uns três segundos. Deve aparecer: a onda de gravação até soltar, sem risco por cima dela no meio da gravação, e o risco depois que a transcrição falha (`TRANSCRIPTION FAILED` no log).
9. **Permissão tirada com o app parado (B4).** Com as duas concedidas e o ícone normal, desligue a Acessibilidade nos Ajustes. Hoje o esperado é: o ícone segue normal até a próxima tecla, que risca e mostra o aviso. Confirme se é aceitável.

(Os passos 6 e 7 ganharam só a menção à linha `ggml devices:`, que já saía antes. Nenhum passo mudou.)

## Comandos rodados

* `shasum` dos sete arquivos da parte e das duas sondas, no início e no fim: os do briefing. Backup em `<scratchpad>/reaudit2-1b/bak/`, conferido por `shasum`.
* `swift build && swift test`: exit 0, **296 testes em 32 suítes, verde**.
* `swift test --skip-build --filter "PermissionsPart1bAuditTests|PermissionsPart1AuditTests"`: 10 testes em 2 suítes, verde.
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK. O build limpo com os quatro warnings foi medido pelo PG às 09:45, e não rodei de novo.
* `python3 -I <scratchpad>/conserto2-1b/sweep.py depois <scratchpad>/reaudit2-1b/bak <scratchpad>/reaudit2-1b/exec-depois.jsonl`: 109 mortas, 1 sem build (P3), 0 sobreviventes, igual ao do executor.
* `python3 -I <scratchpad>/reaudit2-1b/mine/sweep.py depois <scratchpad>/reaudit2-1b/bak <scratchpad>/reaudit2-1b/mine/mine.jsonl`: 27 mutações, 18 mortas e 9 sobreviventes.
* `SWEEP_FILTER=. python3 -I <scratchpad>/reaudit2-1b/mine/sweep.py depois … X-AB1 X-AB2 X-AB3 X-MD1 X-MD2 X-MN1 X-AV1 X-AV2`: as oito passam na suíte inteira, 296 testes em 32 suítes.
* `git diff -U0 bbfec96 -- Sources Tests | grep '^+' | grep -cE "—|–|“|”|‘|’"`: 0.
* `git diff --stat bbfec96` em `docs`, `scripts`, `Package.swift`, nos README e em `Tests/NeverTypeCoreTests/Audit`: vazio. `git status --short`: os cinco arquivos do conserto, mais `models` e este relatório.
