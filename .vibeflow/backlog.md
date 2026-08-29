# Backlog — NeverType

> Montado em 2026-08-28. Fonte de verdade; a versão publicada é só leitura.
> Cada item tem a evidência de onde saiu. Item sem evidência não entra aqui.

## Como está ordenado

Primeiro o que **estraga o trabalho de alguém**, depois o que **muda como o app
se sente na mão**, depois o que **deixa outra pessoa usar**, depois polimento.
Não é ordem de esforço — é ordem de dano.

Tamanhos: **P** cabe no orçamento de ≤4 arquivos · **G** cria subsistema e
precisa de spec própria (ou dividida).

---

## Feito, aguardando você

### ✅ F1 · Abrir com o sistema
Implementado nesta sessão. `LoginItem.swift`, item no menu, 9 testes novos.
Registrado e confirmado pelo macOS na tua máquina.

**Falta:** reiniciar e conferir que o ícone volta sozinho, e ler a linha
`Modelo:` no menu para fechar a medição de boot frio.
Spec: `.vibeflow/specs/abrir-com-o-sistema.md`

---

## 1. Defeitos que podem estragar o trabalho de alguém

Estes quatro são os únicos itens do backlog que causam **dano ao usuário**, não
apenas incômodo. Por isso vêm antes de tudo, inclusive do streaming.

### D1 · A devolução do clipboard é um chute de 0,6 s — P
`TextInjector.restoreDelay = 0.6` nunca foi medido. O comentário no código
admite: *"generoso de propósito"*. Se o app de destino ler o pasteboard depois
disso, ele cola **o conteúdo antigo da pessoa** dentro do documento dela.

**Uma tentativa já falhou (2026-08-28).** Dado prometido
(`NSPasteboardItemDataProvider`) dá o instante exato da leitura, e foi
implementado — mas **quebrou a colagem no Slack**, que lê em várias etapas: a
primeira dispara o provider, a devolução limpa o pasteboard e as etapas
seguintes acham vazio. Revertido no mesmo dia. Patch em
`scratchpad/d1-dado-prometido.patch`, autópsia em
`.vibeflow/specs/devolucao-observada-do-pasteboard.md`.

Aprendizado que vale para qualquer tentativa nova: **não existe sinal de
"colagem consumida" que não exija dado preguiçoso**, e dado preguiçoso quebra
leitor de várias etapas. A devolução continua sendo por tempo. A pergunta boa
deixou de ser "como observar?" e passou a ser "qual tempo, e o que se troca
entre janela de sequestro do clipboard e segurança?".

*Evidência:* `.vibeflow/index.md` (Known Issues) · `TextInjector.swift:52` ·
regressão observada no Slack em 2026-08-28

### D2 · O ⌘V é postado às cegas — P
O app não checa se o foco tem campo editável. Com o foco num app sem campo de
texto, o ⌘V vira **atalho arbitrário no app da frente** — e em vários apps ⌘V
faz outra coisa. O anti-escopo original excluiu consultar a API de
Acessibilidade para descobrir isso; vale reabrir, já que a permissão já é
concedida.
*Evidência:* `.vibeflow/index.md` (Known Issues)

### D3 · `IsSecureEventInputEnabled` não significa o que o código assume — P
É flag **global da sessão**, não "campo de senha em foco". Qualquer processo
liga e esquece de desligar — e a partir daí o NeverType recusa inserir texto sem
motivo. Falso positivo que faz o app parecer quebrado.

**Texto corrigido em 29/08/2026; comportamento em aberto.** O comentário e o log
de `main.swift`, o doc de `TextInjector.Outcome.blockedBySecureInput` e a
mensagem do teste deixaram de dizer "campo de senha em foco": dizem o que o
código sabe — a flag global está ligada, algum processo a ligou, o texto ficou
na área de transferência e no menu. O que continua sem medição é a premissa de
que o macOS descartaria o ⌘V sintético; recusar colar enquanto a flag está
ligada é a decisão que este item ainda precisa tomar.
*Evidência:* `.vibeflow/index.md` (Known Issues) · `TextInjector.swift` ·
auditoria de 29/08 (K29, K112)

### ✅ D4 · O código afirmava não guardar o que a pessoa falou, e guardava — FEITO em 29/08
O doc comment de `lastRecordingURL()` dizia *"o app não guarda histórico de nada
que você falou"*. A auditoria de 29/08 achou **três** cópias em disco, não uma:
`historico.json` (30 transcrições), `nevertype.log` (o texto de cada transcrição
da sessão — sem doc nenhum e fora de "Limpar histórico") e `last.wav` (a gravação
inteira, também fora de "Limpar histórico").

