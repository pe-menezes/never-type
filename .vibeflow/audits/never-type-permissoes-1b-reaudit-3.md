# never-type-permissoes · parte 1b · reauditoria 3

Reauditor em sessão limpa. Comecei em 16/10/2026 às 10:24, depois do conserto 3. Branch `fix/permissoes-icone`, base do conserto `c50aa43`, conserto não commitado.

* Shas conferidos às 10:24 e de novo às 10:44, iguais aos do briefing: `main.swift` 4ecb8338 e `MenuLayoutTests.swift` 891ee521.
* Os outros cinco arquivos da parte estão iguais aos da reauditoria 2: `StatusIcon.swift` ac60fa3e, `StatusIconTests.swift` a33cab34, `Permissions.swift` 44236b27, `DictationAttempt.swift` a3aa59da e `MenuLayout.swift` 1c7a6dec.
* Sondas da auditoria intactas: `PermissionsPart1bAuditTests.swift` b05faa3d e `PermissionsPart1AuditTests.swift` d0eca29d.
* Fiz um backup novo em `<scratchpad>/reaudit3-1b/bak/`, conferido por `shasum` e igual ao `bak1` do executor. Toda mutação foi desfeita por cópia dessa pasta, com o sha conferido depois de cada uma. Nenhuma ficou aplicada.
* Li só o diff do conserto (pacote `never-type-permissoes-1b-pacote-conserto-3.md`) e o código que ele toca. O conserto ficou no escopo dos achados.

## Veredito: PARTIAL

**Para a orquestração: uma ligação da classe ainda sobrevive, e a causa é a mesma do A1 e do A2.** Pelo briefing, a frente para aqui e a quarta volta vai ao Pedro.

O que fechou:
* as seis mutações da classe (X-AB1 a X-AB3, X-MD1, X-MD2 e X-MN1);
* as 97 do executor, que põem um `return` ou um `if` sempre falso em cada ponto de dentro das três funções;
* o B8, o B9 e o B10.

O que sobrevive: a borda do corpo preso. `body(of:)` (`MenuLayoutTests.swift` 713 a 727) acha a linha de abertura da função por `contains` e prende só as linhas **depois** dela até a linha que fecha. Um `return` escrito depois do `{` da própria linha de abertura fica fora do que o teste confere, e a suíte inteira passa (298 testes). O mesmo vale para um `if` sempre falso aberto ali e fechado na linha do `}` final, e para a função inteira desligada por `#if false`. Ou seja, a linha de abertura está provada só pela presença do texto, e o resto por uma janela que começa uma linha abaixo dela. É o mecanismo do A1 e do A2 numa forma menor.

A forma da sabotagem é pouco idiomática: código na mesma linha do `{` da função. Mesmo assim, o critério de fechamento escrito no briefing do conserto 3 era "um `return` ou um `if` sempre falso **em qualquer ponto** dessas funções também morre". A linha de abertura é um ponto da função, e esse critério não se cumpre. O buraco também alcança os oráculos inteiros das rodadas anteriores, como o `handle` e os avisos. Por isso a frase da reauditoria 2, "nenhuma mutação sobreviveu nas funções presas inteiras", só vale para o miolo delas.

## Achados

### A2 e a classe · buraco em código de risco · **as seis fecharam, a borda segue aberta**

**O que fechou.** `launchWiring` prende `applicationDidFinishLaunching` inteiro (59 linhas de código). `menuPermissionConditionsWiring` prende `rebuildMenu` inteiro. O novo `menuItemsWiring` prende `item(for:)` inteiro. Todos usam o mesmo molde `codeLines(body) == [...]` do `handle`. Rodei de novo as listas no estado entregue:
* X-AB1, X-AB2, X-AB3, X-MD1 e X-MD2 morrem em `launchWiring`;
* X-MN1 morre em `menuPermissionConditionsWiring`;
* as 97 do conserto 3 morrem todas: saída e `if` sempre falso em cada instrução do primeiro nível da abertura, dentro das duas `Task` e no laço do menu;
* as minhas confirmam o miolo. Uma linha recuada no nível da função (Y-LI1) ou com tab (Y-TB1) no meio do corpo trunca o corpo achado e morre, em `launchWiring`, `permissionLineWiring` e `undeterminedMicrophoneWiring`. Uma saída em três pontos de `item(for:)`, que a lista do executor não cobria (Y-IT1 a Y-IT3), morre em `menuItemsWiring`.

