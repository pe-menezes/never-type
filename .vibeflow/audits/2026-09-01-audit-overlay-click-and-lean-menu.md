# Auditoria retroativa: clique no overlay e menu enxuto, 2026-09-01

> Branch `feat/overlay-click-and-lean-menu`, HEAD `0933bd7`, PR #5 aberto contra
> `main` em `e74e4f8`. Diff `main...HEAD`: 15 arquivos, 1147 inserções, 145
> remoções.
>
> **Auditoria posterior ao fato.** Esta branch foi implementada sem discover, sem
> gen-spec e sem audit, por briefing escrito à mão. A regra do repositório é não
> abrir PR sem audit, e esta rodada fecha a lacuna depois do PR já estar aberto.
> Nenhuma spec foi criada aqui.
>
> A skill `/vibeflow:audit` carregou nesta sessão. O contrato dela foi seguido,
> com a adaptação descrita em §0.

## Veredito: **PARTIAL**

Critério de cada veredito, declarado antes do resultado:

| Veredito | Condição |
|---|---|
| **PASS** | Todo item do DoD reconstruído implementado **e** verificado; nenhum desvio de pattern em aberto; Critical Gate limpo; suíte verde. |
| **PARTIAL** | Suíte verde, Critical Gate limpo e todo item do DoD implementado, com desvios em aberto que não impedem a função. |
| **FAIL** | Qualquer teste vermelho; ou achado CRITICAL/HIGH do Critical Gate sem override justificado; ou item do DoD sem implementação, ou sem como verificar a partir do contexto disponível. |

O que produz o PARTIAL, em uma linha: **os quatro pedidos estão implementados e a
suíte está verde, e cinco afirmações de "o app não foi rodado para esta mudança"
seguem gravadas no código e no `docs/reference.md` enquanto o próprio PR declara
que a build foi instalada e exercitada à mão.** Uma das duas afirmações está
errada, e a que sobrevive ao merge é a do código.

Nenhum achado é de gravidade que justifique FAIL. Nenhum é do tipo que se
resolve sozinho depois do merge.

---

## 0. A ausência de spec, e o DoD que foi reconstruído

Não existe spec para esta branch, então não existe DoD para comparar. Nada foi
inventado para preencher esse lugar: o que segue é **reconstrução posterior**,
derivada do que foi pedido, e está marcada como tal em cada item. Ela não
existia quando o código foi escrito e não é apresentada como se existisse.

Fontes, na ordem de autoridade que o briefing fixou:

1. Os pedidos do Pedro, em 01/09, nas palavras dele.
2. O corpo do PR #5, que declara o que foi entregue e três limitações conhecidas.
3. `.vibeflow/conventions.md`, `.vibeflow/patterns/`, `.vibeflow/index.md` e
   `docs/pitfalls.md`.

O que a fonte 1 dá é intenção declarada, não contrato binário. Onde a derivação
precisou escolher entre duas leituras, a escolha está registrada no item.

### DoD reconstruído

| # | Checagem derivada | Fonte |
|---|---|---|
| D1 | Um clique sobre o overlay abre o menu que já existe na barra, e o clique convive com o arrasto do círculo sem que um vire o outro. | *"tem alguma forma de se eu clicar em cima do overlay abrir as configurações lá em cima?"* |
| D2 | O menu deixa de abrir com as linhas de texto cinza que não recebem clique, quando não há nada errado para relatar. | Diagnóstico *"seis das doze linhas são texto cinza"*, aprovado pelo Pedro como corte |
| D3 | O menu mostra que a trava de mãos-livres existe, para quem nunca descobriu o duplo toque. | *"seria legal mostrar a opção de dar lock também, pra pessoa saber"* |
| D4 | O menu instrui quais são as hotkeys, e alcança quem não percebeu que dá para clicar no ícone da barra. | *"queria usar também para instruir a pessoa quais são as hotkeys e tal, porque nem todo mundo vê que pode clicar lá em cima"* |
| D5 | Regra nova entra em `NeverTypeCore`, separada do AppKit, com teste; isolamento declarado no tipo; nenhuma chamada de rede; docs públicos acompanham a mudança nos dois idiomas. | `conventions.md`, `patterns/`, `CLAUDE.md` |

Sobre D3, a leitura escolhida: o pedido é de **discoverability**, mostrar que a
trava existe. Ele não pede um interruptor para desligar a trava. A entrega inclui
o interruptor. Isso está tratado em §2 como anti-escopo, e não como falha de D3.

---

## 1. Cobertura

### DoD Checklist

- [x] **D1: clique no orb abre o menu, sem atropelar o arrasto.**
  `PillView.mouseUp` (`Sources/NeverType/RecordingOverlay.swift:369`) lê o
  desfecho de `PointerGesture` e chama `onClick` ou `onDragEnd`. A regra que
  separa os dois é `PointerGesture` (`Sources/NeverTypeCore/PointerGesture.swift`),
  com raio de 3 px comparado ao quadrado, radial e não por eixo, e com trava:
  passou do slop, continua drag até soltar, ainda que o ponteiro volte à origem.
  O menu é aberto por `presentMenu()` (`RecordingOverlay.swift:521`), com
  `popUp(positioning:at:in:)`, decisão justificada pelo caso de tela cheia
  (`docs/pitfalls.md`, "In full screen there is no menu bar"). O objeto é o
  mesmo `NSMenu` da barra (`main.swift:248`), então não há duas árvores para
  manter em passo. Sete testes em `PointerGestureTests`, incluindo a fronteira
  exata e a volta à origem.

