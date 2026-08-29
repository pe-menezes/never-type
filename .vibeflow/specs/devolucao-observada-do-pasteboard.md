# Spec: Devolução observada do pasteboard

> Gerado via /vibeflow:gen-spec em 2026-08-28
> Item D1 de `.vibeflow/backlog.md`

## ⛔ REPROVADA EM USO REAL — 2026-08-28

Implementada, testada (40 testes verdes) e **revertida no mesmo dia**. O patch
está em `scratchpad/d1-dado-prometido.patch`; não reimplemente sem ler o que
segue.

**O que quebrou:** no Slack, o ditado deixou de colar. Nada. O app reportava
sucesso — transcrevia, postava o ⌘V e logava `.inserted` —, enquanto a caixa de
texto ficava vazia.

**Por quê:** o Slack lê o pasteboard em **várias etapas**. A primeira etapa
dispara o data provider, a devolução acontece no turno seguinte e faz
`clearContents()`, e as etapas restantes encontram um pasteboard vazio.

**O ponto cego que deixou passar:** a ferramenta de medição promovia **um tipo
só**, então via a primeira leitura e parava. A própria spec registrava esse
limite em Anti-escopo — *"o provider dispara uma vez por item armado; leitura
repetida é invisível para nós"* — e concluiu que não valia tratar. Era ali que o
defeito morava. **Limite de instrumento não é detalhe: é onde o bug se esconde.**

**Por que não dá para consertar afinando um número:** para saber que a colagem
foi consumida, o dado precisa ser preguiçoso; dado preguiçoso quebra qualquer app
que leia em mais de uma etapa. Medir o Slack e escolher uma margem seria afinar
para *um* app — o mesmo chute de antes, com um passo a mais. E a premissa do
produto é "funciona onde o cursor estiver", não "funciona nos apps que eu testei".

**O que sobra para o D1:** a devolução continua sendo por tempo. O que muda é
que agora se sabe que **não existe sinal de "colagem consumida" sem quebrar
compatibilidade** — então a discussão passa a ser sobre qual tempo, e sobre o que
se troca entre janela de sequestro do clipboard e segurança. Direção nova exige
`/vibeflow:gen-spec` do zero.

---


## Objetivo

O NeverType devolve a área de transferência quando a colagem é de fato consumida,
em vez de esperar 0,6 s e torcer.

## Contexto

`TextInjector.restoreDelay = 0.6` nunca foi medido — o comentário no código
admite: *"generoso de propósito"*. Se o app de destino ler o pasteboard depois
disso, o NeverType devolve o conteúdo antigo antes da leitura e a pessoa **cola o
que tinha copiado antes, dentro do documento dela**. É o único defeito do backlog
que causa dano em vez de incômodo.

**Medido em 2026-08-28** (ferramenta em `scratchpad/medir-leitura`): um
`NSPasteboardItem` com dado **prometido** (`NSPasteboardItemDataProvider`) faz o
macOS chamar `provideDataForType` no instante exato em que alguém pede o dado.
Quem avisa a hora da leitura é o sistema — sinal estrutural, não cronômetro.
Disparou nos dois apps que este usuário realmente usa:

| app | provider disparou |
|---|---|
| Slack | sim (`leitura #1 · Slack`) |
| Warp / terminal | sim (`leitura #1 · Warp`) |

O caminho está vivo. O que a medição **não** deu foi latência: o delta em ms
inclui tempo de reação humana e não serve para nada. Isso é o que decide a
Decisão 2 abaixo.

## Definition of Done

1. **Leitura dispara a devolução antes do teto.** Teste novo em
   `Tests/NeverTypeCoreTests/TextInjectorTests.swift`: insere num pasteboard
   nomeado de teste, **lê a string** (o que chama o provider, igual a uma
   colagem real), e verifica que o conteúdo anterior voltou **em menos que o
   teto** — não em `teto + margem`.

2. **Sem leitura nenhuma, a devolução acontece no teto.** Teste novo: insere,
   não lê, e verifica que o conteúdo anterior voltou depois do teto. É o caminho
   do ⌘V que não chega em campo editável.

3. **`swift test` verde**, com os 12 testes existentes de `TextInjector`
   passando sem alteração de comportamento: geração, `changeCount`, entrada
   segura, tipos que não são texto, dois ditados seguidos.

