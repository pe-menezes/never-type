# Inventário para tradução — 2026-08-29

> HEAD 0d7efbe. Decisão: repositório em inglês — interface do app, comentários,
> mensagens dos scripts e docs — com `README.pt-BR.md` como versão em português.
> `.vibeflow/` fica em português. Nada foi traduzido aqui; isto dimensiona,
> lista o que não pode mudar e propõe texto para as strings de interface.

## 1. Dimensionamento por arquivo

Contagem por `grep`: comentário = linha começando com `//` ou `#`; string = linha
não-comentário contendo aspas; mensagem de script = linha começando com
`echo`/`printf`/`info`/`ok`/`warn`/`fail`/`problem` ou continuação de `fail`;
doc = todas as linhas. Comentários no fim de linha de código (Tone.swift:60-66,
7 linhas) não entram na contagem.

### Docs públicos — 1 021 linhas, tudo em português

| Arquivo | Linhas | Tipo | Observação |
|---|---:|---|---|
| README.md | 219 | doc | Vira `README.md` (en) + `README.pt-BR.md` |
| CLAUDE.md | 90 | doc | Lido por agente; contém regras que citam textos de UI ("Modelo:", "⌘ direito") |
| docs/INSTALL.md | 204 | doc | Contém 4 blocos de fala literal para a pessoa (L59-61, L125-126, L134-141, L159-164) — o agente lê isso em voz alta; traduzir muda o que o usuário final ouve |
| docs/armadilhas.md | 291 | doc | Nome do arquivo em português (§3) |
| docs/escolha-do-modelo.md | 95 | doc | Nome em português (§3) |
| docs/inicializacao-com-o-sistema.md | 67 | doc | Nome em português (§3); cita a linha de menu `Modelo: … carga N ms · aquecimento N ms` |
| fixtures/README.md | 55 | doc | Exemplo de fala em português (L37-39) é o dado de teste do modelo — ver §5 |
| LICENSE | 21 | — | Já em inglês |
| .gitignore | 7 comentários | comentário | L1-2, 6, 9, 12, 20, 23 |

### Sources/ — 754 linhas de comentário, 150 linhas com string literal

| Arquivo | Comentário | UI | Log | Erro/estado | Chave, caminho, técnico |
|---|---:|---:|---:|---:|---:|
| Sources/NeverType/main.swift | 159 | 27 | 28 | 0 | 29 (inclui 9 `keyEquivalent: ""`) |
| Sources/NeverType/VocabularyWindow.swift | 25 | 9 | 0 | 0 | 11 (2 delas são o identificador "Vocabulário", acoplado ao título da aba) |
| Sources/NeverType/RecordingOverlay.swift | 92 | 0 | 0 | 0 | 1 (`overlayOrigin`) |
| Sources/NeverTypeCore/HotkeyMonitor.swift | 76 | 3 | 0 | 0 | 1 |
| Sources/NeverTypeCore/AudioRecorder.swift | 119 | 0 | 3 | 4 | 1 |
| Sources/NeverTypeCore/LoginItem.swift | 59 | 0 | 0 | 6 | 5 |
| Sources/NeverTypeCore/TextInjector.swift | 59 | 0 | 0 | 3 | 1 |
| Sources/NeverTypeCore/Transcriber.swift | 63 | 0 | 0 | 4 | 8 |
| Sources/NeverTypeCore/Tone.swift | 22 (+7 no fim de linha) | 0 | 0 | 0 | 4 |
| Sources/NeverTypeCore/TranscriptHistory.swift | 27 | 0 | 0 | 0 | 0 |
| Sources/NeverTypeCore/Vocabulary.swift | 30 | 0 | 0 | 0 | 2 |
| Package.swift | 16 | — | — | — | — |
| Sources/CWhisper/module.modulemap | 7 | — | — | — | — |
| **Total** | **754** | **39** | **31** | **17** | **63** |

As 138 strings do enunciado correspondem às 150 linhas com aspas menos as 12 que
são só `""`/`keyEquivalent`. Traduzível: 39 UI + 31 log + 17 erro = **87 strings**.
As 63 restantes são chave, caminho, símbolo SF, tag RIFF, regex ou API — ficam.

### Tests/ — 130 linhas de comentário, 93 títulos, ~53 mensagens de `#expect`

