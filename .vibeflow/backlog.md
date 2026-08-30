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

### ✅ D1 · A devolução do clipboard é um chute de 0,6 s · IMPLEMENTADO em 30/08
Os 0,6 s continuam sendo o padrão, porque são o comportamento que já está em uso,
e passaram a ser ajustáveis pela pessoa: chave `clipboardRestoreDelay` em
`UserDefaults`, domínio `com.nevertype.app`, número em segundos, lida a cada
ditado e presa entre 0,1 s e 5 s (`TextInjector.resolvedRestoreDelay`, 4 testes).
Não entrou item de menu. O motivo está em "A decisão de interface", abaixo.

**A pesquisa externa que decidiu o desenho (29/08).** O espanso, expansor de
texto open source com a mesma engrenagem (escreve no pasteboard, dispara o atalho
de colar, devolve o conteúdo), documenta quatro botões onde este projeto tinha um
número fixo: `restore_clipboard` ligado por padrão, `restore_clipboard_delay` de
**300 ms**, `pre_paste_delay` de **300 ms** (espera antes de disparar o atalho,
porque disparar antes de o conteúdo estar no clipboard faz a operação falhar) e
`paste_shortcut_event_delay` de 10 ms entre as teclas. Fonte:
<https://espanso.org/docs/configuration/options/>. O QuiCopy usa 100 ms para a
devolução. O que isso ensina: **ninguém resolve isso por observação, todo mundo
usa cronômetro**, o que confirma a autópsia de 28/08. E os nossos 0,6 s são o
dobro do padrão do espanso, o que os torna conservadores contra o modo de falha
deste item e piores para o tempo em que o clipboard fica com o ditado.

**A espera antes do ⌘V não entrou, e o motivo é medição.** O `pre_paste_delay`
existe porque o atalho pode sair antes de o conteúdo chegar ao clipboard. Aqui a
escrita já é síncrona e o resultado dela já era conferido (`writeObjects`), e o
item carrega bytes concretos, sem nenhum data provider neste arquivo para adiar
a leitura até um callback. Então o código lê o texto de volta do pasteboard e
compara antes de postar o ⌘V. Se o que volta não for o que foi escrito, o ⌘V não
sai, o conteúdo da pessoa é devolvido na hora sob a mesma guarda de `changeCount`
da devolução agendada, e a inserção falha alto. Custa uma ida ao servidor de
pasteboard. Os 300 ms custariam metade do ditado inteiro (~614 ms, L1) e não
provariam nada.

**A decisão de interface.** Chave de `UserDefaults` documentada no README, sem
submenu. Três razões, e todas saem deste arquivo. O número nunca foi medido, e
oferecer três valores no menu daria a eles uma autoridade que a medição não
sustenta. Os dois ajustes que estão no menu (tecla e sons) são coisas que se
trocam durante o uso, e este é de configurar uma vez quando algum app se
comporta mal. E a posição da pílula já é uma preferência guardada sem nenhum item
de menu, que é o precedente mais próximo.

**Falta você usar.** Dite com algo conhecido na área de transferência antes, em
Slack e no terminal, e confira as duas coisas: o ditado entrou certo e o conteúdo
anterior voltou. Depois experimente `defaults write com.nevertype.app
clipboardRestoreDelay -float 1.2` e confira a linha `insertion:` do
`nevertype.log` no lançamento seguinte, que imprime o valor efetivo. Ninguém
mediu qual valor é o certo nesta máquina, e este item não pretende ter medido.
*Evidência:* `TextInjector.swift` (`defaultRestoreDelay`, `restoreDelayKey`,
`restoreDelayRange`, `resolvedRestoreDelay`, a guarda de leitura de volta em
`insert`) · `TextInjectorTests.swift` (4 testes do valor, 2 da leitura de volta) ·
`.vibeflow/specs/devolucao-observada-do-pasteboard.md` (a tentativa revertida) ·
espanso, URL acima, consultada em 29/08/2026

