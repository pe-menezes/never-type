<p align="center">
  <img src="assets/NeverTypeIcon.svg" width="112" height="112" alt="Logo do NeverType">
</p>

<h1 align="center">NeverType</h1>

<p align="center">
  Ditado por voz local no macOS.<br>
  <sub>Áudio, modelo e transcrição ficam no seu Mac.</sub>
</p>

<p align="center"><a href="README.md">English</a></p>

<p align="center">
  <a href="https://github.com/pe-menezes/never-type/actions/workflows/ci.yml"><img src="https://github.com/pe-menezes/never-type/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

Segure o **⌘ direito**, fale em português e solte para colar a transcrição no
cursor. O NeverType fica na barra de menus e transcreve no seu Mac usando
Whisper, sem acesso à rede durante o uso.

Ditados curtos mediram cerca de **600 ms** com o modelo carregado em um MacBook
Pro M4 Pro. A [comparação de modelos](docs/model-choice.md) detalha as medições e
o que foi avaliado.

## Recursos

- Segure para gravar ou dê dois toques para falar com as mãos livres. Mais um
  toque encerra; Esc descarta a gravação.
- Escolha pelo menu um modificador compatível, Fn ou um botão extra do mouse.
  Uma segunda tecla opcional inicia a gravação com as mãos livres com um toque.
- Um indicador flutuante mostra a atividade da gravação e o progresso da
  transcrição. Clique nele para abrir o menu, inclusive em apps em tela cheia.
- Copie transcrições recentes, adicione dicas de vocabulário e substituições de
  texto ou ative a abertura junto com o sistema.

Aguarde a transcrição terminar antes de iniciar outro ditado.

A [referência](docs/reference.md) detalha os controles, teclas aceitas e ajustes.

## Requisitos

- Mac com Apple Silicon e macOS 14 ou mais recente.
- Swift 6.0.3 ou mais recente, fornecido pelo Command Line Tools do Xcode ou Xcode.
- `cmake` para compilar. A preparação dos modelos também exige Homebrew e Python 3.
- O modelo Whisper de 547 MB, armazenado separadamente do app.

## Instalar

O NeverType atualmente distribui o código-fonte. A instalação compila o app na
sua máquina e cria um certificado local de assinatura.

Com os pré-requisitos instalados:

```bash
git clone https://github.com/pe-menezes/never-type.git
cd never-type
bash scripts/setup-bench.sh  # baixa dependências e converte três modelos
bash scripts/fetch-model.sh  # instala o modelo usado pelo NeverType
bash scripts/install.sh     # compila, assina, instala e abre o app
```

A preparação pode demorar e baixa mais do que os 547 MB do modelo final. Se você
já tem um arquivo de modelo compatível, o
[guia de instalação](docs/INSTALL.pt-BR.md#3-o-modelo) explica como usá-lo.

Conceda **Microfone** e **Acessibilidade** quando o macOS pedir e dite em um campo
de texto para verificar a instalação. O [guia de instalação](docs/INSTALL.pt-BR.md)
traz o roteiro completo, solução de problemas e atualização; um agente de código
também pode segui-lo.

## Privacidade

O app instalado não faz requisições de rede. Os scripts de compilação,
preparação dos modelos e atualização baixam código-fonte, dependências e modelos
quando você os executa.

O NeverType guarda as últimas 30 transcrições, o áudio do último ditado, seu
vocabulário e um log de diagnóstico em
`~/Library/Application Support/NeverType/`, sem criptografia própria do app.
O log registra tempo e tamanho da transcrição, sem o texto. **Clear History**
apaga as transcrições e o áudio armazenados.

A inserção usa a área de transferência. Por padrão, o conteúdo anterior é
restaurado após 0,6 s, desde que a área de transferência não tenha mudado nesse
intervalo. Se a colagem automática for bloqueada, a transcrição fica na área de
transferência para colagem manual. O texto ditado é marcado como oculto, mas
gerenciadores que ignoram essa marca podem guardá-lo. Copiar explicitamente um
item do histórico deixa o texto na área de transferência.

A afirmação sobre rede se baseia em inspeção manual do código; o CI não a
verifica. A [referência](docs/reference.md#the-check-behind-no-network-at-run-time)
documenta as verificações e seus limites.

## Limitações

- O idioma configurado é português. Usar outro idioma exige alterar o código e
  recompilar; a qualidade fora do português não foi medida.
- Gravações mais longas levam mais tempo para transcrever: 404 s de fala mediram
  cerca de 13 s. O indicador flutuante mostra o progresso durante a transcrição.
- Os modos de microfone Bluetooth podem reduzir a qualidade do áudio. Use o
  microfone do Mac se as gravações com o fone produzirem resultados ruins.
- Outro código executando como seu usuário pode usar o certificado local para
  se passar pelo NeverType e herdar suas permissões. Veja a seção de
  [assinatura](docs/reference.md#signing-and-what-it-costs).

## Desenvolvimento

```bash
bash scripts/build-app.sh  # compila a dependência nativa whisper.cpp e o app
swift build && swift test # swift-testing
```

O diretório gerado `vendor/` é necessário antes de executar SwiftPM diretamente.
Os testes de integração com modelo e áudio são condicionais; uma execução verde
sem esses arquivos não exercita a transcrição.

- [Referência técnica](docs/reference.md): arquitetura, controles e armazenamento.
- [Escolha do modelo](docs/model-choice.md): medições de qualidade e latência.
- [Problemas encontrados](docs/pitfalls.md): falhas e suas correções.
- [Abertura com o sistema](docs/launch-at-login.md): medições de inicialização.
- [Áudios de avaliação](fixtures/README.md): como gravar amostras para testes locais.

## Licença

MIT. Depende do [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) e do
modelo Whisper da OpenAI (MIT, código e pesos).
