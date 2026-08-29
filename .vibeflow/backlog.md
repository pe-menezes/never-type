# Backlog — FalaFlow

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

Estes três são os únicos itens do backlog que causam **dano ao usuário**, não
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
liga e esquece de desligar — e a partir daí o FalaFlow recusa inserir texto sem
motivo, dizendo "campo de senha em foco" quando não há nenhum. Falso positivo
que faz o app parecer quebrado.
*Evidência:* `.vibeflow/index.md` (Known Issues) · `TextInjector.swift`

---

## 2. O que muda como o app se sente

### L1 · Transcrição em streaming durante a fala — G
**Rebaixado em 28/08 por medição.** Era "o item mais valioso do backlog".

Cinco ditados reais, do log do app:

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
(`docs/inicializacao-com-o-sistema.md`). O OpenQuack fica em ~120 MB parado
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

### I3 · Retorno auditivo ao armar e desarmar — P
Um som curto e discreto ao travar em mãos-livres e ao encerrar. Hoje o único
sinal é visual, e a pílula pode estar fora do canto que você está olhando —
principalmente porque ela é arrastável.

Referência: o Wispr Flow faz isso ao acionar. Vale olhar como soa antes de
escolher o som.
*Evidência:* pedido do autor em uso, 2026-08-29

### I4 · Escolher a tecla do gatilho — P
Hoje é ⌘ direito, fixo. O `HotkeyMonitor.Trigger` **já tem** `rightCommand`,
`rightOption` e `rightControl` prontos — falta só expor no menu e guardar a
escolha.

Atenção: isto **não** contradiz a decisão fechada de não adotar o
`KeyboardShortcuts`. Aquela decisão é sobre gravar atalho arbitrário, que exige
dependência externa; escolher entre três triggers que já existem no código não
exige nada.
*Evidência:* pedido do autor em uso, 2026-08-29

---

## 4. UI — o que dá para ver

### ✅ U1 · O overlay não prova que o microfone está pegando som — FEITO em 28/08
Hoje é um ponto vermelho estático e a palavra "ouvindo…", num painel de
148×40. Com o microfone mudo ou na entrada errada, você vê exatamente a mesma
coisa e recebe uma transcrição vazia.

Um medidor de nível resolve, e é o mesmo padrão do resto do projeto:
`falha-alta.md` diz que degradação silenciosa é erro.
*Evidência:* `Sources/FalaFlow/RecordingOverlay.swift:56`

### ✅ U2 · A transcrição acontece sem feedback nenhum — FEITO em 29/08
No `.released` o app faz `overlay.hide()` e `render(.idle)` **antes** de
transcrever. Entre soltar a tecla e o texto aparecer não há sinal nenhum — o
ícone já voltou ao normal e o painel já sumiu. Com 600 ms passa; com um ditado
longo, é uma zona morta em que o app parece não ter feito nada.
*Evidência:* `Sources/FalaFlow/main.swift`, `handle(.released)`

### U3 · Mostrar o número no painel — P
O OpenQuack mostra `2.4s · 0.30x` depois de cada transcrição. O **fator de tempo
real** (0,30× = transcreveu em 30% da duração do áudio) é métrica melhor que ms
cru, porque não depende do tamanho do ditado. Você já mede tudo que precisa.

### U4 · Histórico de transcrições — P
Hoje só a última, em `ultima-transcricao.txt`. Já está na lista de dor do
`CLAUDE.md`. Decidir antes: quantas, por quanto tempo, e se fica em texto puro
no disco — é o registro do que a pessoa falou.
*Evidência:* `CLAUDE.md` (O que falta)

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

### A3 · Vocabulário customizado — P
Nomes próprios, termos de domínio, nomes de projeto. Está na lista do
`CLAUDE.md` e o OpenQuack tem como "custom dictionary".
*Evidência:* `CLAUDE.md` (O que falta)

---

## 6. Higiene

### H1 · Comparar o WER com um baseline público — P
O OpenQuack publica ~2,6% de erro em fala humana real num M4 base e ~6,3% com
ruído de escritório, em `docs/BENCHMARKS.md`. Você já tem `scripts/bench.sh`
medindo qualidade. Comparar os números vale mais que a impressão de que está bom.

### H2 · Doc comment de `TextInjector.pending` mistura dois assuntos — P
Geração e indexação por pasteboard num bloco só.
*Evidência:* `.vibeflow/index.md` (Known Issues)

---

## Decidido e fechado

- **Não fazer parada automática por silêncio.** Pausa não significa fim: é comum
  ficar em silêncio no meio do ditado enquanto se lê alguma coisa, e um corte
  automático transformaria uma pausa normal em ditado truncado. O modo
  mãos-livres é encerrado por toque, e só.

- **O nome continua FalaFlow.** `lazy2type` colide com o
  [LazyTyper](https://lazytyper.com/), que é o mesmo produto com nome quase
  idêntico. Além disso o `2` promete conversor em ferramenta de dev, o nome é só
  em inglês num app português, e trocar o bundle ID custaria reconceder
  Microfone e Acessibilidade e órfã o login item.
- **A chave de assinatura é alcançável por processo local.** Risco documentado e
  aceito; sem conserto com certificado local.
- **Não adotar `KeyboardShortcuts` para tecla configurável.** Dependência SPM
  externa contra a linkagem estática e o hardened runtime.