| Arquivo | Comentário | `@Suite`/`@Test` | Mensagem de `#expect` | Dado de teste em PT |
|---|---:|---:|---:|---|
| AudioRecorderTests.swift | 40 | 36 | 24 | nenhum textual |
| TextInjectorTests.swift | 22 | 10 | 4 | "o que estava lá antes", "texto ditado", "conteúdo importante", … (~12 literais) |
| LoginItemTests.swift | 16 | 10 | 4 | mensagens de erro de produção (§5) |
| ToneTests.swift | 8 | 7 | 9 | nenhum |
| TranscriberTests.swift | 32 | 9 | 6 | nenhum |
| TranscriptHistoryTests.swift | 6 | 8 | 4 | "primeira", "segunda", "segredo", "o que eu falei antes de fechar", … (~8) |
| VocabularyTests.swift | 6 | 13 | 2 | frases em português que exercitam o regex ("essa transcrição foi negada", "a família ia embora", "manda um PIX…", "o vibe flow e o fala flow") |
| **Total** | **130** | **93** | **53** | |

### scripts/ — 1 303 linhas; 307 de comentário, 204 de mensagem, 2 heredocs de texto

| Arquivo | Comentário | Mensagem | Heredoc / outro |
|---|---:|---:|---|
| scripts/atualizar.sh | 19 | 17 | — (nome em PT, §3) |
| scripts/bench.sh | 46 | 35 | cabeçalhos da tabela (`MODELO`, `FIXTURE`, `ÁUDIO`, `JANELAS`, `PAREDE`, `QUENTE`, `POR JANELA`, `DITADO ATÉ 30s`, `VEREDITO`, L164-165, L202) e vereditos coloridos (L216, L218) |
| scripts/build-app.sh | 108 | 41 | **L314 `NSMicrophoneUsageDescription`** — é texto que o macOS mostra no diálogo de permissão; UI, não script |
| scripts/fetch-model.sh | 6 | 6 | — |
| scripts/install.sh | 29 | 21 | heredoc L93-111 (17 linhas de texto) |
| scripts/record-fixture.sh | 16 | 15 | prompt interativo L55 (`Sobrescrever? [y/N]`) e L59 (`cancelado.`) |
| scripts/setup-bench.sh | 55 | 49 | — (nome em EN) |
| scripts/verificar-instalacao.sh | 28 | 20 | heredoc L110-123 (12 linhas) (nome em PT, §3) |
| **Total** | **307** | **204** | |

### Totais

| Bloco | Linhas a traduzir |
|---|---:|
| Docs públicos | 1 021 |
| Comentários em Sources/ + Package.swift + modulemap | 754 |
| Strings de UI, log e erro em Sources/ | 87 |
| Comentários e títulos em Tests/ | 223 (+53 mensagens de `#expect`, opcional) |
| Scripts: comentários + mensagens + heredocs | ~540 |
| .gitignore | 7 |
| **Total** | **~2 630 linhas** (mais ~50 de mensagens de teste se forem traduzidas) |

## 2. Identificadores que NÃO podem mudar sem migração

O app está instalado e em uso com histórico e vocabulário reais. O commit c97f01b
(FalaFlow → NeverType) mostrou o custo de mexer em nome amarrado a permissão.
Cada linha diz onde o identificador é definido, onde é lido, e o que quebra.

### Amarrados a permissão do macOS (TCC, BTM) — **nunca**

| Identificador | Definido | Lido | O que quebra se renomear |
|---|---|---|---|
| Bundle ID `com.nevertype.app` | build-app.sh:17 (`CFBundleIdentifier`, :305; `--identifier`, :338) | main.swift:207 (fallback); TCC (Microfone, Acessibilidade); BTM (login item, `SMAppService.mainApp`); domínio de UserDefaults | Perde Microfone, Acessibilidade e o login item; UserDefaults (`trigger`, `somDasAcoes`, `overlayOrigin`) voltam ao padrão. Backlog "Decidido e fechado" já veta |
| Identidade `NeverType Local Signing` | build-app.sh:23 (`IDENTITY`), :85 (`CN`) | build-app.sh:63 (`identity_present`), :338 (`--sign`); TCC ancora no `certificate leaf` (:7-12) | Certificado novo = requisito designado novo = Acessibilidade e Microfone revogados |
| Keychain `~/Library/Keychains/nevertype-signing.keychain-db` | build-app.sh:22 | build-app.sh:152-158, :162; README:185; CLAUDE.md:65; INSTALL.md:27, :192 | Sem o arquivo no caminho, `create_identity` roda (:155) e gera certificado novo → mesma revogação |
| Nome do bundle/executável `NeverType.app` / `NeverType` | Package.swift:39; build-app.sh:16, :293, :303-306 | LoginItem.swift:56 (guarda de caminho); install.sh:11, :47-54 (`pgrep -x`); verificar-instalacao.sh:14, :71; atualizar.sh:14; docs/inicializacao:60; INSTALL.md:136 | Guarda do login item recusa; scripts não acham o processo; TCC indexa o app pelo bundle |
| Caminho `/Applications/NeverType.app` (e `~/Applications/NeverType.app`) | install.sh:11; LoginItem.swift:65-66 | LoginItem, verificar-instalacao.sh, atualizar.sh; README:100, :152; INSTALL.md:136 | Login item recusa registrar; permissão pode não seguir o app (README:152) |

