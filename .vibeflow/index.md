# Project: NeverType
> Analyzed: 2026-08-28
> Stack: Swift 6 (SwiftPM, sem Xcode) + whisper.cpp estático + shell. macOS 14+, Apple Silicon.
> Type: aplicativo nativo de menu bar (agente, sem janela) com ferramental de build e medição
> Suggested budget: ≤ 4 files per task

## Structure

Ditado por voz com transcrição local. Segurar ⌘ direito grava, soltar transcreve
e o texto é inserido onde o cursor estiver. Nenhuma chamada de rede em uso.

A lógica vive numa biblioteca (`NeverTypeCore`) porque um alvo executável do
SwiftPM não é importável por um alvo de teste; o executável é só a casca que
monta a menu bar. O whisper.cpp é compilado estático em `vendor/` pelo próprio
script de build — linkagem dinâmica é incompatível com o hardened runtime, que é
o que fecha injeção de código num processo que detém Acessibilidade.

Os artefatos pesados (`models/`, `vendor/`, `fixtures/`,
`bench-out/`, `.cache/`, `build/`) ficam fora do controle de versão.

## Structural Units

- **`Sources/NeverTypeCore/`** — captura e conversão de áudio, tecla global (com
  a trava de mãos-livres e as três teclas oferecidas), transcrição, inserção de
  texto, vocabulário, histórico de transcrições, tons do retorno auditivo e login
  item. É o que tem teste.
- **`Sources/NeverType/`** — `NSApplication` acessória, ícone de bandeja, painel
  flutuante de gravação, janela do vocabulário, ator dono do modelo. Orquestra,
  não decide.
- **`Sources/CWhisper/`** — module map apontando para `vendor/whisper`.
- **`Tests/NeverTypeCoreTests/`** — 81 testes em swift-testing.
- **`scripts/`** — bancada de latência, build e assinatura, instalação.
- **`docs/`** — armadilhas encontradas e a escolha do modelo, com os números.
- **`.vibeflow/`** — convenções e padrões extraídos do código.

## Pattern Registry

<!-- vibeflow:patterns:start -->
patterns:
  - file: patterns/nucleo-testavel.md
    tags: [testability, dependency-injection, module-boundaries, swiftpm, system-apis]
    modules: [Sources/NeverTypeCore/, Sources/NeverType/, Tests/NeverTypeCoreTests/]
  - file: patterns/falha-alta.md
    tags: [error-handling, observability, fail-fast, degradation, user-feedback]
    modules: [Sources/NeverTypeCore/, Sources/NeverType/, scripts/]
  - file: patterns/verificacao-estrutural.md
    tags: [verification, integrity, binary-formats, false-negatives, guards]
    modules: [Sources/NeverTypeCore/, scripts/]
  - file: patterns/isolamento-tipado.md
    tags: [concurrency, swift6, main-actor, actors, thread-safety]
    modules: [Sources/NeverTypeCore/, Sources/NeverType/]
  - file: patterns/estado-consultado.md
    tags: [state-management, permissions, staleness, system-apis, ui-refresh]
    modules: [Sources/NeverType/, Sources/NeverTypeCore/]
  - file: patterns/estado-do-usuario.md
    tags: [user-data, pasteboard, reversibility, privacy, side-effects]
    modules: [Sources/NeverTypeCore/, Sources/NeverType/]
  - file: patterns/scripts-shell.md
    tags: [shell, idempotency, build-scripts, cli, developer-experience]
    modules: [scripts/]
  - file: patterns/terceiros-pinados.md
    tags: [supply-chain, dependencies, integrity, build-security, provenance]
    modules: [scripts/, vendor/]
<!-- vibeflow:patterns:end -->

## Pattern Docs Available

- [`nucleo-testavel.md`](patterns/nucleo-testavel.md) — biblioteca separada do executável, e chamada de sistema entrando por parâmetro para o teste poder trocá-la
- [`falha-alta.md`](patterns/falha-alta.md) — degradação de desempenho é erro; erro que o usuário não vê é erro que não existe
- [`verificacao-estrutural.md`](patterns/verificacao-estrutural.md) — verificar por bytes, campos e checksums, nunca por palavra em log
- [`isolamento-tipado.md`](patterns/isolamento-tipado.md) — contrato de thread declarado no tipo, com `assumeIsolated` só onde a ordem importa mais que a pureza
- [`estado-consultado.md`](patterns/estado-consultado.md) — permissão e área de transferência consultadas na hora, nunca copiadas para variável
- [`estado-do-usuario.md`](patterns/estado-do-usuario.md) — o que se toca, se devolve, inclusive no caminho de erro
- [`scripts-shell.md`](patterns/scripts-shell.md) — o esqueleto comum aos seis scripts
- [`terceiros-pinados.md`](patterns/terceiros-pinados.md) — commit fixo, checksum conferido, rigor proporcional ao impacto

