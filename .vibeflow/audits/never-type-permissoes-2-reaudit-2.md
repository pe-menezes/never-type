# never-type-permissoes · parte 2 · reauditoria 2

Estado: CONCLUÍDA (05/11/2026). Worktree `~/Projects/apps/never-type-permissoes`, branch `fix/permissoes-pendencias`, base do conserto `eaf613a`, nada commitado. `<scratch>` é `<rascunho da sessão>`.

## Veredito: PASS

R1 e R2 fecharam, com a suíte inteira. O diff do conserto não tem defeito novo e ficou no perímetro. Fica um achado baixo, o R3, que vira tarefa: a premissa da ressalva é falsa para `#if`, e o RR-IFCHARS não é mutação equivalente.

**Para a orquestração, a leitura que decide o veredito:** o critério do briefing segura o PASS no que o conserto declarou fechar e não fechou, e em defeito novo no diff. O R3 não é nenhum dos dois: o conserto declarou essa prova como aberta, e o filtro entregue pega a forma. Classifiquei como baixo pelo precedente do R2 da reauditoria 1 (código entregue certo, sobrevive uma mutação de uma cláusula, falta uma fonte no controle). Quem classificar diferente tem o conserto medido no R3: uma linha.

## A ressalva do executor

| mutação | decisão | prova |
|---|---|---|
| RR-IFCHARS | **não é equivalente: buraco, baixo (R3)** | abaixo |
| RR-REGEXCHARS | equivalente para o contrato | abaixo; uma ressalva sobre a linha única |
| RR-TRIPLECHARS | equivalente nas formas medidas | abaixo |

### `#if`: compila, e o código sai do programa
A frase "marca colada a esses tokens não compila" vem da reauditoria 1, e o executor a repetiu avisando que a prova cobria só 11 formas. As 11 usavam U+0301 e U+0600. U+0301 não pode começar identificador, por isso dava erro. Outras marcas podem: o `#if` vira o token e a marca vira o nome de uma condição que não está definida, portanto falsa.

`python3 -I <scratch>/r2/forms.py`, 84 formas, cada marca escrita como escape no script, Swift 6.2.3. Compilam e escondem o código (uma chamada à função escondida dá `cannot find 'wired' in scope`):

| marca logo depois de `#if` | sozinha | com um nome colado depois | depois de `;` | `contains("#if")` | `range(.literal)` |
|---|---|---|---|---|---|
| U+200D, U+200C, U+FE0F, U+E0100, U+0E33, U+1F3FB | compila, esconde | compila, esconde | compila, esconde | **não acha** | acha |

São 18 formas. Com espaço e `false` depois da marca, dá erro (`extra tokens following conditional compilation directive`), e U+0301 segue com erro.

Na suíte inteira, em `main.swift`, com a marca crua no arquivo:

| id | sabotagem | resultado |
|---|---|---|
| Z-ZWJLAUNCH | abertura inteira sob `#if` + U+200D, filtro entregue | morta, `noCodeHiddenFromTheOracles` |
| Z-ZWJMENU | `menuNeedsUpdate` sob a mesma forma, filtro entregue | morta, o mesmo |
| Z-VS16LAUNCH | abertura sob `#if` + U+FE0F, filtro entregue | morta, o mesmo |
| Z-ZWNJMENU | `menuNeedsUpdate` sob `#if` + U+200C, filtro entregue | morta, o mesmo |
| ZD-ZWJLAUNCH | Z-ZWJLAUNCH com RR-IFCHARS | **sobrevive, 310 testes** |
| ZD-ZWJMENU | Z-ZWJMENU com RR-IFCHARS | **sobrevive, 310 testes** |
| ZD-VS16LAUNCH | Z-VS16LAUNCH com RR-IFCHARS | **sobrevive, 310 testes** |

