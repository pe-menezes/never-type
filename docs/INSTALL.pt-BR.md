English: [INSTALL.md](INSTALL.md)

# Instalar o NeverType

Este guia pode ser seguido diretamente ou por um agente de código. As etapas
marcadas com **PARE E PEÇA** exigem interação da pessoa que instala.

O NeverType é compilado na máquina de quem instala e usa um certificado local
para manter a identidade do app entre atualizações. Ainda não há binário
pré-compilado para distribuição.

## Antes de começar

Consulte [pitfalls.md](pitfalls.md) para detalhes dos problemas de instalação
e compilação já encontrados.

**Quatro coisas neste roteiro exigem a pessoa, e nenhum agente as resolve:**
instalar as Command Line Tools, conceder Microfone, conceder Acessibilidade e
ditar a frase que prova a instalação. Elas estão marcadas com **PARE E PEÇA**
abaixo, com o texto a dizer.

## O que você pode consertar sozinho, e o que não pode

| Pode | Pare e pergunte |
|---|---|
| `brew install cmake` | Qualquer coisa com `security list-keychains` |
| Disparar `xcode-select --install` e esperar | Apagar `~/Library/Keychains/nevertype-signing.keychain-db` |
| Recompilar depois de falha de build | Escrever fora do repositório e de `~/Library/Application Support/NeverType/` |
| Repetir um download interrompido | Instalar em `/Applications` sem permissão de escrita |
| Apagar um modelo inválido e rebaixar | Desativar verificação para fazer um passo passar |

A linha do keychain não é excesso de zelo. `security list-keychains -s`
**substitui a lista inteira**: errar ali tira o keychain de login da pessoa, e
as senhas de Wi-Fi, Safari e apps podem ficar indisponíveis até restaurar a lista. O `build-app.sh` tem um guarda-corpo
exatamente por isso. Não improvise nesse comando.

E apagar o keychain de assinatura **revoga a permissão de Acessibilidade**: a
pessoa vai ter que conceder tudo de novo.

## 1. Pré-requisitos

```bash
uname -s   # precisa ser Darwin
uname -m   # precisa ser arm64
sw_vers -productVersion   # precisa ser 14 ou maior
```

Intel ou macOS antigo: **pare**. Sem Metal a transcrição fica ~11× mais lenta, e
o projeto recusa de propósito.

### Command Line Tools: PARE E PEÇA

```bash
xcode-select -p   # se falhar, não estão instaladas
```

Faltando, rode `xcode-select --install` e diga à pessoa:

> Abriu uma janela do macOS pedindo para instalar as Ferramentas de Linha de
> Comando. Clique em **Instalar** e aceite os termos. São alguns minutos. Me
> avise quando terminar.

Elas trazem a toolchain do Swift 6 e o SDK do macOS que o build usa. Xcode
completo **não** é necessário. Confirme com `xcode-select -p` antes de
seguir. Não aceite "já instalei" sem conferir.

Uma instalação de um tempo atrás responde `xcode-select -p` carregando um Swift
mais velho do que o build precisa, e o que o build imprime então não nomeia nada
útil. Confira também a versão:

```bash
swift --version   # 6.0.3 ou mais novo
```

Abaixo de 6.0.3 elas precisam ser atualizadas, e isso é **PARE E PEÇA**. O build
recusa antes, dizendo a versão que achou e de qual toolchain ela veio.

### cmake

```bash
command -v cmake || brew install cmake
```

Só para compilar. Não é dependência de execução.

## 2. Clonar e compilar

```bash
git clone <url-do-repositório> nevertype && cd nevertype
bash scripts/build-app.sh
```

`build-app.sh` clona o whisper.cpp num commit fixo, confere, compila estático e
assina. **Leva alguns minutos na primeira vez**. É normal, não interrompa.

## 3. O modelo

São 547 MB e ele **não vem no app**. O `install.sh` interrompe a instalação antes de abrir o app se ele estiver faltando.

```bash
bash scripts/setup-bench.sh   # baixa três checkpoints do CDN da OpenAI e converte
bash scripts/fetch-model.sh   # valida e promove para o lugar definitivo
```

`setup-bench.sh` é a bancada de modelos, não só o instalador: exige **Homebrew**
(instala `whisper-cpp` por ele) e **python3** (cria um venv com torch em
`.cache/`), e baixa, converte e quantiza **três** modelos (turbo, medium e
small), não um. Demora; o tempo não foi medido. Se `brew` não existir, o script
para: instalar o Homebrew é decisão da pessoa. **Pergunte**.

### Se a rede bloquear o download

Acontece em rede corporativa. O sintoma clássico não é erro de conexão: é um
arquivo do tamanho errado, ou uma **página HTML de erro salva com nome de
modelo**. Por isso a validação confere o magic em hexadecimal, não a extensão.

Copiar de outra máquina que já tenha é um caminho válido, **mas o arquivo
precisa entrar pelo repositório**, nunca direto no destino:

```bash
mkdir -p models
cp /caminho/do/ggml-large-v3-turbo-q5_0.bin models/
cp /caminho/do/ggml-large-v3-turbo-q5_0.bin.sha256 models/
bash scripts/fetch-model.sh
```