### ✅ D2 · O ⌘V é postado às cegas · IMPLEMENTADO em 30/08
`PasteTarget.swift` consulta o elemento em foco da sessão
(`AXUIElementCreateSystemWide` mais `AXFocusedUIElement`) e responde uma de três
coisas: `editable`, `notEditable` ou `unknown`. Só `notEditable` impede o ⌘V.
Nesse caso o texto fica no clipboard com a marca `concealed`, entra no histórico
como qualquer outro ditado, e o aviso sai pelos três canais que a falha de
inserção já usava: ícone cortado por 2 s, "Copy Last Transcription" no menu e
linha no `nevertype.log`, esta dizendo o papel que recusou e o comando que
desliga a checagem.

**A regra foi desenhada em torno de uma assimetria: falso negativo é pior que o
defeito.** Recusar colar onde dava deixa a pessoa com um ditado já falado e um
app que não fez nada, que é a queixa que o README inteiro tenta evitar. Então
erro da API de Acessibilidade, permissão ausente, timeout, elemento sem papel e
papel desconhecido chegam todos como `unknown`, e `unknown` cola. A ordem da
regra também protege: `AXValue` settable é conferido antes da lista de papéis,
então um elemento que diz aceitar texto nunca é vetado pelo papel dele.

**O que a consulta não classifica**, e onde o código cola assim mesmo: Electron e
Java quando o papel exposto não é de texto e o `AXValue` não é settable; terminal
que desenha a própria tela, cujo papel costuma ser de grupo ou desconhecido;
campo de senha, decidido antes pela flag de entrada segura (D3); app sem suporte
a Acessibilidade, que devolve erro; lista, tabela e outline, deixados de fora da
lista de recusa de propósito, porque célula de planilha e renomear no lugar vivem
lá e aceitam digitação. O terceiro sinal que o pedido citava,
`kAXFocusedWindowAttribute` com campo, não foi implementado: ele só poderia
produzir um `editable`, e todo caso em que ele responderia já cola por ser
`unknown`.

Desligável, no mesmo lugar da preferência do D1:
`defaults write com.nevertype.app checkFocusBeforePaste -bool false`. Com a
checagem desligada o comportamento é o de até 29/08.

**Falta você usar.** A regra tem 11 testes, e o caminho da API ao elemento real
não tem nenhum: ele depende de qual janela está na frente da máquina que roda a
suíte, e teste que lê isso não é teste. Então dite com o foco num botão, com um
menu aberto, e depois nos lugares onde você dita todo dia (Slack, terminal,
navegador, Notas), e veja se algum deles recusa onde dava para escrever. Uma
recusa dessas é mais grave que o defeito original, e a saída é o comando acima.
*Evidência:* `PasteTarget.swift` · `TextInjector.swift`
(`Outcome.noEditableField`, a guarda de foco em `insert`) · `main.swift`
(`deliver`, o caso novo) · `PasteTargetTests.swift` (11 testes da regra) ·
`TextInjectorTests.swift` (3 testes do caminho)

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