**O que sobrevive.** Onze mutações minhas, todas com build verde e a suíte inteira verde (`SWEEP_FILTER=.`, 298 testes em 32 suítes):

| id | função | mutação | efeito no app | resultado |
|---|---|---|---|---|
| Y-ML1 | `applicationDidFinishLaunching` | ` if ProcessInfo.processInfo.processIdentifier > 0 { return }` depois do `{` da linha 234 | a abertura não faz nada: nenhum ícone, nenhum pedido de permissão, nenhum modelo | **sobrevive** |
| Y-ML2 | `applicationDidFinishLaunching` | `if … < 0 {` depois do `{` da linha 234, fechado com `}}` na linha do `}` final | o mesmo | **sobrevive** |
| Y-PP1 | `applicationDidFinishLaunching` | `#if false` antes da linha 234 e `#endif` depois do `}` final | o mesmo: o método é opcional no protocolo e compila sem ele | **sobrevive** |
| Y-ML3 | `rebuildMenu` | saída depois do `{` da linha 1014 | o menu abre vazio, sem as linhas de permissão e sem Quit (o X-MN1, uma linha acima) | **sobrevive** |
| Y-ML4 | `rebuildMenu` | `if` sempre falso aberto na linha 1014 e fechado no `}` final | o mesmo | **sobrevive** |
| Y-ML5 | `item(for:)` | ` if … > 0 { return .separator() }` depois do `{` da linha 1045 | todo item do menu vira separador | **sobrevive** |
| Y-ML6 | `item(for:)` | `if` sempre falso aberto na linha 1045 e `}; return .separator() }` no fim | o mesmo | **sobrevive** |
| Y-ML7 | `renderResting` (rodadas anteriores) | saída depois do `{` da linha 921 | o ícone nunca sai do risco sozinho: é o caso das 08:28 de volta | **sobrevive** |
| Y-ML8 | `permissionsChanged` (rodadas anteriores) | saída depois do `{` da linha 909 | a releitura acha a mudança e não loga nem redesenha | **sobrevive** |
| Y-ML9 | `handle` (rodadas anteriores) | ` if … > 0 { return false }` depois do `{` da linha 383 | a tecla não faz nada | **sobrevive** |
| Y-ML10 | `showAccessibilityRequiredAlert` (rodadas anteriores) | saída depois do `{` | o aviso da Acessibilidade nunca aparece | **sobrevive** |

Por que passam:
* `body(of:)` filtra as linhas da fonte por `lines[$0].contains(marker)`. O que vem depois do marcador na mesma linha passa. O corpo começa em `start + 1`.
* O corpo termina na primeira linha recuada até o nível do marcador. O `}}` e o `}; return .separator() }` têm esse recuo, então encerram o corpo e não entram nele.
* No `#if false`, o texto inteiro da função continua no arquivo. O teste só confere texto.

`private func applicationDidFinishLaunching` (Y-AC1) não compila, porque o protocolo exige a visibilidade. Essa forma não vale.

**É a mesma causa do A1 e do A2?** Sim. A decisão "esta linha roda em toda abertura" continua provada por presença de texto (a linha de abertura, por `contains`) mais uma janela de linhas (de `start + 1` até o fecho). O conserto fechou o miolo da janela, mas não as duas bordas.

**O que fecharia (decisão do conserto, não minha, e a lista não é exaustiva):**
* em `body(of:)`, exigir que a linha do marcador, aparada, seja igual ao marcador, e que a linha que encerra o corpo, aparada, seja exatamente `}`;
* para o `#if false`, conferir que o `main.swift` não tem linha de compilação condicional. Medi às 10:43 por `grep -n "^ *#if"`: hoje são 0.

Reprodução: `cd ~/Projects/apps/never-type-permissoes && SWEEP_FILTER=. python3 -I <scratchpad>/reaudit3-1b/mine/sweep.py depois <scratchpad>/reaudit3-1b/bak <saida>.jsonl Y-ML1` (e os outros ids). As mutações estão em `<scratchpad>/reaudit3-1b/mine/muts.py`. O `sweep.py` é o do executor, copiado sem mudança (sha 3b709773 nas duas cópias).

