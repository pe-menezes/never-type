---
tags: [verification, integrity, binary-formats, false-negatives, guards]
modules: [Sources/NeverTypeCore/, scripts/]
applies_to: [services, commands, configs]
confidence: inferred
---
# Pattern: Verificar por evidência estrutural, não por texto

<!-- vibeflow:auto:start -->
## What

Toda verificação neste projeto olha para a estrutura do que está sendo
verificado — bytes, campos, dispositivos registrados, checksums — e nunca para a
presença de uma palavra num log ou num arquivo. Procurar texto produz falso
negativo e falso positivo, e as duas variantes já custaram caro aqui.

## Where

- `scripts/bench.sh` e `scripts/setup-bench.sh` — `metal_is_active()`
- `Sources/NeverTypeCore/Transcriber.swift` — `ModelStore.isValid`, enumeração de backends
- `scripts/build-app.sh` — verificação de commit e manifesto de checksums

## The Pattern

**O caso que ensinou a regra.** O `ggml` inicializa o device Metal só para
enumerá-lo, mesmo quando a inferência roda em CPU: um log de `whisper-cli -ng`
contém 37 linhas com a palavra "metal". Um `grep -qi metal` aceitava execução em
CPU como válida — 1635 ms passando por 143 ms. O discriminador real é o backend
que o whisper escolheu:

```bash
# scripts/bench.sh:33 e scripts/setup-bench.sh:69 — idênticos de propósito
metal_is_active() {
  local log="$1"
  grep -q 'whisper_backend_init_gpu: no GPU found' "$log" && return 1
  grep -Eq 'whisper_backend_init_gpu:.*MTL' "$log"
}
```

Repare que ele exige o positivo **e** rejeita o negativo. Uma guarda cuja única
função é não se deixar enganar não confia num só sinal.

**Dentro do app, a mesma regra vira enumeração em vez de log:**

```swift
// Sources/NeverTypeCore/Transcriber.swift
// Enumera os dispositivos que o ggml de fato registrou, em vez de
// procurar a palavra "metal" em log — que foi o falso negativo pego na
// auditoria da Parte 1.
for i in 0..<ggml_backend_dev_count() {
    guard let dev = ggml_backend_dev_get(i) else { continue }
    devices.append(String(cString: ggml_backend_dev_name(dev)))
}
self.usesMetal = devices.contains { $0.uppercased().contains("MTL") || $0.uppercased().contains("METAL") }
```

**Formato binário se confere pelos bytes, na ordem em que estão no arquivo:**

```swift
// Sources/NeverTypeCore/Transcriber.swift:27
/// O magic do ggml é gravado como uint32 little-endian, então os bytes no
/// arquivo saem invertidos: `6c6d6767`, que lido como texto vira "lmgg", não
/// "ggml". Checar o texto direto reprova todo modelo válido — erro já
/// cometido neste projeto.
return magic.map { String(format: "%02x", $0) }.joined() == "6c6d6767"
```

## Rules

- Nunca verifique presença de palavra em log para concluir que algo funcionou.
  Logs contêm o vocabulário de coisas que **não** aconteceram.
- Magic number se compara em hexadecimal, não como texto: a ordem dos bytes em
  disco não é a ordem em que a constante é escrita no código.
- Magic sozinho não valida arquivo — some sempre um piso de tamanho. Um download
  interrompido tem os primeiros bytes certos.
- A mesma regra de validação vale nos dois lados: se o shell exige magic e
  tamanho, o Swift exige magic e tamanho. Divergência entre eles é bug esperando.
- Artefato reusado se confere por checksum, não por existência de arquivo.

## Examples from this codebase

File: `scripts/build-app.sh` — fonte de terceiro conferida por commit, e a
árvore conferida contra modificação local:
```bash
local got; got="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo desconhecido)"
[ "$got" = "$WHISPER_COMMIT" ] || fail "o whisper.cpp em $src não é o commit esperado.
      esperado: $WHISPER_COMMIT
      obtido:   $got"
if ! git -C "$src" diff --quiet HEAD 2>/dev/null; then
  fail "há modificações locais em $src. Apague o diretório e rode de novo."
fi
```

File: `scripts/build-app.sh` — o vendor reusado confere checksums, não existência:
```bash
vendor_intact() {
  [ -f "$VENDOR/MANIFEST" ] && [ -f "$VENDOR/include/whisper.h" ] || return 1
  ( cd "$VENDOR/lib" && shasum -a 256 --status -c "$VENDOR/MANIFEST" ) 2>/dev/null
}
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **`grep -qi 'metal'`** — a versão original de `metal_is_active`. Aceitava CPU
  como Metal. Reproduzível: `whisper-cli -ng` casa 37 linhas.
- **`head -c 4 "$f" = "ggml"`** — reprovava todo modelo válido, incluindo o de
  referência do Homebrew, porque o magic em disco é `lmgg`.
- **Piso de 50 MB para um modelo de 547 MB** — aprovava download truncado, e foi
  o piso do app (`ModelStore.minimumBytes`), do `fetch-model.sh` e do
  `setup-bench.sh` até 29/08/2026, com a regra certa já escrita em
  `docs/pitfalls.md`. Hoje são 400 MB nos cinco lugares; na bancada, por
  modelo. O piso precisa ser proporcional ao artefato real, não a um mínimo
  teórico — e a regra escrita se confere com `grep` pelo número.
