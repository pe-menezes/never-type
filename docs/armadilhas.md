# Armadilhas

O que quebrou neste projeto, e o custo medido de cada erro. Quase nenhum destes
apareceu em revisão de código: a maioria só apareceu rodando, e vários faziam o
programa **relatar que estava tudo bem** enquanto não estava.

Está aqui porque nenhum é específico deste app.

---

## Verificação que se deixa enganar

### Procurar palavra em log não prova que algo aconteceu

O `ggml` inicializa o device Metal só para enumerá-lo, mesmo quando a inferência
roda em CPU. Um log de `whisper-cli -ng` — CPU explícita — contém **37 linhas**
com a palavra "metal", incluindo `using embedded metal library`.

Um `grep -qi metal` aceitava execução em CPU como prova de GPU. Custo, medido no
mesmo modelo e áudio: **encode 1635 ms em CPU contra 143 ms em Metal**. A bancada
inteira reportava números de CPU como se fossem do app.

O discriminador real é o backend escolhido, e a guarda exige o positivo **e**
rejeita o negativo:

```bash
metal_is_active() {
  local log="$1"
  grep -q 'whisper_backend_init_gpu: no GPU found' "$log" && return 1
  grep -Eq 'whisper_backend_init_gpu:.*MTL' "$log"
}
```

Dentro do processo, a versão correta nem olha log: enumera
`ggml_backend_dev_count()` e lê `ggml_backend_dev_name()`.

**Regra:** logs contêm o vocabulário de coisas que **não** aconteceram.

### Magic number não se compara como texto

O magic do ggml é `0x67676d6c`, gravado como uint32 little-endian. Os bytes em
disco saem invertidos: `6c 6d 67 67`, que lido como texto é **`lmgg`**, não
`ggml`.

`head -c 4 arquivo` = `"ggml"` reprovava **todo modelo válido**, incluindo o de
referência distribuído pelo Homebrew. Compare em hexadecimal.

### Magic sozinho não valida arquivo

Um download interrompido tem os primeiros bytes certos. Pior, o whisper.cpp
aceita um modelo truncado como "modelo vazio para teste" e devolve um contexto
**válido** — e a primeira inferência mata o processo com `std::out_of_range`,
exceção de C++ que nenhum `try` do Swift intercepta.

Reproduzido: 100 KB do modelo real no caminho de produção → `exit 134`, sem
aviso, sem ícone, sem menu. O app simplesmente não abria.

**Regra:** magic **e** piso de tamanho proporcional ao artefato real. Um piso de
50 MB para um modelo de 547 MB aprova download truncado.

E regra escrita não é regra aplicada: até 29/08/2026 este parágrafo já existia e
o piso era 50 MB em três dos cinco lugares que validam o modelo —
`ModelStore.minimumBytes` no app, `fetch-model.sh` e `setup-bench.sh`; só
`install.sh` e `verificar-instalacao.sh` usavam 400. Hoje são 400 MB nos cinco,
e na bancada o piso é por modelo (130 MB para o `small` de 181 MB). Custo de
conferir: um `grep` pelo número.

---

## Concorrência que o compilador não vê

### Closure dentro de método `@MainActor` herda o isolamento

Este derrubou o app duas vezes, e a primeira correção não funcionou.

O callback de `AVCaptureDevice.requestAccess` chega numa fila de background.
Usar `MainActor.assumeIsolated` ali é afirmar algo falso, e o Swift verifica em
runtime: `EXC_BREAKPOINT` em `_swift_task_checkIsolatedSwift`.

A correção óbvia — trocar o corpo por `Task { @MainActor in }` — **não resolve**.
Closures escritas dentro de um método `@MainActor` herdam esse isolamento por
inferência, e a checagem estoura na closure **externa**, antes de chegar no corpo.

A saída foi usar a API assíncrona, que não tem closure:

```swift
Task { @MainActor in
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    self.render(granted ? .idle : .blocked)
}
```

**Detalhe cruel:** o caminho só roda quando a permissão está *indefinida*. Em
qualquer teste com a permissão já concedida, o bug não aparece.

### `AVAudioNodeTapBlock` não é `Sendable`, e o build sai limpo

O tap de áudio roda em thread de tempo real; `stop()` roda na main. Os dois
tocavam o mesmo `AVAudioFile` e o mesmo conversor sem sincronização — e o Swift 6
com concorrência estrita **não acusa**, porque o tipo do bloco não é marcado.