### Amarrados a dado do usuário em disco — **manter, ou migrar com código**

Tudo em `~/Library/Application Support/NeverType/` (base: main.swift:8-9;
Transcriber.swift:9-10; fetch-model.sh:12; install.sh:12; verificar-instalacao.sh:15).

| Identificador | Definido | Lido | O que quebra se renomear |
|---|---|---|---|
| Diretório `NeverType` em Application Support | main.swift:9; Transcriber.swift:10; fetch-model.sh:12; install.sh:12; verificar-instalacao.sh:15 | Tudo abaixo; README:98; INSTALL.md:28, :116 | Histórico, vocabulário, modelo (547 MB) e log ficam órfãos; o app abre "sem modelo" |
| `historico.json` | main.swift:162 | TranscriptHistory.swift:66 (`load`), :79 (`save`), :60 (`clear`) | O histórico real do Pedro some do menu (o arquivo antigo fica no disco, em texto claro, sem ninguém para apagá-lo). Teste usa nome próprio (TranscriptHistoryTests.swift:14) — não depende |
| `vocabulario.json` | main.swift:158 | Vocabulary.swift:92 (`load`), :104 (`save`) | Termos e substituições reais somem; arquivo antigo fica órfão. Teste usa nome próprio (VocabularyTests.swift:13) |
| `models/ggml-large-v3-turbo-q5_0.bin` | Transcriber.swift:6, :10; fetch-model.sh:10-13; install.sh:12-13; verificar-instalacao.sh:15; setup-bench.sh:23 | Transcriber.swift:79-85; scripts; INSTALL.md:111; TranscriberTests.swift:63-64 (`#expect` no caminho e no nome) | App não acha o modelo; 2 `#expect` quebram; 547 MB órfãos |
| `last.wav` | main.swift:9 | AudioRecorder.swift:176 (`AVAudioFile(forWriting:)`); TranscriptHistory.swift:27 (comentário) | Baixo: sobrescrito a cada ditado. Renomear deixa um `last.wav` antigo com voz da pessoa para trás |
| `nevertype.log` | main.swift:662 | main.swift:635-638, :667; docs/inicializacao:61 | Baixo: truncado a cada lançamento. O doc de medição cita o nome |
| `.instance.lock` | main.swift:647 | main.swift:648-652 (`flock`) | Baixo. Durante uma atualização, instância velha e nova com nomes diferentes não se veriam — duas rodando |
| `ultima-transcricao.txt` (legado) | main.swift:165 | main.swift:171-173 (só remove) | Se a string mudar, o arquivo legado com a última transcrição da versão anterior deixa de ser apagado nas máquinas onde ainda existe |

### Chaves de UserDefaults (domínio `com.nevertype.app`)

| Chave | Definida | Lida | O que quebra |
|---|---|---|---|
| `trigger` | main.swift:422 | main.swift:223 (restaura), :441 (grava) | Tecla escolhida volta para ⌘ direito |
| `somDasAcoes` (nome em PT) | main.swift:86 | main.swift:91-92 | Preferência de som volta para "ligado". Única chave em português; renomear exige ler a antiga e gravar a nova uma vez |
| `overlayOrigin` | RecordingOverlay.swift:220 | RecordingOverlay.swift:307, :342 | Pílula volta ao canto inferior direito |

### Chave do Info.plist e outros acoplamentos