4. **O teto subiu, e o comentário diz por quê.** Com a devolução virando evento
   observado, um teto curto deixou de ser proteção e virou o próprio bug
   (Decisão 2). O novo valor está no código com a justificativa e o número.

5. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md`. Em
   particular: **nenhum `MainActor.assumeIsolated` no callback do provider** — a
   API não documenta entrega na main thread, e essa afirmação já derrubou este
   processo duas vezes. Nenhum `try?`, nenhum XCTest, nenhuma chamada de rede.

6. **Verificado por efeito, fora do teste.** Ditar de verdade no Slack e no
   terminal com algo conhecido na área de transferência antes, e conferir as
   duas coisas: o ditado entrou certo, e o conteúdo anterior voltou.

## Escopo

- `Sources/NeverTypeCore/TextInjector.swift` — `.string` passa a ser dado
  prometido no caminho de inserção; a devolução é disparada pelo provider, com o
  tempo como teto.
- `Tests/NeverTypeCoreTests/TextInjectorTests.swift` — os dois testes novos e o
  ajuste dos existentes que citam `restoreDelay`.

Dois arquivos. Bem dentro do orçamento.

## Anti-escopo

- **Não** mexer no caminho de `blockedBySecureInput`. Lá o texto fica no
  pasteboard **de propósito**, para a pessoa colar quando quiser, e não há
  devolução agendada. Prometer dado ali não traz benefício e cria um provider
  vivo por tempo indeterminado. Continua concreto.
- **Não** resolver o D2 (⌘V postado às cegas). São defeitos vizinhos e a
  tentação é grande, mas D2 exige consultar a API de Acessibilidade e é outra
  spec.
- **Não** tentar identificar *quem* leu o pasteboard. `frontmostApplication`
  serviu na ferramenta de medição; em produção é palpite disfarçado de dado.
- **Não** contar leituras nem tratar leitura repetida. Medido: o provider dispara
  uma vez por item armado; leitura repetida vem do cache do `NSPasteboardItem` e
  é invisível para nós. Fingir que tratamos seria pior que não tratar.
- **Não** remover `restoreDelay` da API pública sem substituto — os testes
  existentes dependem dele para saber quanto esperar.

## Decisões técnicas

### 1. Dado prometido só no caminho que tem devolução

`item.setDataProvider(self, forTypes: [.string])` em vez de
`item.setString(text, forType: .string)`, **apenas** no caminho normal de
inserção. O marcador `concealed` continua sendo dado concreto: ele existe para
ser lido por gestores de clipboard antes de decidirem se leem o resto, e
prometê-lo criaria exatamente o disparo falso que queremos evitar.

Isso também é o que faz o marcador virar a defesa contra sinal falso: ler
`types` **não** chama o provider; só pedir o dado de `.string` chama. Um gestor
bem-comportado vê o `concealed` e não pede.

### 2. O teto SOBE, não desce

A conclusão contraintuitiva desta spec, e a razão de ela existir.

Hoje `0.6` é **mecanismo e teto ao mesmo tempo**, e é por isso que é perigoso:
num app que lê em 2 s, o timer devolve primeiro e a pessoa cola o texto errado.
Quando a devolução passa a ser disparada pela leitura, o tempo deixa de ser o
mecanismo e vira **só a saída para o caso em que ninguém leu**.

E nesse caso um teto generoso não custa quase nada: se ninguém leu, não há
colagem para corromper — o único efeito é a área de transferência da pessoa
segurar o ditado por mais alguns segundos, com o `concealed` já impedindo que
isso entre em histórico de clipboard, e com o texto alcançável pelo menu.

Portanto: **teto de 5 s**, e renomeado para dizer o que é
(`restoreCeiling`, mantendo `restoreDelay` como alias enquanto os testes
existentes o citam).

> **TODO / suposição:** 5 s é escolhido por ser folgado o bastante para qualquer
> app plausível, não por medição — a medição feita não isola a latência real de
> leitura. Se incomodar na prática, o número muda com evidência, não com
> opinião.

### 3. A devolução acontece no turno seguinte, nunca dentro do provider

O provider é chamado **durante** a leitura de quem está colando. Mexer no
pasteboard ali dentro é alterar a estrutura que está sendo lida. A devolução é
agendada com `DispatchQueue.main.async` a partir do provider.

E **nada de `MainActor.assumeIsolated`**: a Apple não documenta em que thread
`provideDataForType` chega. Esta é literalmente a armadilha que derrubou o
processo duas vezes neste projeto — inclusive na segunda tentativa de conserto,
porque closure escrita dentro de método `@MainActor` herda o isolamento por
inferência. O salto é verificado pelo compilador, não afirmado.

### 4. As três guardas atuais continuam valendo, na mesma ordem

Geração, `changeCount`, e só então `snapshot.restore`. O provider muda **quando**
a devolução é tentada, não **se** ela é permitida. Nenhuma das três some.

### 5. O provider precisa ficar vivo, e mora no `Pending`

`NSPasteboardItem` não garante reter o data provider. Ele entra no
`Pending` — ao lado de `generation` e `snapshot` —, que já é indexado por
`NSPasteboard.Name` e já tem exatamente o ciclo de vida certo: nasce na
inserção, morre na devolução ou no teto.

## Padrões aplicáveis

- **`estado-do-usuario.md`** — o contrato central não muda: o que se toca, se
  devolve, inclusive no caminho de erro. Esta spec **fortalece** o padrão, porque
  troca "devolve depois de um tempo que a gente chutou" por "devolve quando dá
  para saber que é seguro". O anti-pattern registrado lá — *"restauração
  incondicional e agendada"* — perde a metade "agendada".
- **`verificacao-estrutural.md`** — aplicação nova: a evidência de que a colagem
  aconteceu passa a vir de um callback do sistema, em vez de ser inferida da
  passagem do tempo.
- **`nucleo-testavel.md`** — o caminho novo é exercitável sem colagem real: ler
  a string do pasteboard de teste chama o provider, exatamente como um ⌘V.
  Verificado na ferramenta de medição, onde `pbpaste` disparou o callback.
- **`isolamento-tipado.md`** — `Task { @MainActor in }` ou
  `DispatchQueue.main.async` no callback. Nunca `assumeIsolated`.
- **`falha-alta.md`** — se `writeObjects` falhar com o item prometido, o
  `pending` é limpo e o erro sobe, como já acontece hoje.

## Riscos

| Risco | Mitigação |
|---|---|
| **`Snapshot.capture` dispara o nosso próprio provider.** Ele chama `item.data(forType:)` para todos os tipos — num pasteboard que ainda tem o nosso item prometido, isso é um "consumido" falso vindo de nós mesmos. | O código já herda o retrato pendente em vez de recapturar (`pending[key]?.snapshot ?? capture`). A spec exige que essa herança continue sendo a primeira coisa checada, e um teste que insere duas vezes seguidas cobre o caminho. |
| Gestor de clipboard mal-comportado lê o dado e devolve cedo demais. | O marcador `concealed` é dado concreto e visível sem chamar o provider; gestores bem-comportados param aí. Nesta máquina não há nenhum instalado (varredura de 775 processos e 35 apps), mas o app é para ser instalável por outros — risco documentado, não eliminável. |
| O provider nunca dispara em algum app que este usuário ainda não testou. | O teto cobre: o comportamento degrada exatamente para o de hoje, que é o que já existe em produção. Nenhuma regressão possível nesse caminho. |
| Dado prometido muda o que o app de destino cola (formatação, tipo). | DoD 6 exige ditado real no Slack e no terminal, conferindo o texto inserido — não só que "não quebrou". |
| O provider é chamado numa thread de background e o código toca estado `@MainActor`. | Decisão 3: salto verificado pelo compilador. É a armadilha nº 1 do `docs/pitfalls.md` e tem `@MainActor` explícito no `pending`. |

## References

- `Sources/NeverTypeCore/TextInjector.swift` — o arquivo a mudar; `insert` na
  linha 88 e o bloco `pending` acima dela definem o contrato a preservar
- `Tests/NeverTypeCoreTests/TextInjectorTests.swift` — a suíte que define o
  comportamento atual e não pode regredir
- `scratchpad/medir-leitura/main.swift` — a ferramenta que mediu o disparo do
  provider; o controle dela (leitura por `pbpaste`) é o modelo do teste do DoD 1
- `.vibeflow/patterns/estado-do-usuario.md` — o contrato de devolução que esta
  spec fortalece
