# never-type-permissoes · parte 2 · auditoria

Estado: CONCLUÍDA (05/11/2026). Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-pendencias`, base `6179eee`, rodada não commitada. `<scratchpad>` é `<rascunho da sessão>/audit2`.

## Veredito: PARTIAL

O código do app está certo, e nenhum defeito apareceu: o N3 faz o que o contrato pede, e os textos batem. O que segura o PASS são dois buracos na régua nova, em `MenuLayoutTests.swift`, ambos de conserto pequeno e já medido:

* **A1:** `noCodeHiddenFromTheOracles` não cumpre "nenhum `#if` no `main.swift`". A abertura inteira sob `#if false` volta a passar com 309 testes verdes, escrita depois de um `;` ou de um form feed, e `menuNeedsUpdate` passa dentro de um literal `#/ /#`.
* **A2:** a unicidade do marcador ficou mais frouxa do que era. Uma sabotagem que o `contains` antigo pegava (R-DECOY-OLD morre) agora sobrevive (R-DECOY).

**Para a orquestração:** as 13 mutações da reauditoria 3 estão mesmo mortas, repeti uma a uma. A1 é a classe do Y-PP1 e do F-RAW em forma menor, então cabe ao PG decidir se conta como o mesmo achado voltando (dev-remoto, princípio 8). Minha leitura: é falha de implementação de uma frase escrita, não a mesma causa de novo, porque o conserto é de uma palavra e não muda o desenho. As outras formas que passam (A3) são o limite conhecido da prova por texto, que o Pedro aceitou às 12:28 de 16/10, e não seguram nada.

## Achados

### A1 · buraco em código de risco · `noCodeHiddenFromTheOracles` não recusa todo `#if` nem todo literal
`MenuLayoutTests.swift` 715: `$0.trimmingCharacters(in: .whitespaces).hasPrefix("#if")`. O `/*` e o `"""` ao lado usam `contains`, o `#if` só olha o começo da linha aparada. O contrato: "`main.swift` não tem linha `#if`" (briefing do executor, item 1) e "nenhum `#if` no `main.swift`" (ponteiro, linha 92, a lista da decisão de 12:28). O nome do teste promete "hides no code".

| id | forma | efeito | resultado, suíte inteira |
|---|---|---|---|
| R-SEMIIF | linha anterior `private func keep() {}; #if false`, `#endif` depois do `}` final | `applicationDidFinishLaunching` não compila no app, o mesmo do Y-PP1 | **sobrevive**, 309 testes |
| R-FORMFEED | `\f#if false` antes da abertura (`.whitespaces` não apara form feed) | o mesmo | **sobrevive**, 309 testes |
| R-REGEX2 | `private static let hiddenMenu = #/` em volta de `menuNeedsUpdate`, fechado com `/#` | menu sem reconstrução, o mesmo efeito do Y-MU2 | **sobrevive**, 309 testes |

O R-REGEX2 só compila para função curta o bastante para ser uma expressão válida; a mesma forma não foi tentada na abertura. É a família do F-RAW, que o PG mandou fechar antes desta auditoria.

Conserto medido, sem ficar aplicado: `$0.contains("#if") || $0.contains("#/")` no lugar do `hasPrefix`. R-SEMIIF-FIX, R-FORMFEED-FIX e SK-REGEX morrem nele; SK-CLEAN mostra `MenuLayoutTests` verde no `main.swift` entregue, sem falso positivo (`grep -cE '#if|#/'`: 0).

### A2 · buraco em código de risco · a unicidade do marcador afrouxou
`MenuLayoutTests.swift` 789. Antes, o marcador contado por `contains` tinha de aparecer uma vez em qualquer lugar. Agora conta só linha exatamente igual, e uma linha que contém o marcador com algo depois não conta mais.

R-DECOY: `func menuNeedsUpdate(_ menu: NSMenu) { if … > 0 { return }` na função real, mais uma `private struct Decoy` com uma cópia exata e inofensiva da função. O efeito é o menu vazio.