A correção: o tap só copia o buffer e despacha para uma fila serial dona do
estado; `stop()` usa `queue.sync` como barreira — `removeTap` não garante
ausência de callback em voo.

### O SDK anota `@Sendable` por baixo do código, e o build quebra sem ninguém mexer nele

O oposto do item anterior: aqui o compilador passou a ver **mais** — numa outra
máquina, num código que não mudou.

`Resampler.convert(_:)` entregava ao conversor um bloco que capturava uma `var`
(`supplied`) e o `AVAudioPCMBuffer` de entrada. Compilava na máquina onde o
projeto nasceu, só com Command Line Tools — e a versão do compilador de lá **não
foi registrada**, o que é metade desta armadilha. Num clone limpo do mesmo
commit (`0d7efbe`), com Apple Swift 6.2.3 (swiftlang-6.2.3.3.21), Xcode completo
e SDK MacOSX26.2, `swift build --build-tests` e `swift test` saem com 1 e três
erros, medidos em 29/08/2026:

```
AudioRecorder.swift:90:20: error: capture of 'input' with non-Sendable type 'AVAudioPCMBuffer' in a '@Sendable' closure
AudioRecorder.swift:84:16: error: reference to captured var 'supplied' in concurrently-executing code
AudioRecorder.swift:88:13: error: mutation of captured var 'supplied' in concurrently-executing code
```

A última linha da saída é `error: fatalError`, que não diz nada — a causa está
acima. E ela é o tipo do bloco. Lido no header,
`AVFAudio.framework/Headers/AVAudioConverter.h`, linha 154 — a mesma linha no
`MacOSX26.2.sdk` do Command Line Tools e no `MacOSX.sdk` do Xcode 26.2:

```objc
typedef AVAudioBuffer * __nullable (^ NS_SWIFT_SENDABLE AVAudioConverterInputBlock)(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus);
```

O `NS_SWIFT_SENDABLE` está no `MacOSX26.sdk` (26.0) e no 26.2, e **não está no
`MacOSX15.4.sdk`** — `grep -c "NS_SWIFT_SENDABLE AVAudioConverterInputBlock"`
dá 0 lá. A anotação entrou com o SDK 26.0, e a documentação pública da Apple
ainda mostra a `typealias` sem ela: a doc não é o SDK. Em Swift 6 com
concorrência estrita, cada tipo que a Apple passa a marcar vira erro em código
que ninguém tocou.

A máquina de origem media macOS 26.2 em 28/08 e compilava. A única explicação
consistente com os fatos é o Command Line Tools de lá estar com um SDK 15.x, não
atualizado — e isso é inferência, não medição: ninguém conferiu lá, e a versão
do compilador de lá continua desconhecida.

O conserto: o buffer fica num `OSAllocatedUnfairLock<AVAudioPCMBuffer?>`
(`Sendable`, macOS 13+), que o bloco esvazia na primeira chamada e responde
`.noDataNow` depois. Nada de `@preconcurrency import`, `-strict-concurrency`
mais frouxo ou `@unchecked Sendable` — cada um desses apaga o diagnóstico em vez
de tratar o caso, e vermelho honesto vale mais que verde por afrouxar a régua.
Em qual thread o conversor chama o bloco a Apple não documenta (só que o
parâmetro é non-escaping); o lock custa nanossegundos e dispensa a resposta.

Depois, medido em 29/08/2026 sobre a mesma máquina e a mesma árvore:
`swift build --build-tests` sai 0, **0 erros, 6 warnings — os mesmos 6 da
rodada quebrada, nenhum novo**; `swift test --disable-xctest
--enable-swift-testing` sai 0, **81 de 81 testes em 12 suítes**, 1,507 s.

**Regra:** "compila aqui" sem `swift --version` e `xcrun --show-sdk-version`
anotados não é reproduzível. Registre os dois junto com a medição — a Apple move
a régua de `Sendable` a cada SDK.

### Consultar-e-decidir não é exclusão mútua

`NSRunningApplication.runningApplications(withBundleIdentifier:)` para garantir
instância única falha em lançamentos simultâneos: são dois passos, e o registro
no LaunchServices é assíncrono. **3 de 3** tentativas resultaram em duas
instâncias.