Leve o arquivo `.bin` e o comprovante `.bin.sha256` gerado pelo setup. O
`fetch-model.sh` confere o magic, o tamanho mínimo de 400 MB e o SHA-256 antes
de instalar. O checksum local detecta arquivos alterados ou cópias incompletas;
ele não autentica quem forneceu o modelo. Use uma origem em que você confia.
Modelos antigos sem esse comprovante precisam ser reconstruídos com
`setup-bench.sh`, que reaproveita os checkpoints `.pt` válidos em cache.

## 4. Instalar e conceder permissões

Com o modelo instalado, compile e abra o app:

```bash
bash scripts/install.sh
```

O script sempre executa o build, instala em `/Applications`, verifica a
assinatura e abre o app. Ele recusa sistemas incompatíveis e falta de permissão
de escrita em `/Applications`. Nesse caso, peça ajuda a um administrador ou
combine a instalação em `~/Applications`. Os scripts `verify-install.sh` e
`update.sh` usam `/Applications`; em outro caminho, a verificação exige conferir
o app instalado e ditar uma frase.

Se você abriu o app antes de instalar ou substituir o modelo, encerre-o pelo
menu e abra novamente. O modelo é carregado apenas na inicialização. Executar
`install.sh` também encerra a instância anterior e abre a nova.

O app pede duas permissões ao abrir. **As duas exigem sua interação.**

### Microfone: PARE E PEÇA

> O macOS vai perguntar se o NeverType pode usar o microfone. Clique em
> **Permitir**. Sem isso não há áudio.

### Acessibilidade: PARE E PEÇA

Esta é a mais fácil de não notar, e é o modo de falha mais provável de uma
instalação nova. Sem ela o app não consegue inserir texto. Se a pessoa tentar
ditar mesmo assim, a gravação é bloqueada antes de capturar áudio, e um aviso
oferece abrir a página certa dos Ajustes. O ícone cortado, a linha
"Accessibility: missing" no menu e o `nevertype.log` repetem o diagnóstico.

> Abra **Ajustes do Sistema › Privacidade e Segurança › Acessibilidade** e
> **ligue o NeverType** na lista. Se ele não estiver lá, clique no **+** e escolha
> `/Applications/NeverType.app`.
>
> Isso é o que deixa o app enviar o comando de colar no cursor. Sem isso, tentar
> ditar abre um aviso em vez de gravar um áudio que não poderá ser inserido.
>
> Depois de ligar, tente a tecla outra vez. Se o macOS ainda disser que a
> permissão está ausente, **encerre o NeverType pelo menu da bandeja e abra de
> novo**.

Não continue sem que a pessoa confirme que fez.

## 5. Verificar

```bash
bash scripts/verify-install.sh
```

Confere app instalado, assinatura, processo vivo e modelo válido por bytes. Sai
com código diferente de zero e lista tudo que está errado de uma vez.

**Ele não verifica permissão, e não dá para verificar de fora.** O que interessa
não é o sistema dizer que concedeu, é o ditado inserir texto.

### O teste que fecha a instalação: PARE E PEÇA

> Abra um campo de texto qualquer: uma mensagem, um documento, a busca do
> Spotlight não.
>
> Segure o **⌘ da direita**, fale uma frase, e solte.
>
> O texto tem que aparecer onde o cursor está.

Se o texto aparecer, a instalação está concluída. Caso contrário, confira as
permissões no menu e o diagnóstico Model (segure Option ao abrir o menu).
Depois de instalar um modelo ausente, encerre e reabra o app antes de tentar
novamente.

## 6. Atualizar

Quando a pessoa disser *"atualiza pra mim"*, é um comando só:

```bash
cd nevertype && bash scripts/update.sh
```

Ele confere se há versão nova comparando três coisas: o commit **instalado**
(carimbado no bundle), o commit **local** e o **remoto**. E se já estiver tudo
igual não faz nada. Havendo diferença: traz, compila, instala e roda a
verificação.

**Ele para em seis casos. Em dois deles você também para:**

- **Alterações locais não commitadas.** Ele lista e recusa. **Não rode
  `git reset --hard` nem `git stash` por conta própria**. Commitar, guardar ou
  descartar é decisão da pessoa, e descartar apaga trabalho dela.
- **Pull que não é fast-forward.** A branch local divergiu da remota. Resolver
  isso sozinho pode perder commits dela. Pergunte.

Nos outros quatro a mensagem diz o que fazer: o diretório não é um clone git
(clone e rode `build-app.sh` e `install.sh`); o clone não tem remoto; o `fetch`
falhou (rede); a branch não acompanha nenhuma remota (ele dá o comando).

As permissões sobrevivem à atualização, porque o certificado de assinatura é
estável entre compilações da mesma máquina. É por isso que
`~/Library/Keychains/nevertype-signing.keychain-db` **nunca deve ser apagado**:
apagá-lo revoga a Acessibilidade e a pessoa precisa conceder tudo de novo.

Depois de atualizar, o teste continua sendo o mesmo: **ditar uma frase.**

A versão instalada também aparece no menu da bandeja, em "Version:", com o Option
segurado na hora de abrir o menu.

## Como usar

- Segure **⌘ direito**, fale, solte. O texto aparece onde o cursor está.
- **Dois toques rápidos** travam em mãos-livres; um toque encerra; **Esc** descarta.
- Qualquer tecla comum, ou Esc, durante o hold cancela e descarta o áudio.
- A pílula flutuante mostra o nível do microfone enquanto grava; se as barras não
  mexem, não está entrando som.
- O menu da bandeja tem histórico, escolha da tecla e vocabulário. "Clear
  History" apaga o texto guardado e o áudio do último ditado.