| régua | resultado |
|---|---|
| a nova, entregue | **sobrevive**, 309 testes |
| a antiga, `contains`, com a mesma sabotagem (R-DECOY-OLD) | morta em `menuNeedsUpdateWiring` |

A forma é deliberada e nenhum acidente a escreve. Pesa porque é prova que existia e saiu nesta parte, e o briefing do executor proíbe afrouxar. Conserto medido, sem ficar aplicado: contar por `contains` e exigir que todo acerto seja a linha inteira. SK-DECOY morre e SK-CLEAN fica verde.

### A3 · baixo · limite conhecido da prova por texto: formas sem `#if`, `/*`, `"""`
Resposta à pergunta 4 do briefing. Todas com build verde, sem warning novo em `main.swift` no build incremental, e os 309 testes passando:

| id | forma | efeito |
|---|---|---|
| R-LOCAL, R-LOCALMENU | `private func off() {` acima do marcador, `}` depois: a função vira local e nunca é chamada | abertura ou menu desligados |
| R-NONOBJC, R-NONOBJCMENU | `@nonobjc` na linha acima do marcador | o AppKit não enxerga o método |
| R-OVERLOAD | `private func renderResting() {}` em outro ponto do arquivo | toda chamada sem argumento cai na vazia (medido num arquivo à parte: "the added overload"); a função presa segue intacta |
| R-OVERLOADLOG | o mesmo com `logPermissionsIfChanged()` | a linha `permissions:` some da abertura, dos pedidos e do menu |

Efeito no app deduzido da linguagem, não rodado. Nenhuma tem regressão plausível: é sabotagem deliberada, fora da função presa. As duas primeiras são barulhentas no primeiro uso; as `R-OVERLOAD*` são as mais silenciosas. Fica como tarefa, se um dia valer: conferir que o nome da função presa aparece em uma declaração só. Pela regra de poda, sem regressão plausível nenhuma delas vira sonda.

### A4 · baixo · a frase de `docs/pitfalls.md` sobre o `.timeLimit` está errada numa parte
Os números batem com as fontes (tabela abaixo), mas "with no time-limit issue reported" não se reproduz. Pacote mínimo em `<scratchpad>/tl`, mesma forma, `.timeLimit(.minutes(1))` na main actor, biblioteca de testes 1501:

| saída do processo | o que apareceu | fim |
|---|---|---|
| pipe (`tl_run.py`) | só `Build complete!`, nenhuma linha do swift-testing, nem "Test run started" | morto em 240 s |
| pseudoterminal (`tl_pty.py`) | **65,7 s:** `recorded an issue … Time limit was exceeded: 60.000 seconds` | continua preso, morto em 240 s |

O título e a regra da entrada continuam certos: o limite não encerra o teste. O que muda é a causa do silêncio: o issue é registrado, e a saída em buffer se perde com o `kill`. Vale a correção de uma frase, porque quem ler a entrada vai achar que o limite nem dispara. Uma amostra em cada modo. Não sei em que modo o executor mediu em 16/10, então não afirmo que ele mediu errado, afirmo que o sintoma de hoje é este.

### A5 · baixo · comentário de `askAgain`
`Permissions.swift` 109, "Returns when the request returns.", ficou falso no caminho do N3: ele volta depois de `onNoAnswer`, e no app isso é depois do OK. É a ressalva declarada escrita ao contrário no comentário. O cabeçalho de `MicrophoneRequest` (71 a 76) e o de `showMicrophoneWaitingAlert` (`main.swift` 992 a 996) também não citam o N3. Sonda de estado, fica aqui.

### A6 · baixo · `noCodeHiddenFromTheOracles` não tem controle positivo na suíte
RR-NOIF, RR-NOBLOCK e RR-NOTRIPLE tiram cada cláusula e sobrevivem, porque o `main.swift` limpo não exercita nenhuma. A morte de Y-PP1 e F-RAW, repetidas aqui, e de B6-BF, medida pelo executor, prova que elas funcionam hoje, só por mutação. O `bodyHoldsItsEdges` tem o molde: se o conserto do A1 extrair o filtro para uma função com fontes de exemplo, fecha junto. Sabotar o próprio teste estava fora por decisão, então fica como nota.

