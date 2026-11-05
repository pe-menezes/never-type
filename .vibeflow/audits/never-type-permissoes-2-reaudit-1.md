# never-type-permissoes · parte 2 · reauditoria 1

Estado: CONCLUÍDA (05/11/2026). Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-pendencias`, base do conserto `44fd09c`, nada commitado. `<scratch>` é `<rascunho da sessão>/reaudit1`.

## Veredito: PARTIAL

O conserto faz o que os achados pediam, e nenhuma linha de código do app mudou. Um único achado segura o PASS, o R1: `linesHidingCode` ainda não recusa toda linha com `/*`. O conserto é de uma expressão e está medido. A2, A4, A5 e a poda fecharam. A6 fechou, com uma nota baixa (R2).

**Para a orquestração:** o R1 é da classe do A1, do F-RAW e do Y-PP1, então cabe ao PG decidir se conta como o mesmo achado voltando (dev-remoto, princípio 8). Minha leitura: a causa é outra. Até aqui faltava forma na lista ou o filtro olhava só o começo da linha; agora a lista está certa e a comparação é que é por `Character`. O `contains("/*")` da auditoria tinha o mesmo buraco, então o conserto não o criou. A forma é deliberada, como a do A2, e nenhum acidente a escreve.

## Achados da reauditoria

### R1 · buraco em código de risco · `/*` escapa do filtro com uma marca Unicode colada
`MenuLayoutTests.swift` 796. `String.contains` compara por `Character`, e o compilador lê o arquivo por escalar. Uma marca Unicode colada ao token junta os dois no mesmo grafema: o Swift abre o comentário e o filtro não vê `/*`.

O contrato é "recusa toda linha de `main.swift` que contenha `#if`, `#/`, `/*` ou `"""`" (briefing do conserto, A1), e estas linhas têm `/*` nos bytes. Por isso é achado, e não forma de outra família, que o briefing manda não procurar.

| id | forma (o que entra em `main.swift`) | efeito | resultado, suíte inteira |
|---|---|---|---|
| N-COMBLAUNCH | `/*\u{0301} off` antes de `applicationDidFinishLaunching`, `*/` depois | a abertura inteira fora do programa, o mesmo efeito do Y-PP1 | **sobrevive**, 310 testes |
| N-COMBMENU | a mesma em volta de `menuNeedsUpdate` | menu sem reconstrução | **sobrevive**, 310 testes |
| N-PREPMENU2 | `private static let keep\u{0600}/* off` antes de `menuNeedsUpdate`, `*/ = 0` depois | o mesmo | **sobrevive**, 310 testes |

Na tabela, `\u{...}` indica o caractere em si, gravado cru no arquivo.

Prova de que é comentário de verdade (`<scratch>/contains/effect.py`, `swiftc -typecheck`, com uma chamada à função escondida): sem comentário, compila; com `/*` comum, com U+0301 e U+FE0F e U+200D depois, e com U+0600 antes, todas dão `cannot find 'wired' in scope`. O código saiu do programa, e o oráculo de texto continua lendo.

As outras três formas não têm essa saída. Nos casos em `<scratch>/contains/forms.py`, marca colada a `#if`, `#/` e `"""` não compila (`an identifier cannot begin with this character`, `unterminated regex literal`, `multi-line string literal content must begin on a new line`, `consecutive declarations on a line`). O que abre o buraco é o `/*`, porque o conteúdo de um comentário é livre logo depois do token.

**Conserto medido, sem ficar aplicado.** Comparar por bytes ou por escalar, nas quatro formas. Medi duas escritas, e as duas servem:
* `$0.utf8.contains("/*".utf8)`: SK-UTF8-COMB e SK-UTF8-PREP2 morrem em `noCodeHiddenFromTheOracles`; SK-UTF8-CLEAN verde, 310 testes.
* `$0.range(of: "/*", options: .literal) != nil`: SK-LITERAL-COMB e SK-LITERAL-PREP2 morrem no mesmo teste; SK-LITERAL-CLEAN verde, 310 testes.

Uma fonte de exemplo com `/*\u{0301}` em `hidingFormsAreFound` prende o conserto.

### R2 · baixo · o controle de `/*` não prova "em qualquer ponto da linha"
`MenuLayoutTests.swift` 720 e 726. O título diz "wherever on the line it starts", e a fonte de `/*` é só `"    /*"`. RR-BLOCKPREFIX, com `/*` procurado só no começo da linha aparada, **sobrevive**, 310 testes. As formas irmãs morrem: RR-BLOCKRAWPREFIX, RR-REGEXPREFIX, RR-TRIPLEPREFIX e RR-PREFIX.

O código entregue está certo, e o contrato do A6 ("uma fonte de exemplo para cada forma") foi cumprido. Falta só uma fonte, como `"private func keep() {} /*"`, que cabe na mesma lista do R1. Sonda não resolve: `linesHidingCode` é privada do teste.

## Os achados da auditoria

| achado | estado | prova |
|---|---|---|
| A1 | **aberto em parte (R1)** | fechou o que a auditoria mediu: R-SEMIIF, R-FORMFEED e R-REGEX2 morrem em `noCodeHiddenFromTheOracles`, e N-SEMIBLOCK, N-TABIF e N-HASH2REGEX2 também. Falta a forma do R1 |
| A2 | **fechado** | R-DECOY morre em `menuNeedsUpdateWiring`, N-DECOY-TRAIL e R-DECOYCASE morrem, e RR-EXACTHITS e RR-NOWHOLE morrem nos testes da régua. A saída do R1 não existe aqui: marca depois da chave do marcador não compila (U+0301, U+FE0F, U+200D, `effect.py`) |
| A4 | **fechado** | a frase bate com a fonte, número por número (abaixo). Título e regra iguais |
| A5 | **fechado** | `git diff -U0 44fd09c -- Sources`: 0 linha que não seja `///`. Os três comentários batem com `askAgain` lido agora (`Permissions.swift` 103 a 137) |
| A6 | **fechado, com a nota R2** | RR-NOIF, RR-NOREGEX, RR-NOBLOCK, RR-NOTRIPLE e RR-PREFIX morrem em `hidingFormsAreFound`, e `cleanSourceHidesNothing` passa. Uma fonte para cada forma, com `;` e form feed |
| poda | **fechado, sem prova perdida** | abaixo |
| A3, cenário 1 | fora por decisão | não reabertos |

**A4, número por número.**
* 65,7 s e "continua preso": `audit2/tl-pty.txt` 14 e 15, `recorded an issue … Time limit was exceeded` aos 65,7 s, morto pelo script aos 240,7 s.
* "Not one swift-testing line" por pipe: relatório da auditoria, tabela do A4.
* A causa, a saída em buffer perdida: mesma tabela, parágrafo seguinte.
* 4 min 11 s em 16/10: progresso da parte 1, linha 69, conferido pela auditoria.
* "One run each way" fica escrito, sem generalizar. Não medi de novo: é sonda de estado, e a frase cita uma medição datada.

**A poda: apagar a sonda não tirou prova nenhuma.** `answerFromBackgroundQueue`, `Calls` e o `MARK` saíram, e só isso, pelo diff: as outras sondas de `PermissionsPart1AuditTests.swift` não mudaram, e `PermissionsPart1bAuditTests.swift` e `PermissionsPart2AuditTests.swift` têm o mesmo sha. `LaunchPermissions.run` sabotada, com a suíte já sem ela:

| id | sabotagem | resultado | quem pega |
|---|---|---|---|
| LP-NONE | não pede o microfone | morta | `accessibilityWaitsForTheMicrophone` |
| LP-TWICE | pede duas vezes | morta | o mesmo |
| LP-ORDER | Acessibilidade antes | morta | o mesmo |
| LP-ELSE | `else if`, sem Acessibilidade depois do pedido | morta | o mesmo |
| LP-NOACCESS | nunca pede a Acessibilidade | morta | o mesmo e `answeredMicrophoneIsNotAsked` |
| LP-ALWAYSACCESS | pede mesmo já concedida | morta | `grantedAccessibilityIsNotAsked` |
| LP-S5 | pede de novo negado e restrito | morta | `answeredMicrophoneIsNotAsked` |
| LP-OFFMAIN | sem `@MainActor` em `run` | sem build | `main.swift` 296 |
| LP-DETACHED | um `Task.detached` antes do pedido de Acessibilidade | sobrevive, equivalente | a auditoria mediu o mesmo com a sonda ainda presente (`audit2/sweep1.jsonl`): a função segue na main actor |

O que só a sonda afirmava era a Acessibilidade na thread principal depois de uma volta fora dela. Quem garante isso é o tipo: `run` é `@MainActor`, e tirar o atributo não compila.

## Defeito novo no diff do conserto

Nenhum. O R1 já existia antes dele, e o `contains(marker)` novo de `body(of:)` não abriu saída (linha A2 da tabela). `grep` por `answerFromBackgroundQueue`, `Calls`, `DispatchQueue` e `Thread.` no arquivo podado: 0.

## Notas, de outra família, que não seguram o PASS

Por decisão do briefing. Estas formas não têm o marcador na linha da função real, e a contagem por `contains` da régua antiga dava o mesmo resultado (por leitura, não medi nela).

| id | forma | resultado |
|---|---|---|
| N-DECOY-SPACE | dois espaços antes do `{` e `if … { return }` na linha da função real, mais a `Decoy` com a cópia exata | sobrevive, 310 testes; o efeito é o do R-DECOY, menu vazio |
| N-DECOY-COMMENTED | a função real comentada com `//` linha a linha, mais a `Decoy` | sobrevive, 310 testes; menu sem reconstrução |

É a família `R-OVERLOAD` do A3, e a tarefa que a auditoria já sugeriu cobre as duas: conferir que o nome da função presa aparece em uma declaração só.

## Sondas

Nenhuma nova. O briefing não dá caminho de arquivo de testes, e o R1 e o R2 são da régua, cuja função é privada do teste. Os cenários ficam em `<scratch>/muts.py`, `<scratch>/sweep.py` e `<scratch>/contains/`, com as formas escritas acima para reproduzir à mão. `checa-sondas.py`: 3 arquivos, 0 trecho suspeito.

## Comandos rodados

* `shasum` no início e no fim, iguais ao progresso: `main.swift` 252dc4ff, `Permissions.swift` b313bccb, `MenuLayoutTests.swift` 1d3200cf, `PermissionsPart1AuditTests.swift` 64543f67, `PermissionsPart1bAuditTests.swift` b05faa3d, `PermissionsPart2AuditTests.swift` 24e6a9bf, `docs/pitfalls.md` 0cf2fee2.
* `swift test --skip-build`, antes das mutações: **310 testes em 33 suítes, passou**, 14,7 s.
* `python3 -I <scratch>/sweep.py --backup`, e `python3 -I <scratch>/sweep.py <scratch>/full.jsonl`: 56 mutações, uma por vez, suíte inteira, volta por cópia com sha conferido a cada uma. As 26 do conserto, repetidas: **26 de 26 mortas**, com os testes que o progresso nomeia. O resto está nas tabelas acima. N-HASH2REGEX, N-REGEXLAUNCH, N-PREPMENU, SK-LITERAL-PREP e SK-UTF8-PREP deram sem build, por forma minha que não cabe em `extension` ou regex inválida, e não contam.
* `python3 -I <scratch>/sweep.py <scratch>/full2.jsonl N-PREPMENU2 SK-LITERAL-PREP2 SK-UTF8-PREP2 N-HASH2REGEX2`: como nas tabelas.
* `swift <scratch>/contains/probe.swift`, `python3 -I <scratch>/contains/forms.py` e `python3 -I <scratch>/contains/effect.py`: como no R1.
* Depois das mutações, `swift build --build-tests`: Build complete. `swift test --skip-build`: **310 testes em 33 suítes, passou**, 24,0 s.
* `swift build --build-tests --scratch-path <scratch>/clean` e `python3 scripts/count-swift-warnings.py <scratch>/clean.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `git diff -U0 44fd09c -- Sources`, linha que não é `///`: 0. Travessão e aspas curvas nas linhas novas de `Sources`, `Tests` e `docs`: 0. `grep -cE` das quatro formas em `main.swift`: 0.
* `git status --short` no fim: os arquivos do conserto, `models` e este relatório. Nenhum `tccutil`, nenhum script de instalação, nenhum git de escrita, nada consertado.