As linhas ZD são a prova de que a cláusula importa: com ela por `Character`, a abertura sai do programa e a suíte fica verde. As linhas Z são a prova de que o filtro entregue está certo, e de que o conserto fechou mais do que declarou: comparar as quatro formas por `.literal` fechou também este caso, que ninguém tinha medido.

### `#/`: só em uma linha
Marca depois de `#/`, em todas as formas de várias linhas de `forms.py` e `oneline.py`: `unterminated regex literal`, porque o literal de várias linhas exige a quebra logo depois do delimitador. Prepend antes, colado a um nome ou solto: não compila.

A ressalva: em uma linha só, `private let h = #/` + U+200D + ` x /#` compila, e RR-REGEXCHARS não recusa essa linha, que tem `#/` nos bytes. Portanto a mutação não é idêntica no texto. Ela não abre saída, por leitura e sem mutação medida: nessa forma cabe só um trecho de uma linha, e uma string comum de uma linha faz o mesmo sem token nenhum, o que é a família do A3. Nada que ocupe mais de uma linha, como função e corpo, cabe nela.

### `"""`: não compila
Marca depois, inclusive com espaços antes ou depois dela: `multi-line string literal content must begin on a new line`. Prepend antes, colado a um nome ou solto: não compila.

### O limite dessa prova
Uma marca só se junta à ponta de um token por uma destas vias: Extend, ZWJ ou SpacingMark depois, Prepend antes. As formas medidas cobrem as três. Depois do token, o erro do `"""` e o do `#/` de várias linhas vêm da quebra que falta, e isso não depende da marca escolhida. Antes do token, o Prepend só cabe no fim de um identificador, e não achei contexto em que um identificador colado a uma string ou a um regex compile. Isso é medição mais raciocínio, não demonstração, e vale para o Swift 6.2.3 daqui. Não medi o toolchain do CI.

## Achados

### R1 · fechado
`MenuLayoutTests.swift` 803 a 808: `range(of:options: .literal)` nas quatro formas, por uma lista `tokens`, como o briefing pediu.

| id | antes | agora |
|---|---|---|
| N-COMBLAUNCH | sobrevivia | morta, `noCodeHiddenFromTheOracles` |
| N-COMBMENU | sobrevivia | morta, o mesmo |
| N-PREPMENU2 | sobrevivia | morta, o mesmo |
| RR-ALLCHARS (volta a `contains` nas quatro) | não existia | morta, `hidingFormsAreFound` |
| RR-BLOCKCHARS (volta a `contains` só em `/*`) | não existia | morta, `hidingFormsAreFound` |

Fora das duas fontes do conserto, `python3 -I <scratch>/r2/block.py` testou 10 formas de `/*` (7 marcas depois e 3 Prepend antes): todas compilam e escondem, `contains` não acha nenhuma, e a comparação literal acha todas. O comentário de `linesHidingCode` bate com o relatório anterior, e o número citado, 310, é o medido.

### R2 · fechado
RR-BLOCKPREFIX morta em `hidingFormsAreFound`, com a fonte `private func keep() {} /*` na linha 727. As irmãs RR-REGEXPREFIX e RR-TRIPLEPREFIX seguem mortas.

### R3 · baixo · a comparação literal de `#if` não está presa por teste
`MenuLayoutTests.swift` 722 a 725. `hidingFormsAreFound` não tem fonte com marca colada ao `#if`, e RR-IFCHARS sobrevive, 310 testes.
* **Contrato:** `linesHidingCode` recusa toda linha com `#if` nos bytes.
* **Regressão que derruba:** reescrever a lista `tokens` em cláusulas separadas e deixar o `#if` por `contains`.
* **Por que a suíte não pega:** a fonte de exemplo com marca existe só para `/*`, e o briefing do conserto pediu só essas, sobre a premissa falsa.
* **Por que é baixo:** o código entregue pega a forma (linhas Z). Para virar efeito precisa de duas coisas juntas, desmontar a lista só para o `#if` e gravar `#if` com um caractere invisível em `main.swift`. A regressão natural, voltar a `contains` em tudo, já morre (RR-ALLCHARS).
* **Conserto medido, sem ficar aplicado:** a fonte `"#if\u{200D}"` em `hidingFormsAreFound`. SK-IFSOURCE-CLEAN: verde, 310 testes. SK-IFSOURCE-KILL, com RR-IFCHARS: morta em `hidingFormsAreFound`.