O que mudou: o log passou a guardar tempo e tamanho, nunca o texto (`transcribed
in N ms: M chars`), e o doc de `log(_:)` carrega a regra; "Limpar histórico"
apaga o JSON **e** o `last.wav`, recusando só com gravação em curso
(`RecordingSink.removeDestination`, `AudioRecorder.discardLastRecording`, 4
testes); o doc de `lastRecordingURL()` lista os arquivos; o README ganhou "O que
fica em disco" e `docs/pitfalls.md` ganhou o caso. Guardar continua deliberado
e justificado em `TranscriptHistory.swift`.

**Falta você conferir no disco:** dite, abra
`~/Library/Application Support/NeverType/`, confira que o `nevertype.log` não tem
o texto e que "Limpar histórico" some com `historico.json` e `last.wav`.
*Evidência:* auditoria de 29/08 (§13.1, K1, B2, B3) · `main.swift` (doc de
`lastRecordingURL()`, `clearHistory()`, `log(_:)`) · `AudioRecorder.swift` ·
`AudioRecorderTests.swift` (suíte "Ciclo do arquivo de gravação")

---

## 2. O que muda como o app se sente

### L1 · Transcrição em streaming durante a fala — G
**Rebaixado em 28/08 por medição.** Era "o item mais valioso do backlog".

Cinco ditados reais, do log do app (lidos quando a linha ainda era `transcrito em
N ms → texto`; desde 29/08 ela é `transcribed in N ms: M chars[, K after
replacements]`, sem o texto — o número continua no mesmo lugar):

| áudio | transcrição | fator |
|---|---|---|
| 1,5 s | 647 ms | 0,431× |
| 2,3 s | 612 ms | 0,266× |
| 2,9 s | 679 ms | 0,234× |
| 19,4 s | 698 ms | 0,036× |
| 31,0 s | 1299 ms | 0,042× |

**20× mais áudio custa 2× mais tempo:** ~614 ms fixos + ~22 ms por segundo de
fala. A latência já não cresce de forma relevante com o tamanho do ditado.

O motivo está no formato: o whisper processa em **janelas de 30 s**. 1,5 s e
19,4 s cabem numa janela e custam ~650 ms; 31 s precisa de duas e custa
~1300 ms. O custo é quantizado, não linear.

A citação do OpenQuack que justificava este item — *"the wait doesn't grow with
length"* — descreve um problema que **esta máquina não tem**. Eu copiei a
justificativa de outro projeto sem conferir se o problema existia aqui, que é o
erro que este repositório inteiro existe para evitar.

O que sobra: streaming ataca só o custo marginal. Num ditado de 31 s levaria
1,3 s para ~0,65 s; nos curtos, que são a maioria, economiza ~50 ms. Continua
sendo trabalho de subsistema por um ganho que agora se sabe pequeno.
*Evidência:* log de uso, 5 ditados, 2026-08-28

### L2 · Carregar o modelo sob demanda — P, **depende de L1**
1,1 GB residentes o tempo todo e **8,3 s de boot frio**, medidos hoje
(`docs/launch-at-login.md`). O OpenQuack fica em ~120 MB parado
porque só carrega ao apertar a tecla.

Sozinho isto não compensa — só empurra a espera para o primeiro ditado do dia.
**Com L1 ele deixa de ter custo visível**, porque o carregamento acontece
enquanto você ainda está falando. Não implemente antes de L1.

Com o L1 rebaixado, este item ficou mais longe: ele depende de algo que hoje se
sabe pouco valioso.

### L4 · O piso de 614 ms por ditado — G
**É aqui que a latência mora de verdade**, e streaming não toca neste número.
Todo ditado paga ~614 ms antes de qualquer custo proporcional ao que foi falado
— inclusive um ditado de uma palavra.

Hipótese a verificar antes de qualquer spec: a janela de 30 s do whisper. Se
1,5 s de fala é processado como se fossem 30, o caminho é encurtar a janela ou
mudar a configuração que paga o padding.

**Medir antes de spec'ar.** `scripts/bench.sh` existe para isso, e o app já
separa carga e aquecimento no log. Sem saber onde os 614 ms são gastos, qualquer
spec aqui repete o erro do D1.
*Evidência:* os mesmos 5 ditados — intercepto do ajuste