### D5 · `install.sh` aceita como modelo qualquer arquivo com 400 MB ou mais — P
`install.sh:78-79` dá o modelo instalado por presente se o arquivo existe em
`~/Library/Application Support/NeverType/models/` e tem pelo menos 400 MB — e só
isso: não lê os quatro primeiros bytes. É o único dos cinco lugares que validam
o modelo (`ModelStore.isValid`, `fetch-model.sh`, `setup-bench.sh`,
`verify-install.sh` e ele) sem o magic, e a regra de `docs/pitfalls.md` é magic
**e** piso. O que passa: qualquer arquivo de 400 MB ou mais com esse nome, ggml
ou não; o `install.sh` imprime `model present (N MB)` e abre o app, que recusa o
arquivo e abre com o ícone cortado. O `verify-install.sh:95-107` pega depois, se
alguém rodar. Visto na tradução de 29/08/2026; não consertado.
*Evidência:* `scripts/install.sh:78-79` · `scripts/verify-install.sh:95-107` (a
mesma conferência, com magic) · `docs/pitfalls.md` ("The magic alone does not
validate a file", os cinco lugares)

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

### ✅ H13 · O README passou no cold-read de forma e falhou no de estrutura — FEITO em 30/08
Medido em 29/08/2026 por dois leitores limpos, com tetos declarados antes de o
texto em inglês existir. Rodada 1 sobre `e8044dd`: 4 de 14 tetos estourados
(antítese, família inteira, 41 contra 6; clivada 8 contra 2; meta-comentário 2
contra 1; auto-plágio 12 formulações contra 0). Uma rodada de conserto rodou com
instrução de forma. Rodada 2: **8 de 14 estourados**, e cinco famílias pioraram.

| família | r1 | r2 | teto |
|---|---:|---:|---|
| antítese (12 com negação + 24 contraste sem negação) | 41 | 36 | ≤6, ≤1/H2 |
| clivada (migrou pra copular "The X is Y") | 8 | 7 | ≤2 |
| sentença-veredito | 3 | 20 | ≤3 |
| meta-comentário | 2 | 7 | ≤1 |
| puffery | 0 | 3 | ≤2 |
| par numérico | 1 | 4 | ≤2 |
| with + noun + particípio | 0 | 4 | ≤3 |
| auto-plágio (famílias) | 12 | 8 | 0 |
| travessão · ponto e vírgula de oposição | 0 · 0 | 0 · 0 | 0 |

**O que a medição ensinou, e é o motivo de o conserto ter sido arquitetural:**
proibir a fivela NOMEADA funciona (ponto e vírgula de oposição foi proibido por
escrito e ficou em 0), proibir a família não funciona, porque a figura migra pra
construção que nenhuma lista antecipou. Aqui migrou pra contraste sem negação
nenhuma (24 casos) e pra frase copular (19 aberturas "The X is"). O defeito
restante era **arquitetural**: 21 parágrafos no mesmo molde (frase-tese em
negrito, 2 a 4 frases de explicação, oração de julgamento no fim), 55 spans em
negrito em 348 linhas, e o frame binário anunciado antes de ser executado ("The
two lists do different jobs", "there are two ways"; 23 ocorrências do frame "N
coisas"). Teto numérico não conserta isso. O que consertou foi reescrever o
arquivo a partir de um inventário de fatos com destino declarado, um por um.

**Feito em 30/08/2026.** O README foi de 3.651 para 651 palavras, de 9 seções H2
para 7, de 56 spans em negrito para 2, com 0 ponto e vírgula, 0 travessão e 0
aspa curva. O `README.pt-BR.md` acompanha (675 palavras, 2 negritos) e perdeu os
41 travessões que tinha. A estrutura nova responde três perguntas de quem chega
de fora: o que é, se serve, como instalar. Todo o resto saiu para `docs/`.

Nenhum fato foi cortado sem destino. `docs/reference.md` nasceu neste turno e
recebeu o menu item a item, a gravação e a pílula, a inserção com a checagem de
foco e o secure input, os dois ajustes de `UserDefaults` com faixa e padrão, o
vocabulário, o inventário de disco, o grep de rede de 29/08 com os comandos do
lado do binário e a nota de que ninguém os rodou, a assinatura com as três
mitigações e o Developer ID, a tabela de arquitetura e o mapa do repositório.
`docs/model-choice.md` recebeu a faixa de 612 a 698 ms dentro de uma janela, a
ausência de limite e de aviso de duração, e a fronteira da cobertura da bancada
(ditado inteiro em outro idioma). `docs/INSTALL.md` recebeu o que o `install.sh`
faz no fim (abre o app) e o que as Command Line Tools trazem (toolchain do
Swift 6 e SDK), com o espelho `INSTALL.pt-BR.md` junto.

**O que ficou:** a conferência é minha, não de leitor limpo. Contei à mão no
arquivo novo (0 antítese, 0 clivada de abertura, 0 sentença-veredito, 0
auto-plágio), e o instrumento de 29/08 (`.cache/readme-metrics.py`) não rodou
neste turno porque o sandbox recusa executá-lo. Um cold-read de terceiro em cima
do README de hoje é o que fecha o ciclo de medição. E o `docs/reference.md` nunca
passou por cold-read nenhum: ele herdou a prosa do README antigo em registro de
referência, e as famílias de fivela não foram medidas lá.
*Evidência:* `README.md` e `README.pt-BR.md` em 30/08/2026 (`wc -w`: 651 e 675;
negritos: 2 e 2; `grep -c ';'`: 0 e 0) · `docs/reference.md` novo ·
`docs/model-choice.md`, `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md` alterados ·
relatórios do cold-read em `.cache/coldread-r1.md` e `.cache/coldread-r2.md`

Encerrado por decisão do Pedro em 29/08 depois da rodada 2, com o placar
publicado como saiu: a medição do catálogo diz que da terceira rodada em diante o
ganho é troca de tell por tell. Os dois defeitos de SUBSTÂNCIA que a mesma leitura
achou (manchete de latência contradita pelo próprio dado; alegação de rede mais
larga que a checagem descrita) foram consertados e estão no commit deste dia.

*Evidência:* relatórios em `.cache/coldread-r1.md` e `.cache/coldread-r2.md`
(fora do git) · catálogo de tells e tetos declarados no vault do autor ·
`README.md` em `e8044dd` e no commit seguinte


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

### H7 · Plural fixo no item do vocabulário — P
`main.swift:569` monta `Vocabulary (\(n) terms, \(n) replacements)…` sem tratar
o singular: com um termo e uma substituição o menu diz `Vocabulary (1 terms,
1 replacements)…`. Visto na tradução de 29/08/2026; não consertado.
*Evidência:* `Sources/NeverType/main.swift:569`

### H8 · Condição morta no aviso de `build/` do `install.sh` — P
`install.sh:64` faz `[ -d "$SOURCE" ] && warn "the build/ copy is still in the
repository…"`, mas nesse ponto `$SOURCE` sempre existe: a linha 36 já falhou se
não existisse, e o `cp -R` da linha 57 não o remove. O aviso sai em toda
instalação e o teste não decide nada — ou o aviso é incondicional e o `[ -d ]`
sobra, ou a intenção era outra e ninguém a escreveu. Visto na tradução de
29/08/2026; não consertado.
*Evidência:* `scripts/install.sh:36`, `:57`, `:64`

### H9 · `record-fixture.sh` estoura cru com duração não numérica — P
`record-fixture.sh:44` compara `"$DURATION" -lt 3` com `[`. Um segundo argumento
que não seja inteiro (`10s`, `abc`) faz o `[` reclamar (`integer expression
expected`) e o `set -e` derruba o script sem passar pelo `fail` — sem a linha de
uso e sem dizer qual argumento estava errado. Visto na tradução de 29/08/2026;
não consertado.
*Evidência:* `scripts/record-fixture.sh:19`, `:44`

### H10 · Divisão por zero no `bench.sh` se o `afinfo` não imprimir duração — P
`bench.sh:74-75` extrai `estimated duration` do `afinfo` com `sed` e converte
com `awk`; se a linha não vier, `d` fica vazio e o `awk` imprime `0`. Em
`bench.sh:153-154`, `windows=$(( (0 + 29999) / 30000 ))` dá 0 e
`per_w=$(( hot_ms / windows ))` morre com `division by 0` do bash — depois de já
ter rodado o whisper naquele fixture, sem `fail` e sem dizer qual arquivo não
tinha duração. Visto na tradução de 29/08/2026; não consertado.
*Evidência:* `scripts/bench.sh:74-75`, `:153-154`

### H11 · `verify-install.sh` aceita a cópia de `build/` como processo vivo — P
`verify-install.sh:79` faz `pgrep -x NeverType`, que casa pelo nome do
executável: um `build/NeverType.app` aberto do repositório conta como
`running (pid N)` mesmo com `/Applications/NeverType.app` fechado — e é
exatamente a cópia que o `install.sh:64` avisa que confunde. A verificação
reporta o processo certo e o errado do mesmo jeito. Visto na tradução de
29/08/2026; não consertado.
*Evidência:* `scripts/verify-install.sh:79-80` · `scripts/install.sh:61-64`

### H12 · `update.sh` não explica a recompilação quando o carimbo é `unknown` — P
`build-app.sh:293` carimba `unknown` no bundle quando não há git (build de
tarball). Em `update.sh:56-59`, `installed` vira `unknown` nesse caso — e também
sem plist ou sem a chave `NeverTypeCommit` —, a comparação de idempotência da
linha 67 nunca bate, e o script cai em `Repository already at X; only the
reinstall is missing` (`:79`) e recompila. O motivo real, carimbo ausente, não
aparece: a saída mostra `installed: unknown` sem dizer o que fazer com isso.
Visto na tradução de 29/08/2026; não consertado.
*Evidência:* `scripts/build-app.sh:291-293` · `scripts/update.sh:56-70`, `:79`

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
