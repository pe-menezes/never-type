# Auditoria · never-type-permissoes · parte 2b

05/11/2026. Base `ab0a2a2`, rodada não commitada. Estado auditado: `main.swift` 61d4a861, `StatusIcon.swift` eb1c100b, `MenuLayoutTests.swift` 966bea0f, `docs/reference.md` f4e20ea8, os mesmos do briefing, conferidos por `shasum` no começo e depois das sabotagens.

## Veredito: PASS

Nenhum defeito e nenhum buraco em código de risco. Os pontos de risco (`settleIcon` e os quatro lugares que a chamam) estão certos e presos. Ficam sete achados baixos, que viram tarefa e não abrem volta. O que só o Mac real prova vai na última seção.

## Achados

Todos baixos. L1 é o único com conserto que eu recomendaria fazer junto.

### L1 · baixo · o risco por permissão fica no log sem a causa
`settleIcon` (`main.swift` 943 a 949) é o único dos quatro lugares que religam a releitura sem escrever a linha antes: abertura (302 e 306), gatilho (389 e 392) e `askAgainForMicrophone` (909 e 910) escrevem `permissions:` e só então chamam `start()`.

Sequência, por leitura e pelo Core: a última linha escrita diz `granted`. A permissão cai durante o ditado. `settleIcon` desenha o risco. `start()` toma a leitura sem a permissão como base, então a perda não é mudança. Quando a permissão volta, `permissionsChanged` chama `lineIfChanged`, que compara com a última escrita, igual, e não escreve (`Permissions.swift` 168 a 174). O log fica com `icon → brand.slash` e depois `icon → brand`, sem nenhuma palavra sobre permissão, a não ser que a pessoa abra o menu ou aperte a tecla no meio. Quem lê esse log procura primeiro no modelo e no Metal. Atrapalha, mas o ícone e o menu estão certos, por isso baixo.

Conserto de uma linha, sem leitura a mais e sem linha nova com tudo concedido, porque `lineIfChanged` deduplica. Logo depois de `let reading = PermissionReading.current`:

```swift
logPermissionsIfChanged(microphone: reading.microphone, accessibility: reading.accessibilityGranted)
```

`settleIconWiring` muda junto.

### L2 · baixo · o custo é maior do que a ressalva diz
A ressalva fala em cerca de 29 ms por ditado e diz que só os 14 ms da segunda leitura vêm antes da colagem. As duas vêm: a do `.released` roda antes de `overlay.transcribing()` e do início da transcrição, e a do sucesso antes de `deliver`. As duas estão em série no caminho até o texto, e a medição de agora dá mais que os 14,4 ms da parte 1b. Ver cenário 4. Não muda a decisão.

### L3 · baixo · `transcriptionEndWiring` promete mais do que prende
O título diz "a failure keeps its slash", e o oráculo termina na linha `self.render(.blocked)`. A sabotagem FAIL-AFTER, `self.settleIcon()` logo depois dessa linha, sobrevive, e com tudo certo apaga o risco da falha na mesma hora. A edição de boa-fé existe: religar a releitura no `.failure`, o caso que o progresso do executor anota em "Fora da parte". Fica baixo porque o `.failure` não é um dos quatro pontos de risco nem é código de permissão: o que se perde é o sinal de falha da transcrição. Conserto: o oráculo vai até o `}` que fecha o `switch`.

### L4 · baixo · ninguém prende as chamadas de `flashIdle` em `deliver`
FAILED-NOFLASH (tira `flashIdle()` de `.failed`) deixa o risco até a próxima tecla, e FAILED-SETTLE (troca por `settleIcon()`) apaga o risco na hora. As duas sobrevivem. A edição de boa-fé é a segunda: "agora tudo passa por `settleIcon`". Os oráculos desta parte prendem o corpo de `flashIdle`, mas não quem a chama. Já era assim antes da parte, e `deliver` não é código de permissão.

### L5 · baixo · `endOrphanRecording` não está preso
ORPHAN-OWN (a função faz o cancelamento por conta própria em vez de chamar `discardRecording`) sobrevive e deixaria a onda de gravação no ícone. Não achei edição de boa-fé que escreva isso; pelo critério da fricção #86, é baixo. Código sem mudança nesta parte.