### L3 · O ditado bloqueia uma thread do pool cooperativo por ~600 ms — P
Uma thread do pool presa por ditado. Com o app parado a maior parte do tempo
não dói, mas é dívida real e some junto com L1.
*Evidência:* `.vibeflow/index.md` (Known Issues)

---

## 3. Interação

### ✅ I1 · Hands-free com trava — FEITO em 29/08
Segurar continua sendo push-to-talk. **Duplo toque no ⌘ direito trava** em
mãos-livres; um toque para.

Não use ⌘+Espaço: (a) qualquer `keyDown` durante o hold já significa *cancelar*
(`HotkeyMonitor.swift:110`), e (b) ⌘Espaço é o Spotlight, que dispara com
qualquer um dos dois ⌘ — e o app não engole eventos de propósito. Suprimir
exigiria o `CGEventTap` que o projeto recusou por poder travar a entrada do
sistema inteiro.

Cabe inteiro dentro do `HotkeyMonitor`.

### ✅ I3 · Retorno auditivo ao armar e desarmar — IMPLEMENTADO
`Tone.swift` gera os quatro tons em vez de usar os do sistema, que são alertas
desenhados para *serem notados*. Começo 330 Hz, fim 262 Hz, trava 294→392,
descarte 262→196 (`main.swift:97-100`): o que encerra é mais grave que o que
começa, a trava sobe e o descarte desce, então a direção diz o que aconteceu sem
aprender qual som é qual. Ligados por padrão e desligáveis em Tecla › Sons
(`main.swift:518`). 6 testes, na suíte
"Tons do retorno auditivo". Commit `1479a4b`.

**Falta você ouvir.** Ninguém confirmou em uso que o volume (0,18) é discreto o
bastante em sala compartilhada, nem que o tom de começo não suja a transcrição —
o comentário de `Feedback.started()` em `main.swift` diz que ele entra pelo
microfone nos primeiros ~85 ms (a duração do tom; dizia ~60 até 29/08) e que a
aposta é o Whisper ignorá-lo, marcada como não medida. É a única afirmação da
feature sem número medido atrás.
*Evidência:* pedido do autor em uso, 2026-08-29 · `Tone.swift` · commit `1479a4b`

### ✅ I4 · Escolher a tecla do gatilho — IMPLEMENTADO
Submenu **Tecla** com as três opções de `HotkeyMonitor.Trigger.all`
(`main.swift:509`), marca na atual, escolha guardada em `UserDefaults` sob a
chave `trigger` e restaurada no lançamento (`main.swift:223`). O identificador
guardado é o keyCode, não o rótulo, porque rótulo é texto de interface e muda.
Trocar a tecla zera a máquina de estados (`HotkeyMonitor.swift:174-181`): sem
isso, trocar no meio de um hold deixaria uma gravação órfã, sem tecla que a
encerre. 4 testes, na suíte "Trigger da hotkey". Commit `1479a4b`.

Confirmado que **não** contradiz a decisão fechada sobre o `KeyboardShortcuts`:
nenhuma dependência SPM nova entrou.

**Falta você usar ⌥ e ⌃ direito de verdade.** O teste cobre a regra (máscaras
distintas, ida e volta pelo identificador), mas o caminho do teclado ao evento
só tem tempo de uso no ⌘ direito, que é o padrão.
*Evidência:* pedido do autor em uso, 2026-08-29 · `HotkeyMonitor.swift:140-150` ·
commit `1479a4b`

---

## 4. UI — o que dá para ver

### ✅ U1 · O overlay não prova que o microfone está pegando som — FEITO em 28/08
Hoje é um ponto vermelho estático e a palavra "ouvindo…", num painel de
148×40. Com o microfone mudo ou na entrada errada, você vê exatamente a mesma
coisa e recebe uma transcrição vazia.

Um medidor de nível resolve, e é o mesmo padrão do resto do projeto:
`falha-alta.md` diz que degradação silenciosa é erro.
*Evidência:* `Sources/NeverType/RecordingOverlay.swift:56`

### ✅ U2 · A transcrição acontece sem feedback nenhum — FEITO em 29/08
No `.released` o app faz `overlay.hide()` e `render(.idle)` **antes** de
transcrever. Entre soltar a tecla e o texto aparecer não há sinal nenhum — o
ícone já voltou ao normal e o painel já sumiu. Com 600 ms passa; com um ditado
longo, é uma zona morta em que o app parece não ter feito nada.
*Evidência:* `Sources/NeverType/main.swift`, `handle(.released)`