### B11 · baixo · novo · fora da classe · `menuNeedsUpdate` não tem prova
`menuNeedsUpdate` (`main.swift` 1453 a 1455) é o único chamador de `rebuildMenu`. Duas mutações minhas sobrevivem à suíte inteira:
* Y-MU1: `rebuildMenu()` dentro de um `if` sempre falso;
* Y-MU2: uma saída antes dele.

O efeito é o menu abrindo vazio, com as linhas de permissão e o Quit sumindo. O código é de antes da frente (está em `main`, linha 1419 de lá) e a frente não decidiu nada nele. Por isso fica fora da classe, no mesmo critério que a reauditoria 2 usou no B10. A falha também é barulhenta: o primeiro clique no ícone mostra o menu vazio. Vira tarefa: prender o corpo de `menuNeedsUpdate`, junto com o conserto da borda.

### B8 · baixo · **fechado**
O comentário de `renderResting` (`main.swift` 913 a 920) agora diz o que é verdade, e conferi contra o código:
* o `.released` chama `render(.idle)` na linha 457, fora da regra;
* no `.success`, `deliver` com `.inserted` só faz `break` e não redesenha nada;
* o `.recording` é a onda (`StatusIcon.swift` 76 a 80).

É frase de comentário, então é sonda de estado e fica neste relatório.

### B9 · baixo · **fechado**
* `micAuthorized` saiu: `grep -rn micAuthorized Sources Tests .vibeflow/patterns` dá vazio.
* O exemplo de `.vibeflow/patterns/estado-consultado.md` cita `MicrophoneAccess.current`. O trecho é igual, linha a linha, a `Permissions.swift` 32 a 37.
* `PermissionReading.current` existe (`StatusIcon.swift` 22).
* A regressão que a propriedade deixava caber numa linha que compila, o M9, foi reescrita como M9b com `MicrophoneAccess.current` e morre em `launchWiring`. O M9 original não compila mais (`no member 'micAuthorized'`), que é o esperado.
* O travessão da linha nova do padrão segue o formato do cabeçalho que ela substitui. Fica em `.vibeflow/`, fora de `Sources` e `Tests`, onde a contagem deu 0. Não é achado.

### B10 · baixo · **fechado**
* X-AV1 morre em `settingsPagesWiring`, que prende `openAccessibilitySettings` e `openMicrophoneSettings` inteiros.
* X-AV2 morre em `menuItemsWiring`.
* As AV3 e AV4 do executor, as duas funções sem o `open`, também morrem.

Ressalva: as duas funções de Ajustes têm a mesma borda do achado acima, porque são presas pelo mesmo `body(of:)`. Ela se fecha com o mesmo conserto.

### B1 · baixo · segue aberto
X-PW8 sobrevive. É o intervalo de um segundo, sem prova possível sem relógio. P3 continua sem build. Segue como tarefa, sem reabrir.

### B3, B4, B6
Seguem como tarefa, por decisão escrita no briefing. Não reabri.

## A ressalva do executor: toda linha das três funções presa
Classificação: é o custo já descrito na reauditoria 2 para oráculo inteiro. Não é sonda de estado. Mudar o texto do menu, um `log("ready…")` ou um `toolTip` em `item(for:)` pede uma linha no array esperado, no mesmo commit, e a falha é barulhenta (o teste mostra o corpo inteiro). O custo cresceu com `item(for:)`, que é o maior dos três e tem todo o texto visível do menu. Não pede conserto. Se o Pedro achar o custo alto, a alternativa que ainda fecha a classe é prender só as linhas de permissão de `item(for:)` por `case` (o `body(of: "case .openAccessibilitySettings:")` já existe no arquivo) e deixar o resto do menu com o `MenuLayout`, que é testado por comportamento.

## Varreduras

Todas rodaram no estado entregue, com o backup meu como `bak`. O filtro foi o das seis suítes da parte, e os sobreviventes rodaram de novo com a suíte inteira. Só conta como morta a mutação com build verde e com teste nomeado.

