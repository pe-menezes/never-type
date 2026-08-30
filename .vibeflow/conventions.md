# Convenções — NeverType

<!-- vibeflow:auto:start -->

## Idioma

Código, tipos, APIs, comentários, mensagens de erro, texto de interface, testes,
scripts, documentação pública e commits em inglês. A `.vibeflow/` fica em
português porque é a memória de trabalho de quem conduz o repositório.
`README.md` e `docs/INSTALL.md` têm espelhos em português, que mudam junto com o
original: `README.pt-BR.md` e `docs/INSTALL.pt-BR.md`.

## Comentários registram a decisão e o custo do erro

A convenção mais distintiva deste repositório. Um comentário aqui não explica o
que o código faz — explica **por que é assim e o que aconteceu quando era de
outro jeito**. Sempre com o número medido, quando existe.

```swift
// Sempre template.
//
// Imagem template é a que o macOS repinta conforme o fundo da barra;
// sem isso o símbolo é desenhado na cor natural dele, preto, e some
// contra a barra escura — o ícone ficava invisível exatamente enquanto
// estava gravando.
image?.isTemplate = true
```

```bash
# O ggml inicializa o device Metal só para enumerá-lo, mesmo quando a inferência
# roda em CPU: um log de `whisper-cli -ng` contém 37 linhas com a palavra "metal".
# Custo do erro, medido: encode 1635 ms em CPU contra 143 ms em Metal.
```

Quando uma decisão é revertida, o comentário registra a reversão **e por que a
decisão original estava certa com a informação da época**. Ver
`Sources/NeverTypeCore/Transcriber.swift` (`warmUp`) e o comentário de linkagem
estática em `Package.swift`.

## Estrutura

- `Sources/NeverTypeCore/` — lógica, testável, sem AppKit de interface
- `Sources/NeverType/` — `NSApplication`, menu bar, painel; orquestra, não decide
- `Sources/CWhisper/` — module map para o whisper.cpp estático
- `Tests/NeverTypeCoreTests/` — swift-testing, um arquivo por unidade
- `scripts/` — shell, contrato comum (ver `patterns/scripts-shell.md`)
- `docs/` — decisões e mapas para humanos
- `.vibeflow/` — convenções e padrões

## Nomes

- Tipos e funções em inglês, `UpperCamelCase` e `lowerCamelCase`
- Arquivos de fonte com o nome do tipo principal: `TextInjector.swift`
- Scripts em kebab-case com verbo: `build-app.sh`, `fetch-model.sh`
- Testes descrevem o comportamento em inglês, em frase:
  `@Test("cancelling clears the samples from memory, not just the file")`
- Suítes nomeiam o assunto em inglês: `@Suite("Recording file cycle")`

## Swift

- Swift 6, concorrência estrita. Isolamento no tipo (ver `patterns/isolamento-tipado.md`)
- `public` só no que o executável ou os testes usam
- Erros são `enum ...Error: Error, CustomStringConvertible`, com `description` em
  inglês dizendo a ação de saída
- Sem força de desempacotamento (`!`) fora de literais comprovadamente seguros
- `guard` para saída antecipada; `defer` para liberar recurso, inclusive em erro
- Doc comment (`///`) em todo `public`, explicando o porquê, não o quê

## Testes

- **swift-testing (`import Testing`), nunca XCTest** — XCTest exige Xcode
  completo, e este projeto compila só com Command Line Tools
- `#expect` com mensagem que diz o que se esperava e o que veio
- Todo bug corrigido ganha um teste que o descreve, com o cenário no comentário
- Recurso compartilhado (pasteboard) é sempre uma instância nomeada de teste
- Teste que precisa de artefato pesado é condicional (`.enabled(if:)`), e a
  condição é documentada

## Shell

Ver `patterns/scripts-shell.md`. Em resumo: `set -euo pipefail`, `REPO_ROOT` por
`BASH_SOURCE`, `info/ok/warn/fail`, idempotência, espera por condição.

## Verificação

Sempre por estrutura, nunca por texto de log. Ver `patterns/verificacao-estrutural.md`.

## Don'ts

- **NÃO** procure palavra em log para concluir que algo funcionou — logs contêm o
  vocabulário de coisas que não aconteceram. Um log de execução em CPU tem 37
  linhas com "metal".
- **NÃO** compare magic number como texto: `head -c 4` de um ggml é `lmgg`, não
  `ggml`. Compare em hexadecimal.
- **NÃO** valide arquivo binário só pelo magic — some um piso de tamanho
  proporcional ao artefato real. Download truncado tem os primeiros bytes certos.
- **NÃO** use `MainActor.assumeIsolated` em callback de API sem contrato
  documentado de main thread. Já derrubou o processo duas vezes. E lembre que
  closure escrita dentro de método `@MainActor` **herda** o isolamento por
  inferência.
- **NÃO** use XCTest. Não existe sem Xcode completo.
- **NÃO** guarde estado de permissão numa variável — consulte o sistema.
- **NÃO** restaure recurso compartilhado incondicionalmente. Confira se ninguém
  mexeu (`changeCount`) e se a operação ainda é a mais recente.
- **NÃO** faça exclusão mútua entre processos consultando-e-decidindo. Use
  primitiva atômica (`flock`). `NSRunningApplication` falha 3 de 3.
- **NÃO** engula diagnóstico com `>/dev/null 2>&1` em comando que pode falhar —
  grave em log e cite-o na mensagem de erro.
- **NÃO** use `sleep` fixo esperando processo ou evento. Espere a condição, com
  limite e falha explícita.
- **NÃO** use `osascript` para controlar aplicativo: exige autorização de
  Automação do TCC e trava o script num diálogo modal.
- **NÃO** confie em `trap ... RETURN` sozinho para limpar temporário — não dispara
  em `exit`. Some `EXIT`.
- **NÃO** clone terceiro por tag ou branch. Fixe o commit e confira a cada
  execução, inclusive em clone preexistente.
- **NÃO** reuse artefato compilado só porque o arquivo existe — confira o
  manifesto de checksums.
- **NÃO** adicione chamada de rede ao app. É a restrição que justifica o projeto,
  e há check de DoD verificando isso no código e no binário.
- **NÃO** deixe recurso de privacidade (microfone) adquirido entre usos.
- **NÃO** versione áudio de `fixtures/`, modelos, `vendor/` ou `bench-out/`.
- **NÃO** escreva travessão (em dash `—`, en dash `–`) nem aspas curvas em prosa
  de qualquer arquivo do repositório. Regra do autor, vale pros dois idiomas.
  Cada travessão vira ponto, vírgula, parênteses ou dois-pontos, conforme a
  frase pede. Dentro de bloco de código, string literal, saída colada, tabela de
  dados ou citação de terceiro, fica.
- **NÃO** troque um travessão por figura de oposição: ponto e vírgula
  contrastivo, "rather than", "instead of", "not X but Y", "while/whereas" de
  oposição, privativo espelhado. Se o travessão carregava um contraste, quebre
  em frases separadas, cada uma afirmativa. Medido em 29/08/2026: o cold-read do
  README achou 36 antíteses depois de uma rodada que tinha zerado a forma
  canônica, porque a figura migrou de fivela. Tirar o travessão não é o objetivo,
  é o meio; o objetivo é prosa sem tique retórico.
<!-- vibeflow:auto:end -->

## Observações de operação

- `swift test` fica verde numa máquina sem o modelo: a suíte de transcrição é
  condicional. Não confunda verde com cobertura.
- Os fixtures são gravações de quem desenvolve e não são versionados. A suíte de
  transcrição é pulada quando eles não existem — verde não significa cobertura.