| Identificador | Definido | Lido | O que quebra |
|---|---|---|---|
| `NeverTypeCommit` | build-app.sh:310 | main.swift:430 (menu "Versão"); atualizar.sh:56, :88 | Três lugares; renomear um só faz o menu mostrar "desconhecida" e o atualizar.sh recompilar sempre |
| Prefixo de log `nevertype: ` | main.swift:633; AudioRecorder.swift:373 | Quem lê o log; docs/inicializacao:62 cita a linha "modelo:" | Baixo; manter |
| Fila `com.nevertype.audio-io` | AudioRecorder.swift:284 | Só depuração | Nada |
| Pasteboard de teste `com.nevertype.tests.*`; domínio `com.nevertype.tests` | TextInjectorTests.swift:16; LoginItemTests.swift:17 | Só testes | Nada |
| Idioma `"pt"` | Transcriber.swift:184 | whisper | Não é texto: é comportamento. Fica, e o README em inglês passa a dizê-lo |
| Identificador de aba `"Vocabulário"` | VocabularyWindow.swift:59 (`title`), :79, :97, :115, :121 | VocabularyWindow.swift:129 e :171 comparam a string | Traduzir o título sem as duas comparações faz `isTerms` devolver `false` para a aba de termos — a UI edita a lista errada. Os ids de coluna `"termo"`, `"de"`, `"para"` (:60, :66, :160, :176) idem, mas são internos e podem ficar |

### Nomes que INSTALL.md e CLAUDE.md mandam digitar

`bash scripts/build-app.sh`, `bash scripts/install.sh`, `bash scripts/verificar-instalacao.sh`,
`bash scripts/setup-bench.sh`, `bash scripts/fetch-model.sh`, `bash scripts/atualizar.sh`,
`scripts/record-fixture.sh <nome>`, `cp … models/`, `git clone … nevertype && cd nevertype`,
`brew install cmake`, `xcode-select --install`, `pkill -x NeverType`, `open build/NeverType.app`,
`rm -f ~/Library/Application Support/NeverType/nevertype.log`, e o item de menu
"Sair do NeverType" (INSTALL.md:141 "encerre pelo menu"). Os dois scripts em
português estão em §3; o resto já é inglês.

Mensagens de erro do app que citam nomes de script — permanecem válidas se os
scripts não forem renomeados: Transcriber.swift:60, :62 (`scripts/fetch-model.sh`),
LoginItem.swift:103 (`bash scripts/install.sh`).

## 3. Nomes de arquivo em português e todas as referências

Grep no repositório inteiro (menos `.git/`, `.build/`), 29/08/2026.

### `docs/armadilhas.md` — 9 referências

| Arquivo:linha | Contexto |
|---|---|
| CLAUDE.md:16 | lista de leitura obrigatória |
| README.md:201 | link Markdown + texto |
| README.md:213 | tabela |
| docs/INSTALL.md:14 | "Leia `docs/armadilhas.md`" |
| docs/escolha-do-modelo.md:95 | "Ver `docs/armadilhas.md`" |
| .vibeflow/index.md:98 | Key Files |
| .vibeflow/prds/instalacao-por-agente.md:88 | |
| .vibeflow/specs/instalacao-por-agente.md:175 | |
| .vibeflow/specs/devolucao-observada-do-pasteboard.md:212 | |

### `docs/escolha-do-modelo.md` — 3 referências + 2 fantasmas

| Arquivo:linha | Contexto |
|---|---|
| README.md:214 | tabela |
| .vibeflow/index.md:97 | Key Files |
| .vibeflow/backlog.md:289 | A3, cita `:82` |
| scripts/bench.sh:4 | **`docs/decisao-modelo.md`** — nome que não existe |
| scripts/bench.sh:230 | **`docs/decisao-modelo.md`** — idem |

### `docs/inicializacao-com-o-sistema.md` — 3 referências, nenhuma pública

| Arquivo:linha | Contexto |
|---|---|
| .vibeflow/backlog.md:135 | L2 |
| .vibeflow/specs/abrir-com-o-sistema.md:72 | DoD 6 |
| .vibeflow/specs/abrir-com-o-sistema.md:85 | Escopo |

### `scripts/atualizar.sh` — 2 referências

| Arquivo:linha | Contexto |
|---|---|
| docs/INSTALL.md:174 | comando que o agente roda |
| Sources/NeverType/main.swift:427 | doc comment de `buildCommit` |

### `scripts/verificar-instalacao.sh` — 5 referências

| Arquivo:linha | Contexto |
|---|---|
| README.md:48 | bloco de comando |
| docs/INSTALL.md:148 | bloco de comando |
| scripts/atualizar.sh:85 | chamada |
| .vibeflow/specs/instalacao-por-agente.md:40 | DoD 3 |
| .vibeflow/specs/instalacao-por-agente.md:65 | Escopo |

### Dados do usuário com nome em português (não renomear — §2)

`historico.json` (main.swift:162; TranscriptHistoryTests.swift:14; backlog.md:75, :96, :241),
`vocabulario.json` (main.swift:158; VocabularyTests.swift:13),
`ultima-transcricao.txt` (main.swift:165; TranscriptHistory.swift:16; backlog.md:246).

### Exemplos de nome de fixture