| lista | mutações | mortas | sobreviventes | sem build | diferença do executor, id por id |
|---|---|---|---|---|---|
| conserto 3 (`conserto3-1b/muts.py`) | 97 | 97 | 0 | 0 | 0 |
| reauditoria 2 (`conserto3-1b/re2/muts.py`, igual ao `reaudit2-1b/mine/muts.py`) | 27 | 26 | 1 (X-PW8, B1) | 0 | 0 |
| conserto 2 (`conserto3-1b/c2/muts.py`, igual ao `conserto2-1b/muts.py`) | 110 | 108 | 0 | 2 (P3, M9) | 0 |
| minhas (`reaudit3-1b/mine/muts.py`) | 19 | 5 | 13 | 1 (Y-AC1) | não se aplica |

As minhas, uma a uma:

| id | ponto | resultado |
|---|---|---|
| Y-ML1, Y-ML2, Y-PP1 | borda de `applicationDidFinishLaunching` | **sobrevivem** (classe) |
| Y-ML3, Y-ML4 | borda de `rebuildMenu` | **sobrevivem** (classe) |
| Y-ML5, Y-ML6 | borda de `item(for:)` | **sobrevivem** (classe) |
| Y-ML7 a Y-ML10 | borda de `renderResting`, `permissionsChanged`, `handle` e `showAccessibilityRequiredAlert` | **sobrevivem** (classe, em oráculos das rodadas anteriores) |
| Y-MU1, Y-MU2 | `menuNeedsUpdate` | **sobrevivem** (B11) |
| Y-AC1 | `private` na abertura | sem build (o protocolo exige a visibilidade) |
| Y-LI1 | `if` recuado no nível da função, no meio da abertura | morre (launchWiring, permissionLineWiring, undeterminedMicrophoneWiring) |
| Y-TB1 | saída recuada com tab, no meio da abertura | morre (os mesmos três) |
| Y-IT1, Y-IT2, Y-IT3 | saída dentro de `item(for:)`, em três pontos | morrem (menuItemsWiring) |

## Mudança de comportamento no conserto 3

Nenhuma, como o executor declarou:
* o B8 é comentário;
* o B9 tira uma propriedade privada sem chamador, e o build passa;
* os testes só leem a fonte.

O diff do `main.swift` tem só essas duas mudanças (pacote, linhas 380 a 447).

## Sondas

Não escrevi sonda nova, e `PermissionsPart1bAuditTests.swift` segue intacto (b05faa3d) e verde. O briefing só autoriza sonda nova quando um achado fechado fica sem prova na suíte, e nenhum ficou:
* as seis da classe e o B10 morrem em teste do executor;
* o B9 morre no M9b;
* o B8 é frase, sonda de estado, e fica aqui.

O achado aberto, a borda, se prova pela varredura (`mine/muts.py`). O teste que a mata seria o próprio conserto do `body(of:)`, que é trabalho do executor. `checa-sondas.py --pasta Tests/NeverTypeCoreTests/Audit`: 2 arquivos lidos, 0 trecho suspeito.

## Para o teste manual do Pedro (mantido da reauditoria 2)

O conserto 3 não muda nenhum passo, e o log da abertura sai igual. O log fica em `~/Library/Application Support/NeverType/nevertype.log`. No log, o ícone aparece como `icon → brand` (normal) e `icon → brand.slash` (riscado). O `render` escreve uma linha a cada desenho, sem deduplicar.