### L6 · baixo · `docs/reference.md` 323 e 324: "two-second" não vale no meio do ditado
"Clicked mid-dictation, it refuses with the same two-second slash". O `render(.blocked)` (`main.swift` 1331) pinta por cima da onda, e aos 2 s `settleIcon` não desenha nada, porque `StatusIcon.redraw` devolve nil durante o ditado. O risco fica até o fim da gravação ou da transcrição, não dois segundos. O antigo `if` de `flashIdle` fazia o mesmo, então a frase já estava imprecisa, e a parte não piorou. Ver cenário 6.

### L7 · baixo · dois comentários dizem mais que o código
* `main.swift` 940 e 941: "the watch only starts after them". O gatilho (392) já podia iniciar a releitura durante os pedidos da abertura, e `flashIdle` agora também pode (cenário 3).
* `main.swift` 923 e `StatusIcon.swift` 113: "every end of a dictation" redesenha. O `.failure` e o `onError` desenham `.blocked` direto, de propósito.

## Cenários do briefing

`AppDelegate` mora no alvo executável, que teste não importa. Por isso os cenários 1 a 3 são leitura de código sobre a regra provada no Core, e a ligação é a dos oráculos de texto.

### 1. Algum fim de ditado ficou fora da regra?
| caminho | o que acontece |
|---|---|
| `.released` | `recorder.stop()` põe `isRecording` em falso antes de voltar (`AudioRecorder.swift` 434), e `begin()` vem depois de `settleIcon`, então a regra desenha |
| `stop()` devolve nil | `settleIcon` já rodou antes do `guard url != nil`; pela regra |
| gravação curta demais | `Transcriber` não recusa por tamanho: ou dá texto, e cai no sucesso, ou dá falha, e cai no `.failure` |
| `finish` devolve falso | inalcançável: nada encerra a sessão por fora, e `begin` só cria com nenhuma ativa (`TranscriptionSession.swift`). Se um dia for alcançável, um risco chegado durante a transcrição fica sem redesenho |
| `begin()` nil | inalcançável pelo mesmo motivo: `DictationAttempt.decide` recusa o gatilho durante a transcrição, e o ícone já se acertou antes |
| `endOrphanRecording` | passa por `discardRecording`; pela regra (prova: L5) |
| texto vazio em `deliver` | `settleIcon` já rodou antes de `deliver`; pela regra |
| `recorder.onError` | `render(.blocked)` direto, fora da regra, igual a antes. No meio da gravação, o `.released` depois põe na regra. Com "end of recording lost", chega depois de `settleIcon` e o risco fica até o próximo ditado, com o motivo no log. É sinal de falha, como o `.failure`; não é causa perdida |

Efeito novo a favor: "Check for Updates" recusado durante uma transcrição de mais de 2 s deixava o risco preso até a próxima tecla, porque o sucesso não redesenhava. Agora sai no fim.

### 2. Alguma ordem deixa riscado sem causa, ou normal com causa?
Com as duas concedidas e o modelo bom:
* `flashIdle` sem o `if` desenha o mesmo que antes, porque a guarda de `StatusIcon.redraw` é a mesma condição. Gravação ou transcrição começando dentro dos 2 s: nada é desenhado aos 2 s, e o fim do ditado redesenha. Entre `settleIcon` e `begin()` não há suspensão, então `flashIdle` não cai ali.
* `.failure` e novo ditado: o risco fica até o gatilho, `render(.recording)` troca, e o `.released` desenha o normal. Certo, e é a decisão do PG.
* **Uma ordem encurta um sinal:** uma falha de `deliver` arma os 2 s, e um `.failure` chega dentro deles: o `flashIdle` antigo apaga o risco do `.failure` antes do próximo ditado. Duas falhas seguidas em 2 s. Já era assim, e o log tem as duas. Sem achado.
* Riscado sem causa com permissão: nenhuma ordem. Permissão tirada no ditado religa a releitura em todo fim que passa por `settleIcon`. No `.failure` não religa, mas o risco ali já fica até o próximo ditado, por decisão.
* Normal com causa: o modelo terminando de carregar durante a gravação ou a transcrição agora é desenhado no fim (B3 e B7 fechados). O que sobra é o B4, fora por decisão.

### 3. `settleIcon` religando a releitura
**Durante os pedidos da abertura: pode.** Recusa do "Open at Login" com o pedido do microfone aberto: `flashIdle`, 2 s, `settleIcon`, leitura incompleta, `start()`. Isso desmente o comentário (L7).

