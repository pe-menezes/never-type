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
  mesma inferência fica cerca de 11× mais lenta, o que inviabiliza o ditado.
- Command Line Tools do Xcode. **Xcode completo não é necessário.**
- `cmake`, só para compilar (`brew install cmake`).

O `.app` é autocontido — o whisper.cpp entra estático. Quem for apenas *usar* não
precisa de nada instalado além dele.

## Instalação

```bash
bash scripts/install.sh
```

Compila, instala em `/Applications`, cuida do modelo e abre o app. Da primeira
vez leva alguns minutos: o whisper.cpp é compilado do fonte e o modelo tem 547 MB.

Na primeira execução o macOS pede **Microfone** e **Acessibilidade**. As duas são
necessárias: sem microfone não há áudio, sem Acessibilidade o app não recebe a
tecla global — e fica mudo, sem erro nenhum, parecendo quebrado.

Terminada a instalação:

```bash
bash scripts/verificar-instalacao.sh
```

### Ou peça ao seu agente

Não há binário pré-compilado — cada instalação compila na própria máquina, e é
isso que dispensa o Gatekeeper. Se você usa um agente de codificação, mande o
link deste repositório e peça para ele seguir [`docs/INSTALL.md`](docs/INSTALL.md),
que foi escrito para ser executado por agente: ordem dos passos, o que fazer em
cada falha conhecida, o que **não** tentar consertar sozinho, e os três momentos
que exigem você clicando.

## Uso

Segure **⌘ direito**, fale, solte. O texto aparece onde o cursor estiver.
Apertar qualquer tecla comum durante o hold cancela e descarta o áudio. A tecla
sai do menu: ⌘, ⌥ ou ⌃ **do lado direito**, e só esses — um modificador sozinho
não digita caractere nem dispara ação do sistema, que é o que dispensa
interceptar o evento.

**Dois toques travam em mãos-livres**, e a gravação segue sem a tecla segurada:
um toque encerra e transcreve, **Esc** descarta. Toque é um hold abaixo de
250 ms, e o segundo tem 300 ms para chegar. Travado, teclar não cancela — com a
tecla segurada uma tecla comum quer dizer "isto era um atalho", mas em mãos-livres
não há modificador segurado, e um ditado longo não pode morrer porque você
digitou.

Enquanto grava, o ícone da menu bar fica vermelho e aparece um indicador
flutuante na base da tela — que sobrevive a aplicativos em tela cheia, onde a
menu bar fica oculta. Um tom curto marca começo, fim, trava e descarte — o que
encerra soa mais grave que o que começa, e o que trava sobe, então a direção
diz o que aconteceu sem você ter que aprender qual som é qual.

**A área de transferência é devolvida.** O texto entra por colagem, então o que
você tinha copiado volta logo depois — inclusive imagem, arquivo e HTML, não só
texto. Se a inserção não puder acontecer, o texto não se perde: fica em **Copiar
última transcrição**, no menu da bandeja, e é gravado em disco.

### No menu da bandeja

- **Tecla** — ⌘, ⌥ ou ⌃ direito, com marca na atual. A escolha fica guardada e
  volta no lançamento seguinte.
- **Sons** — no mesmo submenu, ligados por padrão. Som que não se pode desligar é
  defeito para quem trabalha em sala compartilhada.
- **Vocabulário…** — as duas listas que corrigem o que o modelo escreve, com as
  contagens no próprio item. O que elas garantem, e o que não, está em
  [Limitações](#limitações-conhecidas).
- **Histórico** — as últimas 30, mais recente primeiro, com a hora; o submenu
  aparece a partir da segunda. Clicar copia, o texto inteiro fica no tooltip, e
  dá para limpar por ali. Fica em texto claro em
  `~/Library/Application Support/NeverType/`: é registro do que você falou, e
  criptografar guardaria a chave ao lado do arquivo, na mesma máquina.
- **Abrir com o sistema** — só da cópia instalada (`/Applications` ou
  `~/Applications`); de outro lugar o app recusa e manda rodar o `install.sh`.
  Desligado nos Ajustes do Sistema, o menu diz isso e oferece o atalho para lá.

## Como funciona

| | |
|---|---|
| Modelo | Whisper `large-v3-turbo` quantizado (q5_0), 547 MB |
| Motor | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), compilado estático, backend Metal |
| Licença do modelo | MIT — código **e** pesos, pela OpenAI |
| Captura | `AVAudioEngine`, convertido para 16 kHz mono |
| Tecla global | `NSEvent` em modo escuta, sem interceptar |
| Inserção | área de transferência + ⌘V sintético |

O modelo é carregado uma vez no lançamento e mantido quente, então cada ditado
paga só a inferência.

**A latência não cresce com o tamanho da frase.** O Whisper processa em janelas
de 30 segundos: falar cinco segundos ou vinte e cinco custa o mesmo. Acima de 30 s
o custo dobra a cada janela — ver [Limitações](#limitações).

## Limitações conhecidas

**Ditado acima de 30 segundos passa do alvo de latência.** Abaixo disso todo
ditado custa ~780 ms; acima, o custo dobra a cada janela de 30 s. Não há aviso
nem limite.

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
desligar. Enquanto ela estiver ligada o NeverType não cola — deixa o texto na área
de transferência e avisa.

**Gestor de clipboard pode guardar o ditado.** O texto é marcado com
`org.nspasteboard.ConcealedType`, que Raycast e Maccy respeitam. Gestores que
ignoram a marca vão registrar cada ditado no histórico deles.

**Colar substitui a seleção.** Comportamento normal de colar, mas surpreende.

**Mover o app quebra a permissão.** Ele é instalado em `/Applications` e deve
ficar lá: o caminho fixo, junto com a assinatura estável, é o que faz a
Acessibilidade sobreviver às recompilações.

## Segurança

**Nada sai da máquina em tempo de uso.** Não há API de rede no código do app nem
framework de rede no binário. O único download do projeto é o do modelo, feito à
mão pelos scripts.

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

81 testes em **swift-testing**, não XCTest — o XCTest só existe com o Xcode
completo instalado, e este projeto compila com Command Line Tools.

Se você vai mexer no código, leia [`docs/armadilhas.md`](docs/armadilhas.md)
antes. São os erros que este projeto já cometeu, com o custo medido de cada um —
vários passariam despercebidos em revisão de código.

| | |
|---|---|
| `Sources/NeverTypeCore/` | conversão de áudio, tecla, transcrição, inserção — a parte testável |
| `Sources/NeverType/` | app de menu bar |
| `scripts/setup-bench.sh` | monta os modelos ggml a partir do checkpoint da OpenAI |
| `scripts/bench.sh` | mede latência e qualidade por modelo |
| `scripts/build-app.sh` | compila o whisper estático, empacota e assina |
| `scripts/install.sh` | instala em `/Applications` |
| `docs/armadilhas.md` | o que quebrou, e por quê |
| `docs/escolha-do-modelo.md` | por que `large-v3-turbo`, com os números |

## Licença

MIT. Depende de [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) e do
modelo Whisper da OpenAI (MIT, código e pesos).