- [x] **D2: o menu perdeu o texto cinza.**
  `MenuLayout.rows(for:)` (`Sources/NeverTypeCore/MenuLayout.swift:102`) decide
  as linhas. No estado em que tudo funciona, a lista é sete itens clicáveis e
  dois separadores, sem uma única linha morta. O teste `theDefaultMenu`
  (`MenuLayoutTests.swift:40`) compara a lista inteira por igualdade, na ordem, e
  ainda varre uma lista nomeada de sete linhas não clicáveis para garantir que
  nenhuma delas apareceu. Igualdade de lista ordenada é a verificação certa aqui:
  o pedido era sobre ordem e volume, e uma busca por ausência provaria menos.

- [x] **D3: a trava aparece no menu.**
  O item `Hands-free: double tap` (`main.swift:722`) carrega o gesto no próprio
  título, e o submenu (`handsFreeMenu`, `main.swift:801`) traz o ciclo inteiro em
  três linhas. Com a trava desligada o título passa a `Hands-free: off` e o
  submenu guarda uma linha só. Coberto por `handsFreeOff` e
  `theGestureSummaryFollowsHandsFree`.

- [x] **D4: o menu instrui as hotkeys, e alcança quem não clicou.**
  Três canais, e o doc de `MenuLayout.swift:10-15` declara os três de propósito:
  (a) os títulos `Hotkey: Right ⌘` e `Hands-free: double tap`, que ensinam o
  gesto a quem abriu o menu para outra coisa; (b) o ciclo completo dentro dos dois
  submenus; (c) o tooltip no ícone e no orb (`hoverHint`, `main.swift:535`), que
  é o único canal que fala com quem nunca clicou em nada.
  **O canal (c) não foi verificado**, e é o único que responde à segunda metade
  do pedido, *"nem todo mundo vê que pode clicar lá em cima"*. Detalhe em §5 e na
  lacuna L2. Marcado como atendido porque (a) e (b) cobrem o pedido sozinhos, e o
  canal que falta é reforço.

- [x] **D5: convenções estruturais.**
  Duas regras puras saíram do AppKit para `NeverTypeCore` e ganharam teste.
  Isolamento declarado no tipo em todos os tipos novos e alterados. Zero chamada
  de rede no diff (§4). `README.md` e `README.pt-BR.md` mudaram juntos, e
  `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md` também.

**Nada ficou pela metade e nada foi entregue como outra coisa.** O que existe a
mais está em §2.

---

## 2. Anti-escopo

Mudança não pedida não é automaticamente errada. Cada uma está nomeada, com o
que a motivou e como foi declarada.

### 2.1 O interruptor de mãos-livres (o item grande)

O pedido era mostrar que a trava existe. A entrega inclui **desligar a trava**,
com superfície própria:

| Peça | Local |
|---|---|
| Preferência nova no `UserDefaults`, chave `handsFree` | `main.swift:520`, `main.swift:527` |
| Parâmetro no construtor de `Latch`, com a guarda na transição | `HotkeyMonitor.swift:81-85`, `HotkeyMonitor.swift:113` |
| Propriedade mutável com `didSet` que reconstrói a máquina | `HotkeyMonitor.swift:212-224` |
| Ação de menu | `toggleHandsFree`, `main.swift:571` |
| Encerramento da gravação órfã | `endOrphanRecording`, `main.swift:448` |
| Ramo no layout do menu | `MenuLayout.swift:122` |
| 4 dos 23 testes novos | `AudioRecorderTests.swift:487,501`; `MenuLayoutTests.swift:184,201` |
| Parágrafo em `docs/reference.md` | `docs/reference.md:20-25` |