**Efeito real: nenhum.** `LaunchPermissions.run` não olha a releitura, que só lê, sem pedir nada. Se a resposta ao microfone chegar nesse meio-tempo, sai a linha `permissions:` e o ícone redesenha, e a linha de depois é deduplicada. O `start()` da abertura (306) vira nada, porque já roda. Não é porta nova: o gatilho (392) já fazia isso.

**Durante um ditado:** a releitura só vive ali por pouco (concedida um instante antes do gatilho, para no tique seguinte) ou com a permissão caindo durante o ditado e um `flashIdle` pendente. `permissionsChanged` escreve a linha e `renderResting` não desenha nada. Custo: uma leitura por segundo na main actor, sem efeito na transcrição, que roda no ator dela.

### 4. O custo
Binário `swiftc -O` em `<rascunho da sessão>/audit2b/leitura.swift`, microfone `notDetermined`, Acessibilidade falsa, sem TCC alterado. Não é o app assinado, com o microfone autorizado, e pode diferir dele.

| medida | mínimo | mediana | p95 | máximo |
|---|---|---|---|---|
| as duas permissões, espaçadas 0,5 s (n=40) | 18,1 ms | 20,7 ms | 29,9 ms | 31,1 ms |
| duas leituras, como um ditado (n=40) | 39,3 ms | 43,6 ms | 64,0 ms | 79,1 ms |
| `authorizationStatus` em laço (n=200) | 15,9 ms | 18,3 ms | 24,8 ms | 29,3 ms |
| `AXIsProcessTrusted` em laço (n=200) | 0,000 ms | 0,000 ms | 0,000 ms | 0,003 ms |

A primeira leitura do processo custou 80,4 ms, uma vez só; o app já a pagou na abertura.

**Não muda a decisão de pôr `settleIcon` antes de `deliver`.** São cerca de 21 ms antes da colagem e 44 ms no caminho inteiro, sobre os ~600 ms de um ditado, abaixo do que a pessoa nota. Pôr depois de `deliver` exigiria a chamada dentro dos ramos `.inserted` e texto vazio, porque nas falhas ela apagaria o risco: dois pontos a prender, para ganhar 21 ms. Reabrir só se o teste manual mostrar colagem visivelmente mais lenta.

Por leitura: o `render` novo no sucesso custa a imagem e uma linha de log. Não medi, porque `BrandMark` mora no alvo executável.

### 5. A ressalva do log
Atrapalha: L1, com o conserto. A linha `icon → brand` a mais não atrapalha: nenhum script a lê (medido pelo PG), e o log recomeça a cada abertura.

A janela da ressalva 5 do executor existe, entre a leitura de `settleIcon` e a de `start()`, de cerca de 20 ms e não de microssegundos, porque cada leitura custa isso. Exige ligar o interruptor nesse instante, e a próxima tecla corrige. Sem achado.

### 6. Os textos de `docs/reference.md`
| linha | veredito |
|---|---|
| 151 a 153, dois segundos e depois a regra | certa |
| 308 a 310, login recusado | certa: o sinal da recusa dura dois segundos, e com outra causa de pé o risco segue, como a 153 explica |
| 323 e 324, atualização recusada | **imprecisa no meio do ditado:** L6 |
| 344 a 350, o risco de modelo ou Metal fica | certa |
| 376 a 379, nem conceder nem terminar ditado apaga | certa: na gravação a onda toma o lugar e o fim do ditado devolve o risco |

Fora desta parte: a 344 ("while either one is missing, the menu bar icon is slashed") não vale com permissão tirada em repouso e releitura parada, o B4, fora por decisão.

## Sabotagens

`<rascunho da sessão>/audit2b/sab.py`: troca exata com contagem 1, `swift build`, `swift test --filter MenuLayoutTests`, volta por cópia conferida por `shasum` depois de cada uma. Todas com build verde; final 61d4a861.

| id | sabotagem | resultado |
|---|---|---|
| SET-NOSTART | `settleIcon` sem o `start()` | morre, `settleIconWiring` |
| SET-INVERT | condição invertida | morre, `settleIconWiring` |
| SET-CONST | leitura constante, tudo concedido | morre, `settleIconWiring` |
| REL-IDLE | `.released` volta a `render(.idle)` | morre, `releaseWiring` e `idleIsDrawnOnlyAtLaunch` |
| DISC-GONE | `discardRecording` sem redesenho | morre, `discardWiring` |
| FLASH-REST | `flashIdle` com `renderResting()`, sem releitura | morre, `flashIdleWiring` |
| END-ORDER | `settleIcon` depois de `deliver` | morre, `transcriptionEndWiring` |
| FAIL-RULE | `.failure` pela regra no lugar de `.blocked` | morre, `transcriptionEndWiring` |
| FAIL-AFTER | `settleIcon` depois do `.blocked` do `.failure` | **sobrevive** (L3) |
| FAILED-NOFLASH | `.failed` em `deliver` sem `flashIdle` | **sobrevive** (L4) |
| FAILED-SETTLE | `.failed` com `settleIcon` no lugar de `flashIdle` | **sobrevive** (L4) |
| ORPHAN-OWN | `endOrphanRecording` sem `discardRecording` | **sobrevive** (L5) |