### Buracos em código de risco fechados por sonda desta auditoria
Os testes do executor usam um `askAgain` por objeto, então nada cobria o que uma chamada deixa para a próxima. Sobreviviam às suítes do executor, e morrem só nas sondas:

| id | mutação | quem pega |
|---|---|---|
| A-NORESET | sem `alertedByTheWait = false` | `earlierWaitDoesNotSilenceTheNextRequest` |
| A-RESETEARLY | o reset antes do `guard` | `askingWhilePendingKeepsTheMarkOfTheOpenRequest` |
| A-NOCANCEL | sem `timer.cancel()` | `staleWaitDoesNotSpeakForTheOpenRequest` |
| A-NOCANCELCHECK | sem `!Task.isCancelled` | `staleWaitDoesNotSpeakForTheOpenRequest` |
| A-ALERTEARLY | o aviso antes de `isPending = false` | `alertAfterTheReturnFindsNothingPending` |

Sobreviventes aceitos, sem achado:
* **A-NOPENDCHECK** (sem `self.isPending` no `guard`): equivalente hoje, porque `isPending = false` e `timer.cancel()` são vizinhos sem suspensão. O `isPending` só cairia sem o `cancel` com `ask` terminando no meio de um `askAgain`, e a abertura roda antes de qualquer gatilho.
* **A-FLAGAFTER** (a marca depois de `onNoAnswer`): só um `runModal` aninhado diferencia, e aí o `permissionAlertGate` recusa o segundo aviso. Fecho síncrono não simula isso em teste.

## Os cenários do briefing

**1. Quem respondeu pode ver o aviso de espera? Só o Mac decide.** O cabeçalho do SDK (`AVCaptureDevice.h` 2044 a 2053) promete `granted` e fila arbitrária, e não diz nada sobre `authorizationStatus` já estar atualizado quando o handler roda. O código lê logo depois da volta e descarta o `granted` (`main.swift` 888). Se houver atraso, quem clicou em Allow ou Don't Allow vê um aviso errado, sem dano de estado.
A amostra de 14:45 sugere menos do que parece: a linha `microphone=authorized` veio depois de `warnIfAccessibilityMissing` (o log tem `icon → brand.slash` e "Accessibility not granted" antes dela), então entre a volta e a leitura houve a chamada de Acessibilidade. Ela não mede a leitura imediata. Vai como passo 1 do teste manual. Se falhar, vira defeito, e o caminho é `request` devolver o `granted`, que fecha o caso do Allow; o do Don't Allow pediria uma releitura.

**2. Dois avisos?** Não, em nenhuma ordem que eu ache.
* Espera e volta: `alertedByTheWait` é marcado antes de `onNoAnswer` (123 e 124), e a leitura é síncrona depois de `isPending = false`. Se a volta chega com o aviso da espera aberto, a marca já vale. Provado por `noAnswerWithinTheWaitAlerts`.
* Duas chamadas com a primeira no modal: se a primeira está no aviso do N3, `isPending` já é falso, a segunda pede de novo e o aviso dela é recusado pelo `permissionAlertGate` (`main.swift` 998). Nada empilha.
* Sobra uma assimetria aceitável: gatilho com pedido aberto avisa (`.showMicrophoneWaitingAlert`, ou o `guard` de `askAgain`), e a volta sem resposta avisa de novo se a espera não tinha disparado. São dois eventos distintos com o OK no meio.
* Efeito menor do gate: se outro aviso de permissão estiver aberto, o do N3 é recusado e a marca da espera fica como dada. A pessoa está vendo um aviso, e o próximo gatilho avisa.

**3. `alertedByTheWait` velho decide? Não.** A leitura (132) só se alcança passando pelo reset (119), e entre os dois `isPending` fica verdadeiro, o que barra outra chamada no `guard`. O único outro escritor é a espera, que não passa do `guard` depois do `cancel`. Agora é prova na suíte, com as três primeiras sondas. O código está certo; faltava a prova.