`01-fala-normal`, `02-termos-tecnicos`, `03-frase-curta` (fixtures/README.md:9-11;
record-fixture.sh:10-12; escolha-do-modelo.md:90 usa `01-normal`). São arquivos
locais não versionados; os exemplos podem ser traduzidos livremente.

### Recomendação

Renomear os cinco (ex.: `docs/pitfalls.md`, `docs/model-choice.md`,
`docs/open-at-login.md`, `scripts/update.sh`, `scripts/verify-install.sh`): 22
referências reais para atualizar, mais as 2 fantasmas de bench.sh que precisam
mudar de qualquer jeito. Nenhum tem dado ou permissão amarrada. Único custo
externo: um agente seguindo um INSTALL.md antigo chamaria `scripts/atualizar.sh`
— um shim de uma linha por um ciclo resolve, se valer a pena.

## 4. Strings de interface, log e erro em Sources/ — texto atual e proposta

Coluna "Doc": onde a string atual é citada fora do código (README, CLAUDE.md,
docs/, scripts, backlog, spec). Traduzir a string exige atualizar essas linhas
na mesma etapa, senão o doc descreve um item de menu que não existe mais.
"Teste": `#expect` que compara a string de produção (quebra se mudar).

### Menu da bandeja e status — main.swift

| Linha | Texto atual | Proposta | Doc / Teste |
|---|---|---|---|
| 22 | `modelo ainda não carregado` | `model not loaded yet` | — |
| 41 | `Metal` / `CPU (LENTO)` | `Metal` / `CPU (SLOW)` | docs/inicializacao:52 |
| 42 | `\(gpu) · carga \(n) ms · aquecimento \(n) ms` | `\(gpu) · load \(n) ms · warm-up \(n) ms` | docs/inicializacao:52; specs/abrir-com-o-sistema.md:74; backlog.md:24 |
| 43 | ` (AQUECIMENTO FALHOU)` | ` (WARM-UP FAILED)` | patterns/falha-alta.md:95 |
| 141 | `carregando modelo…` | `loading model…` | — |
| 282 | `NeverType` (accessibilityDescription) | manter | — |
| 296 | `FF` (título fallback) | `NT` | resíduo de FalaFlow |
| 430 | `desconhecida` (versão) | `unknown` | — |
| 504 | `Trigger: \(label) (segure e fale)` | `Trigger: \(label) (hold and speak)` | — |
| 505 | `  dois toques travam · toque para encerrar · Esc descarta` | `  double-tap locks · tap to finish · Esc discards` | — |
| 507 | `Tecla` | `Key` | README:88; INSTALL.md:204; backlog.md:185, :197 |
| 518 | `Sons` | `Sounds` | README:90; backlog.md:185 |
| 526 | `Vocabulário…` | `Vocabulary…` | README:92; INSTALL.md:204 |
| 530 | `Vocabulário (\(n) termos, \(n) trocas)…` | `Vocabulary (\(n) terms, \(n) replacements)…` | README:92-93 |
| 535 | `Microfone: ok` / `faltando` | `Microphone: ok` / `missing` | patterns/estado-consultado.md:32 (histórico) |
| 536 | `Acessibilidade: ok` / `faltando` | `Accessibility: ok` / `missing` | — |
| 537 | `Modelo: \(status)` | `Model: \(status)` | docs/inicializacao:52; backlog.md:24; spec:74 |
| 538 | `Versão: \(commit)` | `Version: \(commit)` | INSTALL.md:197 |
| 541 | `Copiar última transcrição` | `Copy last transcription` | README:83-84; main.swift:385 (log cita) |
| 548 | `Histórico (\(n))` | `History (\(n))` | README:95; INSTALL.md:204 |
| 552 | `\(HH:mm)  \(prévia)` | manter formato | — |
| 560 | `Limpar histórico` | `Clear history` | backlog.md:245 |
| 569 | `Abrir Ajustes de Acessibilidade…` | `Open Accessibility Settings…` | — |
| 576 | `Abrir com o sistema` | `Open at Login` (termo da Apple) | README:100; docs/inicializacao (título); spec:170; backlog F1 |
| 584 | `  desativado em Itens de Início de Sessão` | `  turned off in Login Items` | spec:171 |
| 585 | `Abrir Itens de Início de Sessão…` | `Open Login Items…` | — |
| 591 | `Sair do NeverType` | `Quit NeverType` | INSTALL.md:141 ("encerre pelo menu") |

### Janela de vocabulário — VocabularyWindow.swift

