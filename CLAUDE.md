# NeverType

Ditado por voz com transcrição local no macOS, só em português. Segurar a tecla
(⌘ direito por padrão; ⌥ ou ⌃ direito pelo menu) grava, soltar transcreve, dois
toques travam em mãos-livres, e o texto é inserido onde o cursor estiver.
**Nenhuma chamada de rede em tempo de uso** — é a restrição que justifica o
projeto existir, e há check de DoD verificando isso no código e no binário.

App de menu bar acessório (sem Dock; as únicas janelas são a pílula flutuante e
a do vocabulário). macOS 14+, Apple Silicon.
Swift 6 com concorrência estrita, SwiftPM, **sem Xcode** — só Command Line Tools.

## Antes de escrever código, leia

1. `.vibeflow/index.md` — estrutura, orçamento por tarefa, dívidas conhecidas
2. `.vibeflow/conventions.md` — convenções e a seção **Don'ts**
3. Os pattern docs relevantes em `.vibeflow/patterns/` (são oito)
4. `docs/armadilhas.md` — os erros já cometidos, com o custo medido

O quarto não é opcional. Vários defeitos deste projeto **passariam em revisão de
código** e só apareceram rodando — e a maioria fazia o programa relatar que
estava tudo bem enquanto não estava.

## Regras que mais pegam quem chega agora

- **Verifique o efeito, não a intenção.** Procurar palavra em log não prova que
  algo aconteceu: um log de execução em CPU contém 37 linhas com "metal". Enumere
  o dispositivo, compare os bytes, meça de fora do processo.
- **Magic number se compara em hex**, e nunca sozinho. `head -c 4` de um modelo
  ggml é `lmgg`, não `ggml` — e um arquivo truncado tem os bytes certos.
- **Isolamento de concorrência vai no tipo.** `MainActor.assumeIsolated` só onde
  a API documenta main thread **e** a ordem dos eventos importa. Closure escrita
  dentro de método `@MainActor` **herda** o isolamento por inferência — isso
  derrubou o app duas vezes.
- **Estado do sistema é consultado, nunca guardado.** Permissão muda por fora.
- **swift-testing, nunca XCTest.** XCTest exige Xcode completo.
- **Todo caminho de falha precisa ser exercitável.** Se não dá para exercitar,
  não conta como implementado — em quatro auditorias, nenhum caminho de falha não
  exercitado estava correto.
- **Comentário explica por quê e o que quebrou antes**, com o número medido. Não
  explica o que o código faz.

## Comandos

**Primeira coisa, num clone novo:**

```bash
bash scripts/build-app.sh     # compila o whisper.cpp estático em vendor/
```

`vendor/` não é versionado (são binários), e sem ele o `swift build` falha com
`could not build Objective-C module 'CWhisper'` — mensagem que não diz a causa.
O script clona o whisper.cpp num commit fixo, confere, compila e guarda o
resultado. Leva alguns minutos na primeira vez, ~1 s nas seguintes.

Depois disso:

```bash
swift build && swift test     # 86 testes
bash scripts/install.sh       # instala em /Applications
bash scripts/bench.sh         # mede latência e qualidade por modelo
```

Fora do controle de versão e reconstruíveis: `models/` (1,2 GB em disco: os três
modelos da bancada; o app carrega um, de 547 MB), `vendor/` (whisper.cpp
estático), `fixtures/` (gravações), `bench-out/`, `.cache/`, `build/`.

**Nunca apague** `~/Library/Keychains/nevertype-signing.keychain-db` — apagá-lo
revoga a permissão de Acessibilidade e o usuário precisa reconceder.

## Idioma

Código e APIs em inglês. Comentários, mensagens de erro, interface e documentação
em **português**.

## Estado

Funciona ponta a ponta: ~600 ms por ditado com o modelo quente, 86 testes. Nunca
foi instalado por ninguém além do autor.

Falta uma coisa: **pacote distribuível sem compilar** — cada instalação ainda
compila na própria máquina. Abrir no login, histórico de transcrições e
vocabulário customizado saíram da lista: estão implementados (`LoginItem.swift`,
`TranscriptHistory.swift`, `Vocabulary.swift`), com teste, e o que falta neles é
conferência em uso real — está anotado item a item em `.vibeflow/backlog.md`.

## Risco conhecido e aceito

O app é assinado com certificado local, e o macOS amarra Microfone e
Acessibilidade a esse certificado — quem já executa código na máquina pode
usá-lo. É inerente a certificado local; a alternativa faz o macOS revogar a
permissão a cada build. Ver a seção Segurança do README antes de mexer em
`scripts/build-app.sh`.