As oito primeiras repetem, por outra mão, parte das 25 do executor, e confirmam a tabela dele nessa amostra. Nenhuma das quatro vivas está em `settleIcon` ou nos quatro pontos, e nenhuma esconde código do oráculo.

## Sonda

`Tests/NeverTypeCoreTests/Audit/PermissionsPart2bAuditTests.swift`, swift-testing, sem relógio e sem TCC. As sondas das partes 1, 1b e 2 não mudaram.

**`everyReturnIsDelivered`:** três ciclos de permissão perdida e devolvida; em cada um, a concessão é entregue na primeira releitura e a releitura para.
* **Contrato:** o que motivou `settleIcon`. O risco que ela desenha só sai com a concessão que a releitura entrega, e a pessoa pode perder e recuperar a permissão mais de uma vez com o app aberto.
* **Regressão que a derruba:** guardar a base entre um ciclo e outro, como propriedade do tipo, que é como o comentário dele descreve ("the last reading it handed over"). A concessão do ciclo anterior engole a nova, a releitura para, e o ícone fica riscado com as duas concedidas: o defeito de 16/10 às 08:28.
* **Por que o teste do executor não pega:** `startsAgainAfterStopping` reinicia, mas não confere `changes` no segundo ciclo, e `goingBackIsAChange` fica dentro de um ciclo só.

Prova da regressão sem tocar o repositório, porque o briefing limita a sabotagem aos trechos de risco: `<rascunho da sessão>/audit2b/regressao-watch.swift`, com uma cópia da classe de cada jeito. Entregue: 2 concessões em 2 ciclos. Com a base guardada: 1 em 2.

## Comandos e resultado

| comando | resultado |
|---|---|
| `shasum` nos quatro arquivos, no começo e depois das sabotagens | iguais aos do briefing |
| `swift test --filter PermissionsPart2bAuditTests` | 1 teste, verde |
| `python3 -I <rascunho da sessão>/audit2b/sab.py` | 8 mortas, 4 vivas, restaurado |
| `swift build` | Build complete |
| `swift test`, uma vez, no fim | 317 testes em 34 suítes, verde (316 mais a sonda) |
| `swift build --build-tests --scratch-path <rascunho da sessão>/audit2b/clean` e `python3 scripts/count-swift-warnings.py` | 4, a mesma lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28) |

Nada de `tccutil`, de script de instalação, de keychain nem de git de escrita.

## Para o teste manual do Pedro

O log é `~/Library/Application Support/NeverType/nevertype.log`.

1. **Tudo certo:** dite normalmente. O ícone segue normal e a colagem não parece mais lenta. Se parecer, o cenário 4 reabre. O log ganha um `icon → brand` depois de `transcribed in`.
2. **Permissão tirada durante o ditado:** com as duas concedidas, comece um ditado em mãos livres, desligue a Acessibilidade nos Ajustes e termine. O ícone fica riscado. Ligue de novo sem apertar a tecla: o risco some em cerca de um segundo. Repita uma segunda vez sem reabrir o app (é o que a sonda prende). Se a tecla não terminar o ditado com a Acessibilidade desligada, termine pelo menu, desligando as mãos livres, o que descarta a gravação e também deve deixar o risco. Sem a linha `permissions:` no log, a não ser que o L1 tenha sido consertado.
3. **Colagem recusada:** dite com o foco onde não dá para digitar. O risco aparece por dois segundos e o ícone volta ao normal.
4. **Modelo indisponível, só se já estiver nesse estado:** o ditado falha, em vez de dar certo como o passo 1 do progresso sugere, porque sem modelo não há transcrição. Em mãos livres, descarte com Esc: o ícone volta riscado, não normal. "Sem Metal" não se produz à mão num Apple Silicon e fica com a prova do Core.