| Linha | Texto atual | Proposta | Doc / Teste |
|---|---|---|---|
| 51 | `NeverType · Vocabulário` | `NeverType · Vocabulary` | — |
| 59, 129, 171 | `Vocabulário` (título da aba **e** identificador comparado) | `Vocabulary` nos três lugares juntos | — |
| 60 | `Termo que o modelo deve esperar` | `Term the model should expect` | — |
| 61 | `Enviesa o modelo a ouvir estas palavras. Não garante nada, mas também não estraga nada — use para palavra que às vezes é legítima.` | `Nudges the model toward hearing these words. Guarantees nothing, breaks nothing — use for a word that is sometimes legitimate.` | README:132-137 descreve |
| 65 | `Substituições` | `Replacements` | README:135 |
| 66 | `Saiu` / `Deveria ser` | `Came out as` / `Should be` | — |
| 67 | `Troca literal, SEMPRE. Só para o que nunca é certo (vibe flow → vibeflow). Palavra que às vezes é legítima: use a frase inteira, ou a aba Vocabulário.` | `Literal replacement, ALWAYS. Only for what is never right (vibe flow → vibeflow). For a word that is sometimes legitimate, use the whole phrase, or the Vocabulary tab.` | — |
| 112, 118 | `+` / `–` | manter | — |

### Rótulos da tecla — HotkeyMonitor.swift

| Linha | Texto atual | Proposta | Doc / Teste |
|---|---|---|---|
| 140 | `⌘ direito` | `Right ⌘` | README:62, :88; CLAUDE.md:3; INSTALL.md:162, :201; install.sh:108; verificar-instalacao.sh:118; docs/inicializacao:38; backlog. Teste AudioRecorderTests.swift:129 usa como caso negativo (`named("⌘ direito") == nil`) — continua passando |
| 141 | `⌥ direito` | `Right ⌥` | README:64, :88 |
| 142 | `⌃ direito` | `Right ⌃` | README:64, :88 |

### Estados e erros — LoginItem.swift

| Linha | Texto atual | Proposta | Doc / Teste |
|---|---|---|---|
| 34 | `ligado` | `on` | log main.swift:609 |
| 35 | `desligado` | `off` | — |
| 36 | `desativado nos Ajustes do Sistema` | `turned off in System Settings` | — |
| 101-104 | `esta cópia está em \(path), e só a instalada abre com o sistema. Rode: bash scripts/install.sh` | `this copy is at \(path), and only the installed one opens at login. Run: bash scripts/install.sh` | README:100-101. **Teste** LoginItemTests.swift:78-79 checa só `build/NeverType.app` e `scripts/install.sh` — seguro |
| 109 | `o macOS recusou o registro: \(erro)` | `macOS refused to register: \(erro)` | **Teste** LoginItemTests.swift:117 compara a string inteira |
| 127 | `o macOS recusou a baixa do registro: \(erro)` | `macOS refused to unregister: \(erro)` | **Teste** LoginItemTests.swift:125 compara a string inteira |

### Erros — TextInjector.swift, Transcriber.swift, AudioRecorder.swift

| Linha | Texto atual | Proposta | Doc / Teste |
|---|---|---|---|
| TextInjector.swift:92 | `texto vazio` | `empty text` | **Teste** TextInjectorTests.swift:177 |
| TextInjector.swift:126 | `não consegui escrever na área de transferência` | `could not write to the clipboard` | — |
| TextInjector.swift:145 | `não consegui enviar ⌘V` | `could not send ⌘V` | **Teste** TextInjectorTests.swift:47; patterns/nucleo-testavel.md:47 |
| Transcriber.swift:60 | `modelo não encontrado em \(path). Rode scripts/fetch-model.sh` | `model not found at \(path). Run scripts/fetch-model.sh` | Teste TranscriberTests.swift:75 checa `fetch-model.sh` — seguro; patterns/falha-alta.md:52 |
| Transcriber.swift:62 | `o arquivo em \(path) não é um modelo ggml completo (truncado ou corrompido). Rode scripts/fetch-model.sh` | `the file at \(path) is not a complete ggml model (truncated or corrupt). Run scripts/fetch-model.sh` | patterns/falha-alta.md:54 |
| Transcriber.swift:64 | `não consegui carregar o modelo na memória` | `could not load the model into memory` | — |
| Transcriber.swift:66 | `a transcrição falhou (código \(n))` | `transcription failed (code \(n))` | — |
| AudioRecorder.swift:40 | `não consegui converter de \(f) para 16 kHz mono` | `could not convert from \(f) to 16 kHz mono` | — |
| AudioRecorder.swift:42 | `falha ao alocar buffer de áudio` | `failed to allocate audio buffer` | — |
| AudioRecorder.swift:44 | `conversão de áudio falhou: \(e)` | `audio conversion failed: \(e)` | — |
| AudioRecorder.swift:52 | `\(n) Hz / \(n) canal(is)` | `\(n) Hz / \(n) channel(s)` | — |
| AudioRecorder.swift:369 | `gravação interrompida: \(erro)` | `recording interrupted: \(erro)` | — |
| AudioRecorder.swift:398 | `fim da gravação perdido: \(erro)` | `end of recording lost: \(erro)` | — |