### U3 · Mostrar o número no painel — P
O OpenQuack mostra `2.4s · 0.30x` depois de cada transcrição. O **fator de tempo
real** (0,30× = transcreveu em 30% da duração do áudio) é métrica melhor que ms
cru, porque não depende do tamanho do ditado. Você já mede tudo que precisa.

### ✅ U4 · Histórico de transcrições — IMPLEMENTADO
`TranscriptHistory.swift`: teto de 30, mais recente primeiro, JSON atômico em
`~/Library/Application Support/NeverType/historico.json`. As três perguntas que
este item mandava decidir antes estão decididas e documentadas no doc comment —
30 entradas, texto claro no disco, apagável pelo menu. Submenu com hora e prévia
de 44 caracteres, clique copia, texto inteiro no tooltip, "Limpar histórico"
apaga o arquivo em vez de esvaziá-lo (`main.swift`, `rebuildMenu`) e, desde
29/08, apaga também o `last.wav` (D4). O
`ultima-transcricao.txt` da versão anterior é removido no lançamento, para não
deixar cópia órfã do que a pessoa falou. 7 testes. Commit `1479a4b`.

**Falta você abrir esse menu com histórico real.** Uma decisão de interface não
foi conferida por ninguém: com **uma** transcrição só não existe item
*Histórico* — o submenu só aparece a partir da segunda (`main.swift:547`), e
antes disso há apenas "Copiar última transcrição". Pode ser o certo, ou pode
parecer que o histórico sumiu.
*Evidência:* `CLAUDE.md` (O que falta) · `TranscriptHistory.swift` ·
commit `1479a4b`

---

## 5. Deixar outra pessoa usar

### A1 · Pacote distribuível sem compilar — P
Item nº 3 da lista de dor do `CLAUDE.md`. O OpenQuack resolve com um
**Homebrew cask no próprio repositório** (diretório `Casks/` na raiz) mais DMG
nos releases. Padrão copiável.