**4. A régua nova:** ver A1, A2 e A3. Respostas pontuais:
* `marker.contains("func ")`: os marcadores de hoje são funções, `case` e um `lazy var` (`grep` de `body(of:` em `MenuLayoutTests.swift`), e separa todos certo. Deixaria sem exigência de `}` um marcador futuro de `init`, `deinit`, `subscript` ou propriedade computada. Hoje não existe nenhum.
* Marcadores de `case` e `lazy var` ficaram mais apertados (linha inteira), salvo a unicidade do A2. A borda final deles é a de antes.
* `logPermissionsIfChanged` tem assinatura em duas linhas: o marcador é a primeira, e a segunda cai no corpo. `permissionLineWriterWiring` compara essa linha inteira, então a borda está coberta.
* RR-NOFUNCGUARD e RR-CONTAINS morrem nos testes da régua.

**5. `noCodeHiddenFromTheOracles` lê o `main.swift` real?** Sim, por `#filePath` (Y-PP1 e F-RAW morrem nele). Falso positivo existe: `"image/*"` ou um `"""` legítimo reprovam o teste. É aceitável, porque a falha é barulhenta, mostra a linha e a mensagem diz o motivo. O custo é pedir outra forma de escrever aquela linha.

**6. Textos.** Nenhum comando mudou.
* `install.sh`: `git diff -U0` mostra só as linhas 124 a 126 e 133 a 135, dentro do heredoc. A ordem bate com `LaunchPermissions.run`, e o plano B com `docs/INSTALL.md` 167 e 168. Largura em caracteres: máximo 80 (120 a 137).
* `verify-install.sh`: `--word-diff=porcelain` sem palavra adicionada nem removida; os braços das quatro leituras (161 a 177) não estão no diff, e `scriptReadsTheCoreLine` segue verde. Largura máxima 78.
* `docs/reference.md`, `INSTALL.md` e `INSTALL.pt-BR.md` dizem o N3 igual, espelhados.
* `docs/pitfalls.md`, número por número:

| número | fonte | confere? |
|---|---|---|
| 2026-10-15 | `audits/never-type-permissoes-1-audit.md` 3 | sim |
| 10 minutes | a mesma, 59 (L4) | sim |
| 4 min 11 s, `kill`, `.timeLimit(.minutes(1))`, 16/10 | `progresso/never-type-permissoes-1.md` 69 | sim |
| 0,71 s | `audits/never-type-permissoes-1-reaudit-1.md` 37 e 70 | sim |
| o trecho de `Journal.holdsAnswer` | `PermissionsTests.swift` 47 a 49 | sim |
| "no time-limit issue reported" | progresso 69 | bate com a fonte; não se reproduz (A4) |

**7. As medições do item 7.**
* V3: morta em `askAgainWiring`.
* B6: as formas caem em `permissionWatchWiring` e `noCodeHiddenFromTheOracles`; não repeti B6-TR e B6-BL, confio no `depois2.jsonl` e repeti a classe por Y-PP1 e F-RAW.
* `answerFromBackgroundQueue`, reproduzida no estado entregue: LP-S5 passa (0,7 s); LP-NONE e LP-TWICE falham (0,7 s e 0,6 s). A medição do executor se confirma.
* **Existe outra forma em que ela trava.** LP-LOOP (`while microphone() == .notDetermined`, pedir até ter resposta) e LP-NEVERBACK (uma espera a mais que nunca volta) ficaram presos até o corte de 60 s do meu script.
* Isso não pesa contra o descarte, mas muda o motivo. `PermissionsTests`, do executor, trava nas mesmas formas (LP-LOOPSUITE, LP-NEVERBACK-EX), então a sonda não acrescenta risco próprio. O argumento certo para descartar é que ela duplica, abaixo.