### Log — main.swift (vai para stderr e `nevertype.log`)

| Linha | Texto atual | Proposta | Doc |
|---|---|---|---|
| 247 | `modelo: \(status)` | `model: \(status)` | docs/inicializacao:62 ("linha 'modelo:'") |
| 252 | `dispositivos do ggml: \(lista)` | `ggml devices: \(lista)` | — |
| 254 | `ATENÇÃO: sem Metal, a transcrição roda em CPU e fica ~11x mais lenta.` | `WARNING: without Metal, transcription runs on the CPU and is ~11x slower.` | — |
| 261 | `pronto. trigger: \(label)` | `ready. trigger: \(label)` | — |
| 270 | `SEM BOTÃO no status item — o ícone não tem onde ser desenhado` | `NO BUTTON on the status item — nowhere to draw the icon` | — |
| 283 | `símbolo '\(s)' não carregou` | `symbol '\(s)' did not load` | — |
| 297-298 | `vermelho` / `padrão`; `ícone → \(s) (\(tint)), template=…, largura=…` | `red` / `default`; `icon → \(s) (\(tint)), template=…, width=…` | — |
| 308 | `microfone não autorizado — ditado ignorado` | `microphone not authorized — dictation ignored` | — |
| 318 | `falha ao iniciar gravação: \(erro)` | `failed to start recording: \(erro)` | — |
| 333 | `gravado: \(n) amostras (\(s) s)` | `recorded: \(n) samples (\(s) s)` | — |
| 341, 344 | `transcrito em \(ms) ms → \(texto)` | `transcribed in \(ms) ms → \(texto)` | backlog.md:106 lê estes números |
| 342 | `substituições aplicadas → \(texto)` | `replacements applied → \(texto)` | — |
| 352 | `TRANSCRIÇÃO FALHOU: \(motivo)` | `TRANSCRIPTION FAILED: \(motivo)` | patterns/falha-alta.md:77 |
| 361 | `mãos-livres travado. Toque no \(label) para transcrever, Esc para descartar.` | `hands-free locked. Tap \(label) to transcribe, Esc to discard.` | — |
| 367 | `cancelado: tecla comum pressionada durante o hold` | `cancelled: regular key pressed during the hold` | — |
| 374 | `transcrição vazia — nada a inserir` | `empty transcription — nothing to insert` | — |
| 385 | `campo de senha em foco — não inseri. O texto está no menu, em "Copiar última transcrição".` | `secure input is on — did not insert. The text is in the menu, under "Copy last transcription".` | Cita o item 541. A proposta corrige o nome errado (D3) — decisão: traduzir literal ou aproveitar |
| 389 | `não consegui inserir: \(motivo). O texto está no menu.` | `could not insert: \(motivo). The text is in the menu.` | — |
| 442 | `trigger agora é \(label)` | `trigger is now \(label)` | — |
| 447 | `sons: ligados` / `desligados` | `sounds: on` / `off` | — |
| 452 | `histórico apagado` | `history cleared` | — |
| 463 | `última transcrição copiada` | `last transcription copied` | — |
| 495 | `Acessibilidade não concedida: o trigger global não vai funcionar.` | `Accessibility not granted: the global trigger will not work.` | — |
| 609 | `abrir com o sistema: \(estado)` | `open at login: \(estado)` | — |
| 615 | `não consegui mudar 'abrir com o sistema': \(motivo)` | `could not change 'open at login': \(motivo)` | — |
| 633 | prefixo `nevertype: ` | manter | AudioRecorder.swift:373 igual |

### Fora de Sources/, mas é interface do macOS

| Onde | Texto atual | Proposta |
|---|---|---|
| build-app.sh:314 (`NSMicrophoneUsageDescription`) | `O NeverType grava sua voz para transcrever localmente. Nenhum áudio sai da sua máquina.` | `NeverType records your voice to transcribe it locally. No audio ever leaves your Mac.` |

## 5. O que NÃO traduzir, e por quê