**Correção do registro:** a frase da reauditoria 1 ("as outras três formas não têm essa saída") está errada para `#if`. O relatório anterior e o progresso ficam como estão, e esta linha é a correção.

## Defeito novo no diff do conserto

Nenhum. `git diff -U0 eaf613a -- Tests Sources scripts docs`: só `MenuLayoutTests.swift`, só `hidingFormsAreFound` e `linesHidingCode`. Uma imprecisão sem efeito: o progresso diz 13 linhas adicionadas em `Tests`, e o diff tem 12.

## Fora por decisão

A3, N-DECOY-SPACE, N-DECOY-COMMENTED e o cenário 1 não foram reabertos. Não procurei forma de outra família; o R3 é da família do R1, e o briefing mandou decidi-lo.

## Sondas

Nenhuma nova. O briefing não dá caminho de arquivo de testes, e `linesHidingCode` é privada do teste, então sonda de fora não a alcança. Os cenários ficam reproduzíveis em `<scratch>/r2/`: `muts.py`, `sweep.py`, `forms.py`, `block.py`, `oneline.py`, com resultados em `full.jsonl` e `forms.jsonl`. As linhas de mutação ficam no relatório.

## Comandos rodados

* `shasum` no início e no fim, iguais: `main.swift` 252dc4ff, `Permissions.swift` b313bccb, `MenuLayoutTests.swift` f814ae88.
* `swift test --skip-build`, antes das mutações: **310 testes em 33 suítes, passou**, 14,5 s.
* `python3 -I <scratch>/r2/sweep.py --backup`, e `python3 -I <scratch>/r2/sweep.py <scratch>/r2/full.jsonl`: 49 mutações, uma por vez, suíte inteira, volta por cópia com sha conferido.
  * As 40 de `c2/muts.py`: como o progresso declara. **26 de 26 do conserto 1 mortas**; N-COMBLAUNCH, N-COMBMENU, N-PREPMENU2 e RR-BLOCKPREFIX mortas; RR-REGEXPREFIX, RR-TRIPLEPREFIX, RR-ALLCHARS, RR-BLOCKCHARS, N-SEMIBLOCK, N-TABIF e N-HASH2REGEX2 mortas; RR-IFCHARS, RR-REGEXCHARS e RR-TRIPLECHARS sobrevivem. Todas com build verde.
  * As 9 novas: como na seção da ressalva e no R3.
* `python3 -I <scratch>/r2/forms.py`, `block.py` e `oneline.py`: como acima. Controles de `forms.py`: sem esconder, compila; `#if false`, `#/` e `#"""` comuns, compilam e escondem.
* Depois das mutações, `swift build --build-tests`: Build complete. `swift test --skip-build`: **310 testes em 33 suítes, passou**, 14,9 s.
* `swift build --build-tests --scratch-path <scratch>/r2/clean` e `python3 scripts/count-swift-warnings.py <scratch>/r2/clean.log`: **4**, os mesmos quatro pela lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28).
* `grep -cE '#if|#/|/\*|"""' Sources/NeverType/main.swift`: 0.
* Nas 12 linhas adicionadas em `Tests`: 0 travessão ou aspas curvas e 0 caractere invisível cru (categorias Mn, Mc e Cf).
* `git status --short` no fim: `MenuLayoutTests.swift`, o progresso, `models` e este relatório. Nenhum `tccutil`, nenhum script de instalação, nenhum git de escrita, nada consertado.