**A ressalva do executor.** Não achei efeito além do declarado. O `runModal` dentro de `askAgain` é o mesmo mecanismo do aviso da espera. Pelo gatilho o `permissionWatch.start()` já rodou em `handle` (392); pelo menu ele atrasa até o OK, e a abertura normalmente já deixou a releitura de pé. O único resto é a frase do A5.

## Sondas novas (`Audit/PermissionsPart2AuditTests.swift`, 4 testes)

Sem relógio e sem TCC. Passam no código entregue.

| sonda | contrato protegido | regressão que a derruba | por que o teste do executor não pega |
|---|---|---|---|
| `earlierWaitDoesNotSilenceTheNextRequest` | "sem segundo aviso" vale para um pedido, e o objeto vive enquanto o app vive | perder o reset, por exemplo ao mexer na marca (A-NORESET) | todo teste dele cria um `MicrophoneRequest` novo, e A-NORESET-EX sobrevive em `PermissionsTests` |
| `askingWhilePendingKeepsTheMarkOfTheOpenRequest` | gatilho com pedido aberto não mexe na memória desse pedido | subir o reset para o começo da função (A-RESETEARLY) | ele testa o `guard` e a marca em testes separados, nunca juntos |
| `staleWaitDoesNotSpeakForTheOpenRequest` | a espera de um pedido encerrado não fala pelo pedido aberto, nem engole o aviso dele | tirar `timer.cancel()` ou `!Task.isCancelled` (A-NOCANCEL, A-NOCANCELCHECK) | ele encerra a espera depois da volta, sem outro pedido aberto, e aí `isPending` falso já segura |
| `alertAfterTheReturnFindsNothingPending` | o aviso bloqueia até o OK, então o estado de quando abre dura o tempo da pessoa: o pedido voltou, nada segue em andamento | reordenar a leitura para antes de `isPending = false` (A-ALERTEARLY) | ele confere `isPending` só depois de `askAgain` voltar |

## Poda das sondas antigas (nenhuma apagada)

| sonda | duplica? | evidência |
|---|---|---|
| `answerFromBackgroundQueue` | **sim** | LP-NONE-EX e LP-TWICE-EX morrem em `accessibilityWaitsForTheMicrophone`; LP-S5 ela não pega; LP-OFFMAIN (tirar `@MainActor` de `run`) não compila em `main.swift` 296. Nenhuma mutação minha é morta só por ela. |
| `systemStatusMapsOneToOne`, `unknownStatusIsDenied` | não | nenhum teste do executor constrói `MicrophoneAccess(status)` |
| `returningReadingIsWritten` | não | a sequência em `PermissionsTests` 357 a 361 nunca volta a um valor já escrito |
| `exitCodeIgnoresPermissions`, `scriptReadsTheCoreLine`, `neverAnsweredIsNotSentToTheMicrophonePage`, `lastLineWins` | não | nenhum teste do executor roda o script |
| `goingBackIsAChange`, `missingForLongIsStillWatched` (1b) | não | `eachChangeOnce` não volta a leitura anterior nem conta leituras por intervalo |

Nenhuma prende estado (`checa-sondas.py`: 3 arquivos, 0 trecho suspeito).

## Repetição da varredura do executor

`p2/sweep.py` com `p2/bak2`, no estado entregue, sem mudar nada: Y-ML1 a Y-ML10, Y-PP1, Y-MU1 e Y-MU2 mortas (13 de 13, com os testes que o progresso nomeia); Y-AC1 sem build; V3 e F-RAW mortas; N3-NOCHECK, NOGUARD, ANY, EARLY, NOFLAG, W1 e W2 mortas. Bate com o declarado.

## Para o teste manual do Pedro

Num Mac real, com o app desta branch instalado. `tccutil` e `update.sh` são passos dele. Log em `~/Library/Application Support/NeverType/nevertype.log`.