## Key Files

| Arquivo | Papel |
|---|---|
| `Package.swift` | Divisão em 4 alvos e as flags de link estático do whisper |
| `Sources/NeverType/main.swift` | Delegate, ciclo do ditado, ator do modelo, trava de instância |
| `Sources/NeverTypeCore/AudioRecorder.swift` | `Resampler`, `RecordingSink` e o gravador; fila serial dona do estado |
| `Sources/NeverTypeCore/Transcriber.swift` | `ModelStore` e a ponte com o whisper.cpp; enumeração de backends |
| `Sources/NeverTypeCore/TextInjector.swift` | Inserção via área de transferência, com retrato e devolução |
| `Sources/NeverTypeCore/HotkeyMonitor.swift` | O gatilho: push-to-talk, trava de mãos-livres por duplo toque, as três teclas oferecidas |
| `Sources/NeverTypeCore/Vocabulary.swift` | Termos (viram `initial_prompt`) e substituições determinísticas |
| `Sources/NeverTypeCore/TranscriptHistory.swift` | As últimas 30 transcrições, com teto e escrita atômica |
| `Sources/NeverTypeCore/Tone.swift` | Gera os WAV do retorno auditivo, com envelope contra o estalo |
| `Sources/NeverTypeCore/LoginItem.swift` | Abrir com o sistema, com a guarda de caminho antes de registrar |
| `Sources/NeverType/RecordingOverlay.swift` | Indicador que sobrevive a apps em tela cheia |
| `Sources/NeverType/VocabularyWindow.swift` | As duas listas do vocabulário, em abas editáveis |
| `scripts/build-app.sh` | Compila o whisper estático, monta o bundle, assina com identidade estável |
| `scripts/setup-bench.sh` | Constrói os modelos ggml a partir do CDN da OpenAI |
| `scripts/bench.sh` | Mede latência e qualidade por modelo |
| `scripts/install.sh` | Instala em `/Applications` e conduz as permissões |
| `docs/escolha-do-modelo.md` | Qual modelo foi escolhido, com os números |
| `docs/armadilhas.md` | O que quebrou, e o custo medido de cada erro |

## Dependencies (critical only)

- **whisper.cpp** (`306c88f4…`, MIT) — motor de transcrição, compilado estático
- **Whisper large-v3-turbo** (OpenAI, MIT — código e pesos) — modelo, 547 MB, fora do repo
- **cmake** (Homebrew) — só para compilar; não é dependência de execução
- Nenhuma dependência SwiftPM externa

## Known Issues / Tech Debt

- **Orçamento sugerido vs realidade observada.** A regra dá ≤4 arquivos para um
  projeto de 17 fontes, e é razoável para manutenção. As quatro partes
  implementadas precisaram de 5 a 9 arquivos cada, porque construíam do zero.
  Spec nova de manutenção deve caber em 4; spec que cria subsistema, não.
- **O atraso de 0,6 s antes de devolver a área de transferência é um chute**, não
  uma medição. Modo de falha: colar conteúdo antigo dentro do documento de alguém.
- **O ⌘V é postado às cegas** — com o foco num app sem campo editável, vira
  atalho arbitrário no app da frente.
- **`IsSecureEventInputEnabled` é flag global da sessão**, não "campo de senha em
  foco". Qualquer processo pode ligá-la e esquecer de desligar.
- **Cada ditado bloqueia uma thread do pool cooperativo por ~600 ms.**
- **A chave de assinatura é alcançável por processo local** — risco documentado e
  aceito; sem conserto com certificado local.
- **Ninguém além do autor instalou este projeto do zero.**
- Doc comment em `TextInjector.pending` mistura dois assuntos (geração e
  indexação por pasteboard) num bloco só.