1. **Tudo em §2.** Bundle ID, identidade e keychain de assinatura, nome do bundle
   e do executável, diretório em Application Support, `historico.json`,
   `vocabulario.json`, `ultima-transcricao.txt`, `last.wav`, `nevertype.log`,
   `.instance.lock`, as três chaves de UserDefaults (inclusive `somDasAcoes`),
   `NeverTypeCommit`. Dois deles têm nome em português e ficam mesmo assim:
   renomear `historico.json`/`vocabulario.json` custa código de migração para um
   ganho que nenhum usuário vê. Se um dia for feito, é tarefa própria, com
   migração e teste.
2. **`.vibeflow/`** — decisão do Pedro. Mas as citações de strings de UI que
   moram lá (backlog.md:24, :185, :245; specs/abrir-com-o-sistema.md:74, :170-171;
   patterns/falha-alta.md:52-54, :77, :95; patterns/nucleo-testavel.md:47;
   patterns/estado-consultado.md:32) vão passar a citar texto que não existe.
   Não é problema de tradução, é envelhecimento normal de doc interno — anotar,
   não bloquear.
3. **`"pt"` em Transcriber.swift:184** — é comportamento, não texto. O README em
   inglês passa a declará-lo (auditoria B1). Tornar configurável é feature.
4. **Dados de teste em português que exercitam o próprio idioma:**
   VocabularyTests.swift:52-53 ("transcrição"/"transação"), :60-61 ("PIX/Pix/pix"),
   :70-71 ("a família ia embora" — fronteira de palavra com acento, o caso que
   motivou o `\b`), :78-80, :100-104 ("vibe flow", "fala flow"). O app só
   transcreve português; os casos são reais. Manter os dados; traduzir só o
   título do `@Test` e o comentário. O mesmo vale para os textos-dado de
   TextInjectorTests e TranscriptHistoryTests ("conteúdo original da pessoa",
   "o que eu falei antes de fechar") — podem ficar ou virar inglês, sem efeito.
5. **Os 4 `#expect` que comparam mensagem de produção** precisam mudar **junto**
   com a string, no mesmo commit, senão a suíte fica vermelha:
   - LoginItemTests.swift:117 ↔ LoginItem.swift:109
   - LoginItemTests.swift:125 ↔ LoginItem.swift:127
   - TextInjectorTests.swift:47 ↔ TextInjector.swift:145
   - TextInjectorTests.swift:177 ↔ TextInjector.swift:92
   Seguros (checam fragmento não traduzível ou caso negativo):
   LoginItemTests.swift:78-79, TranscriberTests.swift:75, AudioRecorderTests.swift:129,
   TranscriberTests.swift:63-64.
6. **Nomes de símbolo, tag e API**: `mic`/`mic.fill`/`mic.slash` (SF Symbols),
   `RIFF`/`WAVE`/`fmt `/`data`, `6c6d6767`, `org.nspasteboard.ConcealedType`,
   `AXTrustedCheckOptionPrompt`, a URL `x-apple.systempreferences:…`, `HH:mm`,
   os ids de coluna `termo`/`de`/`para` (internos; se traduzir, mudar :60, :66,
   :160, :176 juntos).
7. **Cabeçalhos de tabela e vereditos coloridos do bench.sh** (L164-165, L202,
   L216, L218) podem ser traduzidos, mas são saída lida só pelo Pedro ao
   preencher o doc de decisão — prioridade baixa.
8. **Mensagens de `#expect` (53 linhas) e títulos de `@Test`/`@Suite` (93)**:
   traduzir é seguro (swift-testing usa o nome da função como identidade; o
   título é só exibição). Se o critério é "repo em inglês", entram; se é
   "o que alguém de fora lê", são a parte de menor retorno dos ~2 630.

### Decisões que a etapa 2 precisa tomar antes de começar

- Renomear os 5 arquivos de §3 ou não (recomendação: sim, com as 22 + 2 refs).
- `Abrir com o sistema` → `Open at Login` (termo da Apple) ou tradução literal.
- Aproveitar a tradução de main.swift:385 e TextInjector.swift:17-18 para corrigir
  "campo de senha em foco" (auditoria K29/K112), ou traduzir literal e deixar o
  conserto para o D3. Misturar conserto com tradução contraria o "nenhum conserto"
  deste turno — mas na etapa 2 é a hora mais barata.
- Traduzir ou não os 4 blocos de fala literal do INSTALL.md (L59-61, L125-126,
  L134-141, L159-164): o agente os lê para a pessoa, então o idioma deles é o
  idioma do usuário final, não do repositório. Um README.pt-BR.md não cobre isso.