Atenção ao Gatekeeper: certificado local não é notarizado, então a primeira
abertura exige `botão direito → Abrir`. O OpenQuack tem o mesmo problema e
documenta assim.
*Evidência:* `CLAUDE.md` · [openquack](https://github.com/larryxiao/openquack)

### A2 · Ninguém além do autor instalou do zero — P
O caminho completo (clone → `build-app.sh` → `install.sh` → permissões → modelo)
nunca foi exercitado por outra pessoa. Cada suposição não testada aí é um
abandono na primeira tentativa. A forma barata: alguém do teu time num Mac
limpo, com você olhando por cima do ombro e anotando onde trava.
*Evidência:* `.vibeflow/index.md` (Known Issues) · `CLAUDE.md`

### ✅ A3 · Vocabulário customizado — IMPLEMENTADO
`Vocabulary.swift` com duas listas, e são duas de propósito: **termos** viram o
`initial_prompt` do whisper (dica de reconhecimento, probabilística) e
**substituições** rodam sobre o texto pronto (determinísticas, palavra inteira,
ignorando maiúsculas na busca — sem a fronteira de palavra, trocar "ia" por "IA"
estragaria "família"). Misturar as duas numa lista só seria prometer garantia
onde não existe. `VocabularyWindow.swift` edita as duas em abas; o menu mostra as
contagens (`main.swift:526-532`). 12 testes. Commit `43d968f`.

**Falta você usar com termos reais.** O ganho da lista de termos é
probabilístico e ninguém mediu se o `initial_prompt` melhora o reconhecimento
nesta máquina. `docs/model-choice.md:82` é evidência de que o problema
existe, não de que esta solução o resolve — e essa distinção virou a limitação
honesta no README, no lugar do "não há vocabulário customizado" que estava lá.
*Evidência:* `CLAUDE.md` (O que falta) · `Vocabulary.swift` · commit `43d968f`

---

## 6. Higiene

### H1 · Comparar o WER com um baseline público — P
O OpenQuack publica ~2,6% de erro em fala humana real num M4 base e ~6,3% com
ruído de escritório, em `docs/BENCHMARKS.md`. Você já tem `scripts/bench.sh`
medindo qualidade. Comparar os números vale mais que a impressão de que está bom.

### H2 · Doc comment de `TextInjector.pending` mistura dois assuntos — P
Geração e indexação por pasteboard num bloco só.
*Evidência:* `.vibeflow/index.md` (Known Issues)

### H3 · Não há CI; a alegação de isolamento de rede é verificada à mão — P
Não existe `.github/` no repositório e nenhum teste toca rede: `grep -rn
"URLSession\|CFNetwork\|otool" Sources/ Tests/ scripts/` volta vazio. O que
sustenta "nada sai da máquina" hoje é o item de Definition of Done conferido a
cada tarefa, mais a ausência de import de rede nas fontes — verificação humana,
que vale enquanto alguém lembrar de fazer.

O README afirmava "há teste de CI verificando isso no código e no binário".
**Corrigido em 29/08/2026 por não ter lastro** — a frase de hoje (`README.md:15`)
descreve a conferência manual, que é o que de fato existe. O item aqui é fechar a
distância: um check que falhe sozinho quando alguém adicionar rede, em vez de
depender de quem revisa notar.
*Evidência:* `.github/` inexistente em 29/08/2026 · grep sem resultado em
`Sources/`, `Tests/` e `scripts/` · `.vibeflow/conventions.md:118` (o Don't que
já existe) · `README.md:15`

### ✅ H4 · Link quebrado para as limitações, no README — FEITO em 29/08
`README.md` apontava para `#limitações`, mas o heading é "## Limitações
conhecidas" e a âncora dele é `#limitações-conhecidas`. Corrigido na passada de
docs da auditoria de 29/08 (R45); o arquivo agora só tem a forma certa.
*Evidência:* `grep -n 'limitações' README.md` em 29/08/2026 — todas as
ocorrências com `#limitações-conhecidas`

### H5 · "Um arquivo por unidade" já não descreve os testes — P
`conventions.md:44` diz "swift-testing, **um arquivo por unidade**". O
`AudioRecorderTests.swift` tem **cinco** suítes: "Conversão de áudio" (5 testes,
L8), "Trigger da hotkey" (4, L102), "Ciclo do arquivo de gravação" (7, L146),
"Nível de entrada do microfone" (6, L276) e "Trava de mãos-livres" (9, L325). As
duas da hotkey não são de áudio — são do `HotkeyMonitor`, que não tem arquivo de
teste próprio.

**A decisão é qual dos dois lados muda, e o item não presume nenhum.** Ou a
convenção passa a descrever o que o repositório faz de fato, ou trigger e trava
saem para um `HotkeyMonitorTests.swift` e a convenção continua valendo como
está. Não é óbvio que seja a segunda: quem escreveu deixou as suítes juntas, e o
motivo não está registrado em lugar nenhum — pode ter sido conveniência, ou pode
ser que as suítes compartilhem apoio de teste que eu não conferi.

Custo colateral de mexer: a contagem por arquivo do README e do `index.md` não
muda (81 continua 81), mas quem procurar teste de hotkey pelo nome do arquivo
hoje não acha.
*Evidência:* `.vibeflow/conventions.md:44` ·
`Tests/NeverTypeCoreTests/AudioRecorderTests.swift` (as cinco suítes, contadas em
29/08/2026) · ausência de `HotkeyMonitorTests.swift`

### ✅ H6 · A linha de abertura do `CLAUDE.md` descrevia a tecla como fixa — FEITO em 29/08
`CLAUDE.md:3` dizia só *"Segurar ⌘ direito grava, soltar transcreve"*. Agora diz
que ⌘ direito é o padrão, que ⌥ e ⌃ direito saem do menu, que dois toques travam
em mãos-livres — e que o app só transcreve português (B1 da auditoria), que é a
omissão mais cara para quem chega pelo README.
*Evidência:* `CLAUDE.md:3-5` · `HotkeyMonitor.swift:150` e `:192` ·
`Transcriber.swift` (`params.language = "pt"`)

---

## Decidido e fechado

- **Não fazer parada automática por silêncio.** Pausa não significa fim: é comum
  ficar em silêncio no meio do ditado enquanto se lê alguma coisa, e um corte
  automático transformaria uma pausa normal em ditado truncado. O modo
  mãos-livres é encerrado por toque, e só.

- **O nome continua NeverType.** `lazy2type` colide com o
  [LazyTyper](https://lazytyper.com/), que é o mesmo produto com nome quase
  idêntico. Além disso o `2` promete conversor em ferramenta de dev, o nome é só
  em inglês num app português, e trocar o bundle ID custaria reconceder
  Microfone e Acessibilidade e órfã o login item.
- **A chave de assinatura é alcançável por processo local.** Risco documentado e
  aceito; sem conserto com certificado local.
- **Não adotar `KeyboardShortcuts` para tecla configurável.** Dependência SPM
  externa contra a linkagem estática e o hardened runtime.
