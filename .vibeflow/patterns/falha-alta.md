---
tags: [error-handling, observability, fail-fast, degradation, user-feedback]
modules: [Sources/FalaFlowCore/, Sources/FalaFlow/, scripts/]
applies_to: [services, commands, handlers]
confidence: inferred
---
# Pattern: Falha alta, nunca degradação silenciosa

<!-- vibeflow:auto:start -->
## What

Nada neste projeto pode falhar em silêncio nem funcionar pior sem avisar.
Degradação de desempenho é erro, não aviso; erro que o usuário não vê é erro que
não existe; e um caminho de falha que ninguém exercita é código morto.

## Where

Todo o repositório. É a convenção mais repetida e a que mais nasceu de defeito.

## The Pattern

**Degradação silenciosa é tratada como falha.** O `ggml` cai para CPU sem erro —
só fica ~11× mais lento. A bancada aborta em vez de reportar um número enganoso:

```bash
# scripts/bench.sh:124
if ! metal_is_active "$log"; then
  echo "SEM METAL"
  grep -E 'whisper_backend_init_gpu:' "$log" >&2 || true
  fail "a inferência não rodou em Metal nesta execução.
      Qualquer tempo medido assim é de CPU e não representa o app."
fi
```

**Erro em thread de background chega ao usuário.** O `catch` do tap de áudio
escrevia só em stderr — que não vai a lugar nenhum quando o app abre pelo Finder.
Hoje ele sobe até o ícone:

```swift
// Sources/FalaFlowCore/AudioRecorder.swift
/// Chamado quando a gravação falha no meio. Sem isto, o erro morria num
/// stderr que não vai a lugar nenhum quando o app é aberto pelo Finder: o
/// ícone seguia vermelho e `stop()` devolvia a URL como se tivesse dado certo.
public var onError: (@MainActor @Sendable (String) -> Void)?
```

**A mensagem diz o que fazer, não só o que houve:**

```swift
// Sources/FalaFlowCore/Transcriber.swift
case .modelMissing(let u):
    return "modelo não encontrado em \(u.path). Rode scripts/fetch-model.sh"
case .modelInvalid(let u):
    return "o arquivo em \(u.path) não é um modelo ggml completo (truncado ou corrompido). Rode scripts/fetch-model.sh"
```

## Rules

- Perda de desempenho por fallback (GPU → CPU) é **erro**, não aviso.
- Toda mensagem de erro nomeia a ação de saída: o script a rodar, o ajuste a abrir.
- Erro fora da main thread tem canal até a interface. Log sozinho não conta —
  o app é acessório, sem janela, e o stderr se perde.
- Todo caminho de falha precisa ser exercitável. Se não dá para exercitar, ele
  não conta como implementado.
- `>/dev/null 2>&1` em comando que pode falhar exige que o diagnóstico seja
  gravado em algum lugar e citado na mensagem.

## Examples from this codebase

File: `Sources/FalaFlow/main.swift` — falha de transcrição deixou de ser `nil`
opaco e passou a carregar a causa, com sinal visual:
```swift
case .failure(let failure):
    // Sinal visível: sem isto o ditado sumia em silêncio — o
    // ícone já voltou ao normal, o app não tem janela, e o
    // stderr não vai a lugar nenhum quando aberto pelo Finder.
    self.log("TRANSCRIÇÃO FALHOU: \(failure.reason)")
    self.render(.blocked)
```

File: `scripts/build-app.sh` — o diagnóstico do cmake era engolido; hoje vai para
log e é citado:
```bash
    || fail "configuração do cmake falhou. Diagnóstico em: $log
      $(tail -3 "$log" | sed 's/^/      /')"
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **`try?` que engole exceção que não existe.** `warmUp()` usava `try?` achando
  que protegia de falha do modelo. O modo de falha real era exceção de C++
  (`std::out_of_range`), que `try` nenhum do Swift intercepta — o `try?`
  mascarava só o que não acontecia. Hoje `warmUp()` devolve `Bool` e o status
  diz `AQUECIMENTO FALHOU`.
- **Fallback inalcançável.** `[ -n "$load_ms" ] || load_ms=0` nunca rodava:
  `set -e` mais `pipefail` derrubavam o script na atribuição quando o `grep` não
  casava. Sob `pipefail`, um `grep` que pode não casar vai entre
  `{ grep ... || true; }`.