É um recurso coerente, bem construído e documentado nos dois lugares. Ele não foi
pedido. A justificativa está escrita em `HotkeyMonitor.swift:214` ("Somebody who
locks by accident needs a way out of the mode") e é razoável. Fica nomeado porque
é a maior parte do custo desta branch fora do pedido, e porque cria uma
preferência permanente, com migração implícita para todo mundo que já usa o app.

### 2.2 O `Quit NeverType` com seletor próprio

`main.swift:767-773`. Trocar `NSApplication.terminate(_:)` por `quitNeverType()`
para tirar o glifo que o macOS 26 desenha ao lado do comando padrão. Defeito
achado no caminho, declarado no PR. Não pedido, e consequência direta do print
que originou o pedido D2.

### 2.3 O cursor deixou de ser a mão aberta

`RecordingOverlay.swift:325-334`. Antes, mão aberta em repouso e mão fechada
durante o arrasto. Agora, seta em repouso e mão fechada só quando o orb está de
fato se movendo. O comentário justifica: uma mão promete uma coisa, arrastar, e o
orb passou a fazer duas. É consequência de D1 e é uma escolha de gosto. O efeito
colateral: em repouso o orb não anuncia mais nem que arrasta nem que clica, e o
tooltip do canal (c) passou a ser o único aviso de que ali existe um botão. Isso
liga 2.3 à lacuna L2.

### 2.4 A troca de nível de janela

`RecordingOverlay.swift:423,433,436-437` e `main.swift:936-943`. Consequência
necessária de D1: o painel repousa em `.screenSaver` (1000) e o AppKit desenha
menu em `.popUpMenu` (101), então o menu sairia por baixo do orb. **Em escopo.**

### 2.5 Refatorações de apoio

`discardRecording` extraído (`main.swift:431`), helper `action(_:_:keyEquivalent:)`
(`main.swift:786`), `hotkeyMenu()` e `historyMenu()` separados. O helper `action`
tem razão registrada e não estética: item sem `target` procura a ação subindo uma
cadeia de responders que começa em outro lugar quando o menu é aberto do painel
não-ativante. **Em escopo, e a razão está no código.**

---

## 3. Conformidade com patterns e conventions

Um a um, com onde.

### `nucleo-testavel.md`: **SEGUE**

Duas regras puras saíram do AppKit e foram para a biblioteca:
`Sources/NeverTypeCore/PointerGesture.swift` e
`Sources/NeverTypeCore/MenuLayout.swift`. As duas citam explicitamente o
precedente do repo (`PasteTarget.decide(_:)`) como o motivo da separação. O
executável ficou com a tradução de `Row` para `NSMenuItem` (`item(for:)`,
`main.swift:695`), que é texto para uma pessoa e não decisão. `MenuLayout` recebe
`Conditions`, um snapshot de valores, e não as fontes deles, o que é exatamente o
que torna a função comparável num teste. Evidência: 21 dos 23 testes novos batem
nessas duas unidades sem janela, sem mouse e sem relógio.

Limite conhecido do pattern, aplicável aqui: a montagem de `Conditions` em
`rebuildMenu()` (`main.swift:667-686`) é código da casca e não tem teste. Ver §5.

### `isolamento-tipado.md`: **SEGUE**

`RecordingOverlay` e `PillView` são `@MainActor` (`RecordingOverlay.swift:408`,
`:257`). `PointerGesture` é `struct Sendable` sem isolamento, porque não precisa.
`MenuLayout.Conditions` e `MenuLayout.Row` são `Sendable`. **Nenhum
`MainActor.assumeIsolated` foi adicionado**, que é o Don't que já derrubou este
app duas vezes. O único salto novo é `Task { @MainActor in }` em
`presentMenu()` (`RecordingOverlay.swift:527`), que é a forma que o pattern
prescreve, e ali serve para sair do handler de mouse antes do loop de tracking do
menu, com a razão escrita.

### `estado-consultado.md`: **SEGUE, e melhorou**

`rebuildMenu()` continua consultando tudo na hora: `micAuthorized`,
`HotkeyMonitor.hasAccessibilityPermission`, `NSEvent.modifierFlags`,
`history.entries.count`, `loginItemState`. `MenuLayout.Conditions` documenta em
`MenuLayout.swift:22-25` que carrega valores e não as fontes, e que os três
estados externos são relidos a cada `menuNeedsUpdate`. A mudança melhora o
pattern num ponto: as linhas `Microphone: ok` e `Accessibility: ok` sumiram, e
com elas some a possibilidade de exibir um "ok" que envelheceu. Agora o menu só
diz alguma coisa sobre permissão quando ela falta.

Um estado guardado que vale registrar: `hoverHint` é recalculado à mão por
`refreshHoverHint()` (`main.swift:539`), chamado no launch e em `chooseTrigger`.
Ele depende só de `monitor.trigger.label`, e `chooseTrigger` é o único ponto que
muda isso, então está correto hoje. É um acoplamento que uma quarta tecla ou uma
mudança de gatilho por outro caminho quebraria em silêncio. Confiança alta,
gravidade baixa.

### `falha-alta.md`: **DESVIO** (o que produz o PARTIAL)

O pattern diz: *"Todo caminho de falha precisa ser exercitável. Se não dá para
exercitar, ele não conta como implementado."* E o `CLAUDE.md` abre com *"Verifique
o efeito, não a intenção."*

Cinco lugares do artefato final afirmam que o app não foi rodado:

| Local | O que afirma |
|---|---|
| `Sources/NeverType/RecordingOverlay.swift:313` | tooltip no painel não-ativante, "the app was not run for this change" |
| `Sources/NeverType/RecordingOverlay.swift:432` | nível de janela com o menu aberto, "was not watched happening" |
| `Sources/NeverType/main.swift:446` | `endOrphanRecording`, "Not watched happening" |
| `Sources/NeverType/main.swift:772` | o glifo do `Quit`, "the app was not run for this change" |
| `docs/reference.md:133-134` | o tooltip no orb, "the app was not run for this change" |

O corpo do PR #5 declara, na seção Verification: *"the build was installed and
exercised by hand"*. O briefing desta auditoria confirma o mesmo número medido
fora do sandbox.

As duas afirmações não podem estar certas ao mesmo tempo para pelo menos dois
desses cinco lugares. `menuOpenLevel` é atravessado por qualquer clique no orb
que abra o menu, que é o gesto central de D1. E o PR afirma sobre o `Quit`, no
passado e como observação, *"the menu now has no icons at all"*, enquanto a linha
772 diz que ninguém viu. A que sobrevive ao merge é a do código, porque o corpo
do PR ninguém lê depois.

O resto do pattern está atendido: `discardRecording` fala pelo log, o erro de
gravação continua tendo canal até a interface, e o menu ganhou item de saída para
a Acessibilidade que falta.

### `estado-do-usuario.md`: **DESVIO menor, documentado**

Regra do pattern: *"Nada que a pessoa falou é descartado sem que exista outro
caminho até ele."*

`endOrphanRecording` (`main.swift:448`) chama `discardRecording`, que chama
`recorder.cancel()`. O `cancel` apaga o WAV e limpa as amostras da memória, que é
o comportamento testado em `AudioRecorderTests`. Dois caminhos chegam nele:
trocar a tecla e desligar mãos-livres com uma gravação rodando
(`main.swift:566`, `main.swift:574`).

O caminho de mãos-livres é o que preocupa. O próprio comentário diz que ele
existe para quem travou sem querer e foi ao menu procurar a saída. Essa pessoa
pode ter falado antes de chegar lá, e o áudio some sem transcrever. Concluir a
gravação e transcrever estava disponível e não perderia nada.

A mitigação existe e é a que o pattern pede: está declarado em
`docs/reference.md:23-25`. Fica como desvio nomeado, não bloqueante.

### `verificacao-estrutural.md`: **NÃO SE APLICA, e nada foi enfraquecido**

O diff não toca formato binário, checksum, magic number nem enumeração de
backend. Nenhuma verificação estrutural existente foi removida ou trocada por
busca de texto. Os testes novos verificam por igualdade de estrutura
(lista ordenada de `Row`, vetor de deslocamento), que é o análogo do pattern no
domínio deles.

### `scripts-shell.md`: **SEGUE**

`scripts/install.sh` é o único script tocado, e a mudança é texto de duas
mensagens (`install.sh:99-100`, `install.sh:131-133`). Esqueleto, `set -euo
pipefail`, `REPO_ROOT`, funções de saída e idempotência intactos. O briefing
registra `install.sh`, `build-app.sh` e `verify-install.sh` com exit 0.

Vale um registro de coerência: `scripts/verify-install.sh:120` cita
`"Accessibility: missing"` e `"Open Accessibility Settings…"`, e as duas linhas
continuam existindo nesse estado (`MenuLayout.swift:105-108`). O texto do script
segue verdadeiro depois do corte do menu.

### `terceiros-pinados.md`: **NÃO SE APLICA**

Nenhuma dependência tocada.

### Convention Violations

- `Sources/NeverType/RecordingOverlay.swift:333`: *"it appears when the press
  passes the slop **instead of** when the button goes down"*. Don't de
  `conventions.md:128-134`: não trocar travessão por figura de oposição, e
  "instead of" está na lista nominal.
- `Sources/NeverType/main.swift:767`: *"The app's own selector **instead of**
  `terminate:`"*. Mesmo Don't.
- Contexto para calibrar a gravidade: já existem 5 ocorrências de "instead of"
  nos mesmos arquivos antes desta branch (`main.swift:71,198,646,884`,
  `HotkeyMonitor.swift:10`). Esta é dívida sistêmica que a branch faz crescer em
  dois, não uma violação inaugurada aqui.
- `scripts/install.sh:99` tem um travessão em linha adicionada. Ele **já estava
  lá** na linha removida correspondente, dentro de string literal de shell, que é
  uma das exceções escritas na convenção. Os oito scripts têm travessão hoje.
  Informativo, sem ação.
- Nenhuma aspa curva no diff. Nenhum travessão novo em prosa de Swift ou de
  markdown.

---

## 4. Critical Gate

**Limpo. Nenhum achado, de nenhuma gravidade.**

O catálogo de ~40 regras mira `.sql`, `.tf`, `.hcl`, `.yaml`, `.json`, `.toml` e
fontes em Python, JS, TS, Ruby, Go e Java. Este diff é Swift, shell e markdown, e
nenhuma regra do catálogo casa por tipo de arquivo. Então a varredura foi feita
pelos gatilhos que o briefing nomeou, sobre as linhas adicionadas e as removidas
do diff `main...HEAD` inteiro:

| O que foi varrido | Padrão | Resultado |
|---|---|---|
| Remoção ou apagamento de arquivo | `rm`, `rm -`, `removeItem`, `unlink`, `FileManager`, `trash`, `delete`, `truncate` em linhas `+` | **Nenhuma ocorrência** |
| Escrita fora do sandbox do app | `Application Support`, `NSHomeDirectory`, `applicationSupportDirectory` em linhas `+` | **Nenhuma.** As únicas menções são prosa de `docs/INSTALL*.md`, inalteradas quanto ao caminho |
| Dado do usuário em `~/Library/Application Support/NeverType/` | leitura/escrita de `historico.json`, `vocabulario.json`, `last.wav` | **Nenhuma.** O diff não toca `TranscriptHistory` nem `Vocabulary`. `recorder.cancel()` apaga o WAV da gravação em curso, que é comportamento pré-existente e testado, e não caminho novo |
| Mudança de permissão | `chmod`, `chown`, `+x` | **Nenhuma** |
| Assinatura ou keychain | `codesign`, `security `, `keychain` | **Nenhuma.** `scripts/build-app.sh` não foi tocado |
| Chamada de rede | `URLSession`, `NSURLConnection`, `http://`, `https://`, `Network.`, `socket`, `CFNetwork` | **Nenhuma.** A restrição que justifica o projeto está intacta |
| Execução dinâmica | `Process(`, `NSTask`, `system(`, `popen`, `eval`, `exec` | **Nenhuma** |
| Proteção removida | `guard`, `permission`, `authoriz`, `trusted`, `secure`, `verify`, `checksum`, `shasum`, `flock`, `changeCount` em linhas `-` | **5 ocorrências, todas benignas.** Duas são o `guard` de `mouseDragged` e o de `Latch`, reescritos na linha `+` logo abaixo com a condição preservada e ampliada; três são linhas de menu e de README que mudaram de lugar |
| Segredo em literal | `password`, `secret`, `api_key`, `token` com literal | **Nenhuma** |

O que muda no `UserDefaults`: uma chave nova, `handsFree` (`main.swift:520`),
booleana, sem texto. `docs/reference.md:240` foi atualizado de cinco para seis
preferências, e a contagem confere (tecla, mãos-livres, sons, posição do orb,
`clipboardRestoreDelay`, `checkFocusBeforePaste`).

Nenhum override `vibeflow:allow` foi necessário, e nenhum está presente no diff.

---

## 5. Testes

Números medidos fora do sandbox, usados como dado e não refeitos: build limpo
após `rm -rf .build` com exit 0; 4 fingerprints de warning em debug e em release,
com teto de CI em 4; `swift test --disable-xctest --enable-swift-testing` com
**132 testes em 16 suítes**, contra 109 antes. Nenhum teste vermelho, então a
regra "teste vermelho é FAIL" não dispara.

### Provam a regra ou provam o mock?

**Provam a regra.** Não existe mock em nenhum dos 23. As três unidades recebem
dado puro e devolvem valor comparável:

- `PointerGestureTests` (7) passa coordenadas como dado. Sem janela, sem mouse,
  sem relógio, e o doc do arquivo declara isso na primeira linha.
- `MenuLayoutTests` (14) passa `Conditions` como dado e compara listas inteiras
  na ordem. `theDefaultMenu`, `optionShowsTheDiagnostics`, `microphoneMissing`,
  `nothingTranscribedYet` e `handsFreeOff` usam igualdade da lista completa, que
  é a asserção forte. Ordem é metade do que o pedido D2 tratava, e a igualdade
  ordenada é o que prova ordem.
- Os 2 testes novos de `LatchTests` passam timestamps como argumento
  (`.down(0)`, `.up(0.05)`), que é relógio injetado e não relógio real.

### Fragilidade

**Nenhum dos 23 é frágil.** Varrido especificamente: nenhum lê relógio de
parede, nenhum abre janela, nenhum move mouse, nenhum depende de ordem entre
testes, nenhum toca recurso compartilhado. `theBoundaryItself` usa
`defaultSlop - 0.1`, que dá 2,9 e 8,41 contra 9 no quadrado, longe de qualquer
fronteira de ponto flutuante.

### Ramos de decisão sem teste

Em ordem de quanto importa:

1. **A montagem de `Conditions` em `rebuildMenu()` (`main.swift:667-686`) não tem
   teste, e não pode ter.** Trocar `microphoneAuthorized:` por
   `accessibilityAuthorized:` no ponto de chamada deixa os 14 testes de
   `MenuLayoutTests` verdes. É o limite conhecido de `nucleo-testavel`, e o repo
   já convive com ele em todo o `Sources/NeverType/`. Informativo, sem ação.
2. **`HotkeyMonitor.handsFreeEnabled` e seu `didSet` não têm teste**
   (`HotkeyMonitor.swift:212-224`). `grep 'HotkeyMonitor('` em `Tests/` não
   retorna nada: a classe nunca é instanciada na suíte, porque é `@MainActor` e
   instala monitores do `NSEvent`. A `Latch` interna é testada, o
   `resetGesture()` que a reconstrói não. É a mesma forma do `didSet` de
   `trigger`, que já era não testado. Dívida pré-existente que ganhou um segundo
   caso.
3. **Falta a combinação "permissão faltando com Option segurado" por igualdade de
   lista.** `aMissingPermissionDoesNotBringTheDiagnosticsBack` testa Accessibility
   faltando com Option desligado. `quitIsAlwaysLast` monta o estado máximo
   (as duas permissões faltando, Option, 30 no histórico, login item pendente) e
   afirma um elemento só, o último. A ordem completa do estado mais cheio do menu
   não é comparada em lugar nenhum.
4. **`PointerGesture.init(origin:slop:)` nunca é chamado com slop customizado.**
   O parâmetro existe e só o padrão é exercitado. Baixo.

---

## 6. As três limitações declaradas no PR

Todas as três estão no código **e** no `docs/reference.md`. Este item passa.

| Limitação | No código | Em `docs/reference.md` |
|---|---|---|
| Option lido uma vez, na construção do menu | `main.swift:672-682`, com o motivo e a alternativa descartada (`isAlternate` com par visível para cada linha escondida) | `:180-182`, "The key is read once, at the moment the menu is built. Holding Option after the menu is already on screen changes nothing" |
| Menu virando na borda da tela | `RecordingOverlay.swift:507-518`, no doc de `presentMenu()` | `:50-56`, "Near an edge of the screen (…) macOS flips the menu to whichever side fits" |
| Tooltip em `NSPanel` não-ativante | `RecordingOverlay.swift:305-316`, no doc de `updateTrackingAreas()` | `:121-134`, seção "The tooltip" inteira |

O `install.sh` e o `docs/launch-at-login.md` também foram atualizados para dizer
que `Model:` e `Version:` agora pedem Option, o que fecha o efeito colateral do
corte de D2 sobre docs que citavam essas linhas. Conferido: nenhum outro doc ou
script ficou apontando para uma linha de menu que deixou de existir sem condição.

Uma ressalva sobre a terceira. O texto de `reference.md:133-134` documenta a
limitação **e** afirma que o app não foi rodado. Documentar a dúvida é o
comportamento certo. Manter a afirmação depois de rodar o app é o achado do §3.

---

## 7. Dívida deixada

- **`docs/pitfalls.md` não foi tocado.** Esta branch produziu três defeitos com
  causa nomeada e nenhum entrou lá: a inversão de nível de janela
  (`.screenSaver` 1000 contra `.popUpMenu` 101), o glifo que o macOS 26 desenha
  ao lado de `terminate:`, e o `NSTrackingArea` construído com `userData:`. Os
  três estão só no corpo do PR. `CLAUDE.md` chama `docs/pitfalls.md` de leitura
  obrigatória antes de escrever código, e a seção "macOS: things that vanish
  without an error" é onde os dois primeiros pertencem por assunto. O PR some do
  caminho depois do merge, e o `pitfalls.md` não.
- **`.vibeflow/index.md` desatualizado em dois pontos.** A linha 31 diz
  "109 testes em swift-testing", e são 132 em 16 suítes. A linha 87 descreve
  `HotkeyMonitor.swift` sem mencionar que a trava agora pode ser desligada. A
  seção "Known Issues / Tech Debt" não registra nada desta branch.
- **`.vibeflow/backlog.md` e `.vibeflow/decisions.md` não foram alimentados.**
  Esta auditoria não escreveu neles, por restrição do briefing. Os itens que
  caberiam ali estão na lista de lacunas abaixo.
- **Sem spec e sem PRD para uma branch com 1147 linhas.** É a lacuna de processo
  que esta rodada fecha por fora. O DoD do §0 é reconstrução e não substitui um
  contrato escrito antes.
- **`hoverHint` acoplado a `chooseTrigger`** (§3, `estado-consultado`). Uma quarta
  tecla ou um segundo caminho de troca de gatilho deixaria o tooltip mentindo
  em silêncio.
- Nada foi quebrado em outro lugar do repo. Nenhuma API pública de
  `NeverTypeCore` mudou de assinatura; `Latch.init` e `HotkeyMonitor.init`
  ganharam parâmetro com valor padrão, o que preserva as chamadas existentes.

---

## 8. O erro de compilação, e o que ele indica

`NSTrackingArea` foi escrito com `userData:`, o rótulo do Objective-C, onde o
Swift toma `userInfo:`. Chegou na branch e foi consertado antes do PR.

O que ele indica, com evidência: **a superfície AppKit desta mudança foi escrita
sem compilar, e é exatamente a superfície que os quatro comentários de "o app não
foi rodado" cobrem.** As duas coisas apontam para a mesma fronteira. O erro caiu
em `updateTrackingAreas()`, a mesma função cujo doc declara que ninguém viu o
efeito. `menuOpenLevel`, `endOrphanRecording` e o seletor do `Quit` estão do
mesmo lado.

O que ele **não** indica: nada sobre o núcleo. `PointerGesture` e `MenuLayout`
compilam, têm 21 testes e não carregam nenhuma afirmação não verificada. A
separação que o `nucleo-testavel` prescreve funcionou aqui como blindagem, e o
erro caiu do lado que o pattern já sabe que não protege.

A conclusão operacional é a lacuna L2: o compilador pegou o `userData:`, e nada
neste fluxo pega o tooltip que não aparece. Só rodar pega.

---

## Lacunas, em ordem de gravidade

### L1. Cinco afirmações de "o app não foi rodado" contra a verificação do próprio PR

**Bloqueante para o merge.**

`Sources/NeverType/RecordingOverlay.swift:313` · `RecordingOverlay.swift:432` ·
`Sources/NeverType/main.swift:446` · `main.swift:772` · `docs/reference.md:133`

O que falta: decidir qual das duas afirmações é a verdadeira, para cada um dos
cinco lugares, e deixar no artefato a que ficou. Para `menuOpenLevel` e para o
glifo do `Quit`, o exercício à mão que o PR declara já responde. Para
`endOrphanRecording` e para o tooltip, ou o caminho foi exercitado e o comentário
sai, ou não foi e o comentário fica como está, correto.

Por que bloqueia: é a regra de abertura do `CLAUDE.md` e é o pattern
`falha-alta`. O custo de deixar passar é um leitor futuro tratando como não
verificado algo que foi, ou o contrário, e este repositório tem quatro auditorias
mostrando que essa confusão custa caro.

Esforço: **S**. São cinco comentários.

### L2. O tooltip no orb entrega o canal (c) de D4 sem verificação

**Bloqueante para o merge, ou backlog explícito se o Pedro decidir que é reforço.**

`Sources/NeverType/RecordingOverlay.swift:305-322` · `main.swift:535`

O que falta: parar o ponteiro sobre o orb por dois segundos, com o NeverType
inativo, e olhar. O `falha-alta` diz que caminho que não dá para exercitar não
conta como implementado, e este dá: a build está instalada.

Uma dúvida técnica que reforça a checagem, e que eu não tenho como resolver sem
rodar: `NSView.toolTip` instala tracking próprio do AppKit, e a `NSTrackingArea`
adicionada aqui tem `owner: self` numa view que não implementa `mouseEntered`
nem `mouseMoved`. Não é evidente que a área adicionada seja o que alimenta o
timer do tooltip. `panel.acceptsMouseMovedEvents = true`
(`RecordingOverlay.swift:492`) é a parte que plausivelmente importa. Se o
tooltip não aparecer, o conserto fica com a lacuna, não com a verificação.

Ligação com 2.3: o cursor virou seta em repouso, então o tooltip passou a ser o
único aviso de que o orb recebe clique.

Esforço: **S** para verificar. **M** se não funcionar.

### L3. `docs/pitfalls.md` não recebeu os três defeitos desta branch

**Backlog, com data.**

O que falta: três entradas curtas em `docs/pitfalls.md`, seção "macOS: things
that vanish without an error" para as duas primeiras:

1. Um `NSPanel` em `.screenSaver` (1000) fica acima do menu que o AppKit desenha
   em `.popUpMenu` (101). O número medido é a diferença dos dois níveis, e a saída
   é `.statusBar` (25) enquanto o menu está aberto.
2. O macOS 26 reconhece `terminate:` como comando padrão e desenha glifo próprio
   ao lado. Um menu com um ícone só parece um menu faltando quinze.
3. `NSTrackingArea` toma `userInfo:` no Swift, e `userData:` é o rótulo do
   Objective-C.

Por que importa: o `CLAUDE.md` manda ler `docs/pitfalls.md` antes de escrever
código e diz que o quarto item não é opcional. O corpo do PR não é lido depois do
merge.

Esforço: **S**.

### L4. O interruptor de mãos-livres é anti-escopo sem registro nos artefatos do repo

**Backlog.**

Está declarado no PR e no `docs/reference.md`. Não está em `.vibeflow/`. Um
recurso permanente, com preferência nova no `UserDefaults`, que ninguém pediu,
merece uma linha em `.vibeflow/decisions.md` dizendo por que entrou. Ver §2.1
para a lista de peças.

Esforço: **S**.

### L5. Desligar mãos-livres durante uma gravação joga o áudio fora

**Backlog.**

`Sources/NeverType/main.swift:448` e `:574`

Concluir e transcrever estava disponível e não perderia nada. O comportamento
atual está documentado em `docs/reference.md:23-25`, que é a mitigação que o
`estado-do-usuario` pede, então não bloqueia. Vale como item de uso real, junto
com D1 e D2 do backlog que já esperam a mesma coisa.

Esforço: **S** para trocar por concluir. **M** com teste.

### L6. Duas figuras de oposição novas

**Backlog, dentro de uma varredura maior.**

`Sources/NeverType/RecordingOverlay.swift:333` · `main.swift:767`

Dois "instead of" novos, sobre 5 pré-existentes nos mesmos arquivos. Consertar só
os dois desta branch deixa o arquivo inconsistente consigo mesmo. Cabe numa
varredura de `Sources/` inteiro, que é trabalho de outra rodada.

Esforço: **S** isolado. **M** como varredura.

### L7. Buracos de teste

**Backlog.**

Em ordem: a combinação "permissão faltando com Option segurado" sem igualdade de
lista completa (`MenuLayoutTests`); `HotkeyMonitor.handsFreeEnabled.didSet` sem
teste, porque a classe não é instanciável na suíte; `PointerGesture` com slop
customizado nunca exercitado. Detalhe em §5.

Esforço: **S** para o primeiro. **L** para o segundo, que pede extrair o
`resetGesture` para onde um teste alcance.

### L8. `.vibeflow/index.md` desatualizado

**Backlog.**

Linha 31, "109 testes", agora 132 em 16 suítes. Linha 87, a descrição de
`HotkeyMonitor.swift`, sem a trava desligável.

Esforço: **S**.

---

## Incremental Prompt Pack

Cobre só as lacunas. Não repete o que já passou.

### Bloco 1. L1 e L2, antes do merge

> As cinco afirmações de "o app não foi rodado para esta mudança" em
> `Sources/NeverType/RecordingOverlay.swift:313`, `RecordingOverlay.swift:432`,
> `Sources/NeverType/main.swift:446`, `main.swift:772` e `docs/reference.md:133`
> contradizem a seção Verification do PR #5, que declara a build instalada e
> exercitada à mão.
>
> Para cada um dos cinco, decida qual das duas afirmações é verdadeira e deixe no
> arquivo a que ficou. Dois deles o exercício à mão já responde: abrir o menu
> pelo orb atravessa `menuOpenLevel`, e o glifo do `Quit` o PR descreve como
> observado ("the menu now has no icons at all").
>
> Antes de mexer no comentário do tooltip, exercite o caminho: com o NeverType
> inativo, pare o ponteiro sobre o orb por dois segundos e olhe se o texto
> `NeverType. Hold Right ⌘ to dictate. Click for the menu.` aparece. Se não
> aparecer, o achado é o tooltip e não o comentário. Uma pista para esse caso:
> `NSView.toolTip` instala tracking próprio, e a `NSTrackingArea` de
> `updateTrackingAreas()` tem `owner: self` numa view que não implementa
> `mouseEntered` nem `mouseMoved`.
>
> Pattern que rege isto, `falha-alta.md`: *"Todo caminho de falha precisa ser
> exercitável. Se não dá para exercitar, ele não conta como implementado."* E a
> regra de abertura do `CLAUDE.md`: *"Verifique o efeito, não a intenção.
> Procurar uma palavra num log não prova que algo aconteceu."*
>
> Convenção de comentário deste repo: o comentário registra a decisão e o custo
> do erro, sempre com o número medido quando existe. Ele não explica o que o
> código faz.

### Bloco 2. L3, três entradas em `docs/pitfalls.md`

> Adicione três entradas em `docs/pitfalls.md`, as duas primeiras na seção
> "macOS: things that vanish without an error", cada uma no formato das que já
> estão lá: título em `###` dizendo a regra, o que quebrou, e o número medido.
>
> 1. Um `NSPanel` em `.screenSaver` fica acima do menu. `.screenSaver` é 1000 e o
>    AppKit desenha menu em `.popUpMenu`, que é 101, então o menu sai por baixo
>    do painel. A saída é descer para `.statusBar`, 25, enquanto o menu está
>    aberto, que continua acima da janela do app da frente e de uma em tela
>    cheia. Onde está: `Sources/NeverType/RecordingOverlay.swift:423-437`.
> 2. O macOS 26 reconhece `terminate:` como o comando Quit padrão e desenha um
>    glifo ao lado. Era o único ícone do menu inteiro. Rotear por um seletor do
>    próprio app não deixa comando padrão para o AppKit reconhecer. Onde está:
>    `Sources/NeverType/main.swift:766-773`.
> 3. `NSTrackingArea` toma `userInfo:` no Swift. `userData:` é o rótulo do
>    Objective-C e não compila. Custo: um erro de compilação que chegou na branch
>    `feat/overlay-click-and-lean-menu` e foi consertado antes do PR #5.
>
> Não invente número que não foi medido. Os níveis de janela são constantes
> públicas do AppKit e podem ser citados como estão.

### Bloco 3. L4, L5 e L8, registro em `.vibeflow/`

> Três registros, todos em português, que é o idioma de `.vibeflow/`:
>
> 1. `.vibeflow/decisions.md`: o interruptor de mãos-livres entrou nesta branch
>    sem ter sido pedido. O pedido era mostrar que a trava existe. Registre a
>    decisão, o que ela custou em superfície (chave `handsFree` no
>    `UserDefaults`, parâmetro em `Latch`, `didSet` que reconstrói a máquina,
>    `toggleHandsFree`, `endOrphanRecording`, ramo em `MenuLayout`, 4 testes,
>    parágrafo em `docs/reference.md`) e a razão escrita em
>    `Sources/NeverTypeCore/HotkeyMonitor.swift:214`.
> 2. `.vibeflow/backlog.md`: desligar mãos-livres com uma gravação rodando
>    descarta o áudio (`Sources/NeverType/main.swift:448` e `:574`). Concluir e
>    transcrever estava disponível. O `estado-do-usuario.md` pede que nada do que
>    a pessoa falou seja descartado sem outro caminho até ele. O comportamento
>    está documentado em `docs/reference.md:23-25`, e o item é de uso real.
> 3. `.vibeflow/index.md`: a linha 31 diz "109 testes em swift-testing" e são 132
>    em 16 suítes; a linha 87 descreve `HotkeyMonitor.swift` sem a trava
>    desligável. As duas ficam dentro dos marcadores `vibeflow:auto`, então
>    ajuste com cuidado para a próxima rodada de `analyze` não desfazer.

### Bloco 4. L7, o buraco de teste que vale fechar agora

> Em `Tests/NeverTypeCoreTests/MenuLayoutTests.swift`, falta a combinação de
> permissão faltando com Option segurado por igualdade da lista inteira. Hoje
> `aMissingPermissionDoesNotBringTheDiagnosticsBack` testa Accessibility faltando
> com Option desligado, e `quitIsAlwaysLast` monta o estado máximo e afirma um
> elemento só.
>
> Adicione um teste que compare a lista completa, na ordem, para
> `conditions(microphone: false, accessibility: false, option: true, history: 30,
> startsAtLogin: true, needsApproval: true)`. Siga a forma dos que já estão lá:
> igualdade contra o array literal inteiro, e doc comment dizendo qual decisão o
> teste protege.
>
> Convenções que valem: swift-testing com `import Testing`, nunca XCTest. Nome do
> teste é uma frase em inglês descrevendo o comportamento. `#expect` com mensagem
> dizendo o que se esperava e o que veio.
>
> Não mexa nos 23 testes existentes. Eles provam a regra, não usam mock, e não
> leem relógio, janela nem mouse.

---

## Próximo passo

Feche L1 e L2, que são S e ficam no caminho do merge. L3 a L8 viram backlog.
Depois, `/vibeflow:audit` de novo sobre a mesma branch.

Registro de método: esta auditoria não rodou `swift build` nem `swift test`. O
sandbox não roda `swift`, e os números do §5 são os medidos fora dele e
declarados no briefing. Nenhum arquivo foi consertado, por restrição da rodada.
O único arquivo escrito foi este.