Com dois monitores globais de tecla, um ditado vira duas gravações, duas
transcrições e dois ⌘V. `flock` resolve num passo indivisível.

---

## Áudio

### O conversor retém amostras, e o fim da fala some

`AVAudioConverter` guarda amostras dentro do filtro de reamostragem entre
chamadas. Durante a gravação isso não importa — o resíduo sai na chamada
seguinte. No fim, importa: **982 quadros retidos em 1 s de áudio a 48 kHz**, que
são 61 ms — e é exatamente onde está o fim da frase.

Sem drenar, a última palavra de cada ditado sumia.

### Uma chamada não esgota o conversor

O conversor preenche até a capacidade do buffer de saída e guarda o resto.
Assumir que uma chamada basta funcionava para downsample e truncava no upsample:
**3744 quadros perdidos** convertendo 8 kHz (fone Bluetooth em modo HFP) para
16 kHz. É preciso bombear até secar.

### Motor de áudio parado ainda segura o microfone

Um `AVAudioEngine` parado mas vivo mantém o nó de entrada configurado, e o macOS
continua contando o app como usuário do microfone — o indicador do sistema fica
aceso o tempo todo. A instância precisa nascer e morrer com cada uso, inclusive
no caminho de erro:

```swift
var started = false
defer { if !started { self.engine?.reset(); self.engine = nil } }
```

---

## macOS: coisas que somem sem erro

### `NSStatusItem` criado antes de `setActivationPolicy` é descartado

E o objeto continua respondendo `isVisible = true` e `frame.width = 30`. O log do
app dizia que estava tudo bem enquanto nada era desenhado na tela.

Crie o item dentro de `applicationDidFinishLaunching`, depois da política.

### Imagem não-template é preta sobre fundo preto

Imagem *template* é a que o macOS repinta conforme o fundo da barra. Marcar
`isTemplate = false` para poder tingir de vermelho fazia o símbolo ser desenhado
na cor natural — preto — e sumir contra a barra escura.

E `contentTintColor` **só tinge imagem template**, então o vermelho pretendido
também não acontecia. O ícone ficava invisível exatamente enquanto gravava.

### Em tela cheia não existe menu bar

Um app cujo único feedback é o ícone da bandeja fica sem feedback nenhum no modo
em que a maioria dos aplicativos é usada. A saída é um `NSPanel` com
`level = .screenSaver` e `collectionBehavior` incluindo `.fullScreenAuxiliary`.

### `IsSecureEventInputEnabled()` é flag global da sessão

Não é "campo de senha em foco", apesar do nome sugerir. Qualquer processo pode
ligá-la — inclusive um sem interface, em segundo plano — e há apps que ligam e
esquecem de desligar. Um app que dependa dela para decidir se cola pode ficar
mudo indefinidamente por causa de outro programa.

### `security find-identity -v -p codesigning` filtra por confiança

Um certificado self-signed nunca aparece nessa lista, **mesmo funcionando
perfeitamente** para o `codesign`. Usar esse comando como teste de existência faz
o script recriar o certificado a cada execução — e no macOS isso revoga a
permissão de Acessibilidade toda vez, porque o TCC ancora no certificado.

Use `security find-identity <keychain>`, sem os filtros.

### Hardened runtime é incompatível com dylib de terceiro

Ligar `--options runtime` ativa validação de bibliotecas, que recusa carregar
código assinado por outra equipe. Com dylibs do Homebrew o app morre no dyld:

```
code signature not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

Não há meio-termo: ou linkagem estática, ou sem a proteção. Para um processo que
detém Acessibilidade — capaz de ler e injetar teclas no sistema inteiro — a
proteção vale o trabalho de compilar estático.

---

## Estado do usuário

### Restauração agendada precisa de guardas

Inserir texto via área de transferência exige salvar e devolver o que estava lá.
Devolver depois de um atraso fixo, incondicionalmente, destrói dado de duas
formas:

1. **Qualquer escrita nos N ms seguintes é revertida** — um ⌘C do usuário, o
   Universal Clipboard, um gestor de clipboard.
2. **Duas inserções dentro da janela** deixam o texto da primeira no lugar do
   conteúdo original, permanentemente: a segunda fotografa o pasteboard já
   contaminado pela primeira.

Três guardas resolvem: uma **geração** por operação (só a restauração mais
recente vale), o **retrato herdado** de uma restauração pendente (devolve o
conteúdo original, não o intermediário) e o **`changeCount`** (desiste se alguém
escreveu no meio).

E marque o item com `org.nspasteboard.ConcealedType`, ou cada inserção entra no
histórico de gestores de clipboard e sobrevive à restauração.

### Comentário de privacidade envelhece sem ninguém ver

`main.swift` abria com: *"Um arquivo só, sobrescrito… o app não guarda histórico
de nada que você falou."* Era verdade quando foi escrito. Em 29/08/2026 havia
três cópias do que a pessoa falou em disco: `historico.json` (30 transcrições),
`nevertype.log` (o texto de **cada** transcrição da sessão — que nenhum documento
mencionava e "Limpar histórico" não apagava) e `last.wav` (a gravação inteira,
que "Limpar histórico" também não apagava).

Nenhuma delas era defeito de comportamento — o histórico é deliberado e
documentado. O defeito era a frase: uma negativa categórica dentro da fonte, para
quem perguntasse "ele guarda o que eu falei?". Hoje o log guarda tempo e tamanho,
nunca o texto; "Limpar histórico" apaga o JSON e o WAV; e o comentário lista os
arquivos.

**Regra:** afirmação de privacidade se confere contra o disco — `ls` na pasta do
app depois de ditar —, não contra a intenção de quem escreveu.

---

## Shell

### `set -e` mais `pipefail` tornam fallbacks inalcançáveis

```bash
load_ms=$(grep -i 'load time' "$log" | sed ... )
[ -n "$load_ms" ] || load_ms=0     # nunca executa
```

Se o `grep` não casa, o pipeline retorna não-zero, `set -e` derruba o script na
atribuição, e a linha seguinte não roda. Envolva em `{ grep ... || true; }`.

### `trap ... RETURN` não dispara em `exit`

Uma função que cria diretório temporário e limpa com `trap ... RETURN` deixa o
temporário para trás quando o script sai por erro. No nosso caso ficava uma
chave RSA sem senha em `$TMPDIR`. Some um `trap ... EXIT`.

### `osascript` para controlar app pede autorização de Automação

Mandar Apple event para um app novo exige uma concessão do TCC, e o macOS abre um
diálogo modal — travando o script até alguém responder, sem nenhuma pista do
motivo. Use `pkill` e espere o processo sumir.

### `sleep` fixo esperando processo não é espera

Se o processo demora mais que o `sleep`, o script segue com premissa falsa. No
instalador, isso fazia a pessoa continuar rodando o binário antigo achando que
tinha atualizado. Espere a condição, com limite e falha explícita.

---

## Medição

### Tempo de parede mede o cache de disco junto

A bancada media `parede − load_time` para estimar o custo "quente". Com o cache de
página frio, o mesmo modelo marcou **5087 ms de parede contra 976 ms de
processamento real** — os ~4 s eram o fault-in dos 547 MB vindos do disco, que o
contador interno de "load" não cobre.

O veredito contra o teto de latência dependia de o modelo estar em cache ou não.
A correção: aquecer o cache antes de medir, e usar o cronômetro interno do
processo.

### Uma amostra não é medição

Latência declarada dentro do alvo com base em **um** ditado, do tamanho mais
barato possível, lida do log que o próprio app escreve. O número acabou certo, e
o método não sustentava a conclusão: não media variância, não exercitava o pior
caso, e o instrumento era o próprio objeto medido.

---

## O padrão por trás de quase todos

Os piores defeitos desta lista têm a mesma forma: **o programa relatava saúde
enquanto a realidade era outra.**

O log dizia que o ícone tinha sido desenhado. O objeto dizia estar visível. O
`grep` encontrava "metal". O contador dizia quanto tempo levou. O `try?` dizia
ter protegido. Nenhum estava mentindo — todos respondiam com precisão a uma
pergunta que não era a que importava.

A regra que sobrou: **verifique o efeito, não a intenção.** Enumere o dispositivo
em vez de procurar o nome dele. Compare os bytes em vez do texto. Meça de fora do
processo. E quando um caminho de falha nunca foi exercitado, trate-o como não
implementado — porque em quatro auditorias, nenhum caminho de falha não
exercitado estava correto.