1. **O caso das 08:28.** Microfone autorizado, Acessibilidade desligada, app aberto e parado. Ligue a Acessibilidade nos Ajustes e não aperte a tecla. Deve aparecer: o risco some em cerca de um segundo, e o log ganha `permissions: microphone=authorized accessibility=granted` seguido de `icon → brand (monochrome)…`.
2. **A releitura parou.** Depois do passo 1, espere um minuto sem mexer. Deve aparecer: nenhuma linha nova `icon →` nem `permissions:` no log, e o NeverType perto de 0% de CPU no Monitor de Atividade.
3. **O microfone, como a referência diz agora.** Com o app aberto e o microfone desligado, ligue o microfone nos Ajustes. Deve aparecer o **Quit & Reopen** do macOS. Escolha **Quit & Reopen**: o app reabre com o ícone normal, e o log da abertura tem `permissions: microphone=authorized …`. Opcional: repita escolhendo **Later**. Se o risco sumir sozinho em cerca de um segundo, a referência poderia dizer mais. Se não sumir, ela já está certa. Nos dois casos não há conserto.
4. **A ordem dos pedidos.** Numa primeira abertura, ou depois de revogar as duas pelos Ajustes (sem `tccutil`), o pedido do microfone vem primeiro e o da Acessibilidade depois de responder.
5. **Custo com o microfone negado (B2).** Microfone negado, app aberto e parado por um minuto. Deve aparecer: a CPU do NeverType perto de 0%. Se ficar visivelmente acima do normal em repouso, o B2 vira conserto.
6. **Abertura com tudo certo.** Abra o app com as duas permissões e o modelo instalado. Deve aparecer, depois da linha `model: Metal · …`, a linha `ggml devices: …` e mais uma `icon → brand`, e o ícone normal o tempo todo.
7. **Opcional, o risco do modelo fica.** Com o modelo indisponível na instalação, o passo 1 deixa o ícone riscado, e o log tem `model:` com a falha e nenhuma linha `ggml devices:`.
8. **Opcional, ditado durante o carregamento.** Com o modelo indisponível, abra o app e segure a tecla logo em seguida, por uns três segundos. Deve aparecer: a onda de gravação até soltar, sem risco por cima dela no meio da gravação, e o risco depois que a transcrição falha (`TRANSCRIPTION FAILED` no log).
9. **Permissão tirada com o app parado (B4).** Com as duas concedidas e o ícone normal, desligue a Acessibilidade nos Ajustes. Hoje o esperado é: o ícone segue normal até a próxima tecla, que risca e mostra o aviso. Confirme se é aceitável.
10. **Novo, opcional: as duas páginas dos Ajustes (B10).** Com a Acessibilidade desligada, abra o menu e escolha `Open Accessibility Settings…`. Deve abrir Privacidade e Segurança › Acessibilidade. Com o microfone negado, `Open Microphone Settings…` deve abrir Privacidade e Segurança › Microfone.

## Comandos rodados

* `shasum` dos sete arquivos da parte e das duas sondas, às 10:24 e às 10:44: os do briefing. O backup em `<scratchpad>/reaudit3-1b/bak/` está conferido contra o `conserto3-1b/bak1/` (0 diferença).
* `swift build && swift test`: exit 0, **298 testes em 32 suítes, verde**.
* `swift test --skip-build --filter "PermissionsPart1bAuditTests|PermissionsPart1AuditTests"`: 10 testes em 2 suítes, verde.
* `python3 scripts/test-count-swift-warnings.py`: 9 testes, OK. Não rodei de novo o build limpo com os quatro warnings: o PG mediu às 10:22, e o conserto não muda o código compilado além de apagar uma propriedade.
* `python3 -I <scratchpad>/conserto3-1b/sweep.py depois <scratchpad>/reaudit3-1b/bak <scratchpad>/reaudit3-1b/c3/depois.jsonl`: 97 mortas.
* `python3 -I <scratchpad>/conserto3-1b/re2/sweep.py depois … reaudit3-1b/re2/depois.jsonl`: 26 mortas, X-PW8 sobrevive.
* `python3 -I <scratchpad>/conserto3-1b/c2/sweep.py depois … reaudit3-1b/c2/depois.jsonl`: 108 mortas, P3 e M9 sem build.
* Comparação id por id com os `.jsonl` do executor, resultado e teste nomeado: 0 diferenças nas três listas.
* `python3 -I <scratchpad>/reaudit3-1b/mine/sweep.py depois … reaudit3-1b/mine/mine.jsonl`: 19 mutações, 5 mortas, 13 sobreviventes, 1 sem build.
* `SWEEP_FILTER=. python3 -I <scratchpad>/reaudit3-1b/mine/sweep.py depois … mine/full.jsonl` com os 13 sobreviventes: os 13 passam em 298 testes de 32 suítes.
* `git diff --stat c50aa43` em `docs`, `scripts`, `Package.swift`, nos README, em `Sources/NeverTypeCore`, em `Tests/NeverTypeCoreTests/Audit` e em `.vibeflow/audits`: vazio.
* `git diff -U0 c50aa43 -- Sources Tests | grep '^+' | grep -cE "—|–|“|”|‘|’"`: 0.
* `checa-sondas.py --pasta Tests/NeverTypeCoreTests/Audit .`: 0 trecho suspeito.
* `git status --short`: os quatro arquivos do conserto, `models` e este relatório.