1. **Quem responde não vê aviso (cenário 1).** Faça: `tccutil reset Microphone com.nevertype.app`, abra o app, responda ao pedido da abertura clicando em **Allow**. Reset de novo com o app aberto, e clique em **Ask for Microphone Access…** no menu; responda **Allow**, em menos de 10 s. Repita três vezes com **Allow** e três com **Don't Allow**, fechando e abrindo se precisar. Deve aparecer: nenhum aviso em nenhuma das seis, e nenhuma linha `microphone: waiting alert shown` no log. **Um aviso aqui é defeito do N3.**
2. **O N3 de verdade, se acontecer.** Faça: reset do microfone e aperte a tecla. Deve aparecer: o pedido do sistema. Se o pedido não aparecer e a chamada voltar sem resposta, o aviso "NeverType is waiting for the microphone answer" vem na hora, sem esperar 10 s. Não conheço mecanismo que provoque isso no build atual, então o normal é este passo não mostrar o caminho.
3. **Sem resposta por 10 s.** Faça: reset, aperte a tecla e não responda. Deve aparecer: o aviso em cerca de 10 s, uma vez. Clique em OK e responda depois: nenhum segundo aviso. Anote se o aviso cobre o pedido do sistema.
4. **A ressalva pelo menu.** Se o passo 2 mostrar o aviso, repita pelo item **Ask for Microphone Access…**. Deve aparecer: o mesmo aviso, e o redesenho do ícone e a linha `permissions:` desse caminho só depois do OK. É o combinado.
5. **Mensagem do `install.sh`.** Ao rodar a instalação, leia o bloco "Two permissions are left for you to grant": a ordem e o plano B têm de bater com o que o Mac mostrou.

Os passos antigos que nunca rodaram seguem valendo: a lista do Microfone no nunca respondido (reauditoria 1 da parte 1, passo 9) e o custo com o microfone negado (reauditoria 3 da parte 1b, passo 5).

## Comandos rodados

* `shasum` no início e no fim: `main.swift` 6e49d4ba, `Permissions.swift` 80bf6977, `MenuLayoutTests.swift` ea1afac0, `PermissionsTests.swift` 383e7122, `install.sh` 0aecd332, `verify-install.sh` 77d89c10, sondas d0eca29d e b05faa3d, iguais ao briefing. Sonda nova 24e6a9bf. Backup em `<scratchpad>/bak`, cada volta conferida por sha.
* `swift test --skip-build --filter PermissionsPart2AuditTests` antes das mutações: 4 testes, passou.
* `python3 -I <scratchpad>/sweep.py sweep1.jsonl`: 36 mutações. `sweep2.jsonl`: 9. `sketch.jsonl`: 3 esboços, desfeitos.
* `env SWEEP_FILTER=. python3 -I <scratchpad>/sweep.py full.jsonl <12 ids>`: os 12 sobreviventes passam na suíte inteira, 309 testes.
* `python3 -I <scratchpad>/../p2/sweep.py <scratchpad>/../p2/bak2 exec-repeat.jsonl all <23 ids>`: como acima.
* `python3 -I <scratchpad>/tl_run.py` e `tl_pty.py`: como no A4. `swift <scratchpad>/overload/shadow.swift`: "the added overload".
* `swift build`: Build complete. `swift test`, uma vez no fim: **309 testes em 33 suítes, passou** (305 do executor mais 4 sondas).
* `swift build --build-tests --scratch-path <scratchpad>/clean` e `python3 scripts/count-swift-warnings.py`: **4**, os mesmos quatro (`AudioRecorder.swift` e `PasteTarget.swift`).
* `bash -n` nos dois scripts: sem erro. Largura por Python: 80 e 78.
* `git diff --word-diff=porcelain 6179eee -- scripts/verify-install.sh` e `git diff -U0 6179eee -- scripts/install.sh`: como no cenário 6.
* `git diff -U0 6179eee -- docs Sources Tests scripts`, nas linhas adicionadas, contagem de travessão e aspas curvas por `grep -cE`: 0.
* `checa-sondas.py --pasta Tests/NeverTypeCoreTests/Audit .`: 3 arquivos, 0 trecho suspeito.
* `git status --short` no fim: os 10 arquivos do executor, o progresso, `models`, este relatório e a sonda nova. Nenhum `tccutil`, nenhum script de instalação, nenhum git de escrita.
