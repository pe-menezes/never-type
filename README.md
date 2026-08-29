# NeverType

Ditado por voz que nunca sai da sua máquina. Segure uma tecla em qualquer
aplicativo, fale, solte — e o texto aparece onde o cursor está.

**~600 ms** por ditado, num MacBook Pro M4 Pro. Nenhuma chamada de rede.

## Por que existe

Ferramentas de ditado por voz costumam mandar o áudio para um servidor. Isso é o
que as torna rápidas, e também o que as torna inviáveis onde o conteúdo não pode
sair da máquina.

O NeverType roda o modelo localmente. O áudio nasce e morre no seu Mac; o modelo
fica em disco; o app não abre conexão nenhuma em tempo de uso — não há API de
rede no código nem framework de rede no binário.

**Essa conferência é manual.** Não existe CI neste repositório: o que sustenta a
afirmação é um item de Definition of Done, verificado no código e no binário a
cada tarefa. Ver [Segurança](#segurança).

## Requisitos

- macOS 14+ em Apple Silicon. O Metal é o que torna a latência viável: sem GPU a
  mesma inferência fica cerca de 11× mais lenta (encode de 1635 ms contra
  143 ms, medido em `docs/armadilhas.md`), o que inviabiliza o ditado.
- Command Line Tools do Xcode. **Xcode completo não é necessário.**
- `cmake`, só para compilar (`brew install cmake`).
- **O modelo, 547 MB, que não vem no `.app`.** Fica em
  `~/Library/Application Support/NeverType/models/`, e há dois caminhos para
  colocá-lo lá. O do repositório é `scripts/setup-bench.sh`, que exige
  **Homebrew** (instala `whisper-cpp` por ele) e **python3** (cria um venv com
  torch), baixa do CDN da OpenAI os **três** checkpoints da bancada — turbo,
  medium e small — e converte e quantiza cada um. O outro é copiar o arquivo de
  quem já tem para `models/` e rodar `scripts/fetch-model.sh`, que valida magic
  e tamanho antes de instalar. Os dois estão em [`docs/INSTALL.md`](docs/INSTALL.md).
- **Fala em português.** O idioma é fixo no código; não há opção no menu. Ver
  [Limitações](#limitações-conhecidas).

O whisper.cpp entra estático no `.app`: para *rodar*, ele não depende do
Homebrew nem de biblioteca instalada. O que ele precisa de fora é o modelo acima
e, na primeira execução, as duas permissões.

## Instalação

```bash
bash scripts/install.sh
```

Compila (se `build/NeverType.app` ainda não existe — depois de mudar código,
rode `scripts/build-app.sh` antes), instala em `/Applications`, confere o modelo
e abre o app. Da primeira vez leva alguns minutos: o whisper.cpp é compilado do
fonte. O modelo ele não baixa: se faltar, imprime os dois caminhos de
[Requisitos](#requisitos) e segue.

Na primeira execução o macOS pede **Microfone** e **Acessibilidade**. As duas são
necessárias: sem microfone não há áudio; sem Acessibilidade o app não recebe a
tecla global. Ele avisa do jeito que um app sem janela consegue — ícone cortado
(`mic.slash`), "Acessibilidade: faltando" e o item "Abrir Ajustes de
Acessibilidade…" no menu, uma linha em `nevertype.log` e o pedido do próprio
macOS —, mas segurar a tecla não faz nada, e quem não abre o menu conclui que
está quebrado.

Terminada a instalação:

```bash
bash scripts/verificar-instalacao.sh
```

### Ou peça ao seu agente

Não há binário pré-compilado — cada instalação compila na própria máquina, e é
isso que dispensa o Gatekeeper. Se você usa um agente de codificação, mande o
link deste repositório e peça para ele seguir [`docs/INSTALL.md`](docs/INSTALL.md),
que foi escrito para ser executado por agente: ordem dos passos, o que fazer em
cada falha conhecida, o que **não** tentar consertar sozinho, e os quatro momentos
que exigem você: instalar as Command Line Tools, conceder as duas permissões e
ditar a frase que prova a instalação.

## Uso

Segure **⌘ direito**, fale, solte. O texto aparece onde o cursor estiver.
Apertar qualquer tecla comum — ou Esc — durante o hold cancela e descarta o
áudio. A tecla sai do menu: ⌘, ⌥ ou ⌃ **do lado direito**, e só esses — um
modificador sozinho não digita caractere nem dispara ação do sistema, que é o que
dispensa interceptar o evento. Trocar a tecla no meio de um hold descarta esse
hold.

**Dois toques travam em mãos-livres**, e a gravação segue sem a tecla segurada:
um toque encerra e transcreve, **Esc** descarta. Toque é um hold abaixo de
250 ms, e o segundo tem 300 ms para chegar. Travado, teclar não cancela — com a
tecla segurada uma tecla comum quer dizer "isto era um atalho", mas em mãos-livres
não há modificador segurado, e um ditado longo não pode morrer porque você
digitou.

Enquanto grava, o ícone da menu bar fica vermelho e a **pílula flutuante** mostra
o nível do microfone em barras — se elas não mexem, não está entrando som, e a
transcrição vai voltar vazia. Solta a tecla, ela mostra uma onda azul enquanto o
modelo trabalha, e volta ao repouso quando o texto sai. A pílula fica na tela o
tempo todo, mesmo parada: um app sem janela que morre não muda nada visualmente,
e ela parada é a prova de que ele está vivo. Nasce no canto inferior direito, mas
é arrastável — solte perto de uma borda e ela gruda; a posição fica guardada. E
sobrevive a aplicativos em tela cheia, onde a menu bar fica oculta.

Um tom curto marca começo, fim, trava e descarte — o que encerra soa mais grave
que o que começa, e o que trava sobe, então a direção diz o que aconteceu sem
você ter que aprender qual som é qual.

**Transcrição vazia não insere nada** nem entra no histórico: o app só escreve
uma linha no log. Sem Metal — o app enumera os dispositivos do ggml no
lançamento — o ícone abre cortado e o log avisa; sem modelo válido, o ícone abre
cortado e a linha "Modelo:" do menu traz a mensagem com o script a rodar.

**A área de transferência é devolvida.** O texto entra por colagem, então o que
você tinha copiado volta logo depois — inclusive imagem, arquivo e HTML, não só
texto. Se a inserção não puder acontecer, o ícone fica cortado por 2 s e o texto
não se perde: fica em **Copiar última transcrição**, no menu da bandeja, e em
`historico.json` (ver [O que fica em disco](#o-que-fica-em-disco)).

### No menu da bandeja

As duas primeiras linhas dizem a tecla atual ("Trigger: ⌘ direito (segure e
fale)") e o resumo do mãos-livres. Depois:

- **Tecla** — ⌘, ⌥ ou ⌃ direito, com marca na atual. A escolha fica guardada e
  volta no lançamento seguinte.
- **Sons** — no mesmo submenu, ligados por padrão. Som que não se pode desligar é
  defeito para quem trabalha em sala compartilhada. O volume é fixo, sem ajuste.
- **Vocabulário…** — abre a janela do vocabulário: duas abas (termos e
  substituições), botões + e –, salva a cada célula editada; fechar devolve o
  foco ao app em que você estava. As contagens aparecem no próprio item. O que
  as listas garantem, e o que não, está em [Limitações](#limitações-conhecidas).
- **Microfone**, **Acessibilidade** — `ok` ou `faltando`, consultados ao sistema
  toda vez que o menu abre. Sem Acessibilidade aparece também **Abrir Ajustes de
  Acessibilidade…**.
- **Modelo** — `Metal · carga N ms · aquecimento N ms`: o backend que o ggml
  registrou, quanto levou para carregar o modelo e quanto levou o aquecimento
  (1 s de silêncio transcrito no lançamento). `CPU (LENTO)` no lugar de `Metal`
  é falha, não aviso. Se o modelo não carregou, a linha traz o erro e o script a
  rodar.
- **Versão** — o commit de que o binário foi compilado. É a versão real: a que o
  Finder mostra (0.1.0) é fixa.
- **Copiar última transcrição** — aparece a partir da primeira transcrição; a
  prévia fica no tooltip.
- **Histórico** — as últimas 30, mais recente primeiro, com a hora e uma prévia de
  44 caracteres; o submenu aparece a partir da segunda. Clicar copia, o texto
  inteiro fica no tooltip, e **Limpar histórico** apaga o `historico.json` **e o
  `last.wav`**, o áudio do último ditado. Fica em texto claro em
  `~/Library/Application Support/NeverType/`: é registro do que você falou, e
  criptografar guardaria a chave ao lado do arquivo, na mesma máquina.
- **Abrir com o sistema** — só da cópia instalada (`/Applications` ou
  `~/Applications`); de outro lugar o app recusa, o ícone fica cortado por 2 s e
  o log manda rodar o `install.sh`. Desligado nos Ajustes do Sistema, o menu diz
  isso e oferece o atalho para lá.
- **Sair do NeverType** (⌘Q). Abrir o app já aberto não cria segunda instância:
  a nova ativa a que está rodando e sai.

## Como funciona

| | |
|---|---|
| Modelo | Whisper `large-v3-turbo` quantizado (q5_0), 547 MB |
| Motor | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), compilado estático, backend Metal |
| Licença do modelo | MIT — código **e** pesos, pela OpenAI |
| Captura | `AVAudioEngine`, convertido para 16 kHz mono |
| Tecla global | `NSEvent` em modo escuta, sem interceptar |
| Inserção | área de transferência + ⌘V sintético |

O modelo é carregado uma vez no lançamento e aquecido com 1 s de silêncio, então
cada ditado paga só a inferência. Só transcreve **português**: o idioma é fixo no
código.

**A latência quase não cresce com o tamanho da frase.** Cinco ditados reais,
lidos do log do app em 2026-08-28: ~614 ms fixos mais ~22 ms por segundo de fala
(`.vibeflow/backlog.md`, L1). O degrau é a janela de 30 s do Whisper: de 1,5 s a
19,4 s custou entre 612 e 698 ms; 31 s precisou de duas janelas e custou
1299 ms — ver [Limitações](#limitações-conhecidas).

## Limitações conhecidas

**Ditado longo custa por janela de 30 s, e o alvo de 1500 ms só foi medido até
31 s.** Os números que circulam neste repositório medem coisas diferentes:

- **~600 ms** é o app com o modelo quente: 599–609 ms num ditado curto
  (`docs/escolha-do-modelo.md`) e 612–698 ms em quatro ditados reais de 1,5 a
  19,4 s, lidos do log do app em 2026-08-28 (`.vibeflow/backlog.md`, L1).
- **~780 ms** é o `whisper-cli` na bancada — 782 ms por ditado de até 30 s, pelo
  cronômetro interno do processo. É o número que escolheu o modelo, não o que
  você sente ditando.
- **1299 ms** foi um ditado de 31 s no app, duas janelas, na mesma medição de
  2026-08-28: dentro do teto, embora a bancada projetasse 1640 ms (2 × 820).
  Acima de duas janelas ninguém mediu.

Não há aviso nem limite de duração.

**Só transcreve português.** O idioma está fixo no código (`"pt"`), sem opção no
menu. Termos em inglês no meio da fala são o caso medido na bancada; ditar
inteiro em outro idioma não foi medido.

**Fone Bluetooth degrada o áudio.** Ao abrir o microfone, o macOS coloca fones
Bluetooth em modo HFP a 8 kHz, e de quebra corta a música. A conversão funciona
(há teste), mas o reconhecimento piora. Para ditar, prefira o microfone do Mac.

**O vocabulário customizado não garante o termo, só aumenta a chance.** O menu
tem duas listas, e são duas de propósito. Os **termos** viram o `initial_prompt`
do whisper: dica de reconhecimento, probabilística, sem garantia. Só as
**substituições** são determinísticas — e elas exigem que você já saiba com o que
o termo é confundido, porque consertam "saiu X, eu queria Y", não a palavra que
sai errada de um jeito diferente a cada vez.

**O app pode se recusar a colar por causa de outro programa.** Ele consulta a
flag *secure input* do macOS, que existe para proteger digitação de senha. Só que
a flag é **global da sessão**, não "campo de senha em foco": qualquer processo
pode ligá-la, inclusive em segundo plano, e há apps que ligam e esquecem de
desligar. Enquanto ela estiver ligada o NeverType não cola: deixa o texto na área
de transferência (marcado como oculto) e no menu, o ícone fica cortado por 2 s e
o log diz o que aconteceu. Se você não está num campo de senha, foi outro app.

**Gestor de clipboard pode guardar o ditado.** Na inserção o texto é marcado com
`org.nspasteboard.ConcealedType`, que Raycast e Maccy respeitam; gestores que
ignoram a marca vão registrar cada ditado no histórico deles. A exceção é sua:
**"Copiar última transcrição" e os itens do Histórico copiam sem a marca e sem
devolver a área de transferência** — é uma cópia que você pediu, então o texto
fica lá e entra no histórico de qualquer gestor.

**Colar substitui a seleção.** Comportamento normal de colar, mas surpreende.

**Mover o app quebra a permissão.** Ele é instalado em `/Applications` e deve
ficar lá: o caminho fixo, junto com a assinatura estável, é o que faz a
Acessibilidade sobreviver às recompilações.

## Segurança

**Nada sai da máquina em tempo de uso.** Não há API de rede no código do app nem
framework de rede no binário. O único download do projeto é o do modelo, feito à
mão pelos scripts.

### O que fica em disco

Tudo em `~/Library/Application Support/NeverType/`, em texto claro — criptografar
guardaria a chave ao lado do arquivo, na mesma máquina:

- `historico.json` — as últimas 30 transcrições. **Limpar histórico** apaga.
- `last.wav` — o áudio do último ditado, sobrescrito a cada gravação. **Limpar
  histórico** apaga; cancelar um ditado também não deixa arquivo. A transcrição
  não lê daqui (usa as amostras em memória); o WAV é artefato de depuração.
- `nevertype.log` — diagnóstico da sessão, truncado a cada lançamento. Guarda
  tempo e tamanho de cada transcrição, **nunca o texto**.
- `vocabulario.json` — os termos e substituições que você cadastrou.
- `models/` — o modelo, 547 MB.

Fora dessa pasta só há preferências em `UserDefaults` (domínio
`com.nevertype.app`): tecla, sons e posição da pílula, sem texto. O
`ultima-transcricao.txt` de versões anteriores é apagado no lançamento.

**O app roda com hardened runtime**, que liga a validação de bibliotecas: o
processo recusa carregar código que não venha assinado junto com ele. Isso importa
porque o NeverType detém Acessibilidade — permissão de ler e injetar teclas no
sistema inteiro. É também por isso que o whisper.cpp entra estático: a validação
recusa dylibs de terceiros.

**O certificado de assinatura é um risco conhecido e aceito.** Para que a
permissão de Acessibilidade sobreviva a recompilações, o app é assinado com um
certificado local estável, e o macOS amarra Microfone e Acessibilidade a esse
certificado. Consequência: **quem já executa código como você nesta máquina pode
se assinar como NeverType e herdar essas permissões.**

Isso é inerente a certificado local, não um descuido — a alternativa é assinatura
ad-hoc, que faz o macOS revogar a permissão a cada build. As mitigações aplicadas
reduzem a exposição sem eliminar a classe:

- a senha do keychain é derivada do identificador da máquina, nunca versionada
- a chave privada é liberada só ao `codesign`, não a qualquer aplicativo
- o keychain fica em modo 600 e é travado ao fim de cada build

Para distribuição além de uso pessoal, o certo é um Developer ID da Apple.

**Perder o keychain revoga sua permissão.** Ele fica em
`~/Library/Keychains/nevertype-signing.keychain-db`. Apagá-lo faz o próximo build
gerar outro certificado, e o macOS pede Acessibilidade de novo.

## Desenvolvimento

```bash
bash scripts/build-app.sh     # primeira vez: compila o whisper.cpp em vendor/
swift build && swift test
```

`vendor/` não é versionado. Sem ele o `swift build` falha com
`could not build Objective-C module 'CWhisper'` — mensagem que não diz a causa.

86 testes em **swift-testing**, não XCTest — o XCTest só existe com o Xcode
completo instalado, e este projeto compila com Command Line Tools.

Se você vai mexer no código, leia [`docs/armadilhas.md`](docs/armadilhas.md)
antes. São os erros que este projeto já cometeu, com o custo medido de cada um —
vários passariam despercebidos em revisão de código.

| | |
|---|---|
| `Sources/NeverTypeCore/` | conversão de áudio, tecla, transcrição, inserção, vocabulário, histórico, tons e login item — a parte testável |
| `Sources/NeverType/` | app de menu bar: ícone, menu, pílula, janela do vocabulário |
| `scripts/setup-bench.sh` | monta os três modelos ggml a partir dos checkpoints da OpenAI (exige Homebrew e python3) |
| `scripts/fetch-model.sh` | valida e instala o modelo de `models/` no lugar definitivo |
| `scripts/record-fixture.sh` | grava fixtures da bancada em 16 kHz mono (exige `ffmpeg`) |
| `scripts/bench.sh` | mede latência e qualidade por modelo |
| `scripts/build-app.sh` | compila o whisper estático, empacota e assina |
| `scripts/install.sh` | instala em `/Applications` |
| `scripts/verificar-instalacao.sh` | confere app, assinatura, processo e modelo por bytes |
| `scripts/atualizar.sh` | traz o remoto, recompila, reinstala e verifica |
| `docs/INSTALL.md` | roteiro de instalação escrito para um agente executar |
| `docs/armadilhas.md` | o que quebrou, e por quê |
| `docs/escolha-do-modelo.md` | por que `large-v3-turbo`, com os números |
| `docs/inicializacao-com-o-sistema.md` | quanto custa abrir com o sistema, medido |
| `fixtures/README.md` | o que gravar para a bancada, e o que não |

## Licença

MIT. Depende de [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) e do
modelo Whisper da OpenAI (MIT, código e pesos).
