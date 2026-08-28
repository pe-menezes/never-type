---
tags: [supply-chain, dependencies, integrity, build-security, provenance]
modules: [scripts/, vendor/]
applies_to: [commands, configs]
confidence: inferred
---
# Pattern: Código de terceiro entra por referência fixa e conferida

<!-- vibeflow:auto:start -->
## What

Nada de terceiro é baixado, compilado ou executado sem que a origem esteja fixada
numa referência imutável e conferida na hora do uso. Isso vale para o script que
converte o modelo, para o repositório que fornece os assets e para as ~300 mil
linhas de C++ que entram no binário.

## Where

- `scripts/build-app.sh` — `WHISPER_COMMIT`, manifesto de `vendor/`
- `scripts/setup-bench.sh` — `CONVERTER_SHA256`, `OPENAI_WHISPER_COMMIT`

## The Pattern

**Tag de git não é referência imutável.** `v1.9.2` é um ponteiro que o mantenedor
— ou quem comprometer a conta — move sem deixar rastro. O commit é fixado:

```bash
# scripts/build-app.sh
# `v1.9.2` é uma tag leve — um ponteiro que o mantenedor, ou quem comprometer a
# conta, move sem deixar rastro. Isto aqui vira ~300 mil linhas de C++ compiladas
# e linkadas dentro do binário que detém Acessibilidade.
WHISPER_COMMIT="306c88f4d1286aec1bf96e544632897886af5501"
```

**A conferência acontece sempre, inclusive num clone que já existia:**

```bash
# Confere sempre, inclusive num clone preexistente: reusar .cache/ só por
# existir significa compilar o que quer que esteja lá.
local got; got="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo desconhecido)"
[ "$got" = "$WHISPER_COMMIT" ] || fail "o whisper.cpp em $src não é o commit esperado. ..."
if ! git -C "$src" diff --quiet HEAD 2>/dev/null; then
  fail "há modificações locais em $src. Apague o diretório e rode de novo."
fi
```

**Artefato compilado ganha manifesto**, para o reuso não ser confiança cega:

```bash
# Manifesto do que foi produzido. Sem isto, reusar vendor/ numa execução
# seguinte confiaria nos .a só por existirem — e é código que vai para dentro
# do binário que detém Acessibilidade.
( cd "$VENDOR/lib" && shasum -a 256 ./*.a ) > "$VENDOR/MANIFEST"
```

**Download conferido por checksum, e removido se não bater:**

```bash
# scripts/setup-bench.sh
CONVERTER_SHA256="e874333f95c52725c23541b39e71594e01442a2a687c96e2e882493c45b887a2"
# ...
if [ "$got" != "$CONVERTER_SHA256" ]; then
  rm -f "$CONVERTER"
  fail "checksum do conversor não confere. ... Não execute script baixado que não confere."
fi
```

## Rules

- Referência fixa é commit ou checksum. Tag e branch não servem.
- A conferência roda a cada execução, não só no primeiro download. Reuso por
  existência de arquivo é a mesma coisa que não conferir.
- Artefato compilado localmente é reusado só contra manifesto de checksums; se
  não confere, reconstrói a partir da fonte verificada.
- O que não confere é removido, não deixado no disco para a próxima execução
  encontrar.
- **O rigor acompanha o impacto.** Código que entra no binário com Acessibilidade
  merece pelo menos o mesmo cuidado que um script auxiliar.

## Examples from this codebase

File: `scripts/build-app.sh` — reuso condicionado a integridade:
```bash
if vendor_intact; then
  ok "vendor/whisper íntegro (checksums conferem)"
elif [ -d "$VENDOR" ]; then
  warn "vendor/whisper não confere com o manifesto — reconstruindo do zero"
  build_whisper_static
else
  build_whisper_static
fi
```

File: `scripts/setup-bench.sh` — assets do modelo também pinados:
```bash
OPENAI_WHISPER_COMMIT="5f86d1d86363843179951550570367b37c5d6f78"
got_commit="$(git -C "$WHISPER_REPO" rev-parse HEAD 2>/dev/null || echo desconhecido)"
[ "$got_commit" = "$OPENAI_WHISPER_COMMIT" ] || fail "openai/whisper ... não é o commit esperado."
```
<!-- vibeflow:auto:end -->

## Rationale

A regra do rigor proporcional ao impacto nasceu de uma inconsistência que uma
auditoria formulou melhor do que o autor:

> O rigor de sha256 é aplicado a um script Python de 10 KB que roda offline, uma
> vez. O mesmo raciocínio não é aplicado a ~300 mil linhas de C/C++ compiladas e
> linkadas dentro do binário que detém Acessibilidade. **O critério mais rigoroso
> está no alvo de menor impacto.**

## Anti-patterns

- **Clone por tag ou por branch padrão.** `git clone --depth 1 -b v1.9.2` sem
  conferir o commit, e `git clone --depth 1` do branch padrão do `openai/whisper`
  — os dois existiram, no mesmo arquivo que pregava contra alvos móveis.
- **Reuso por existência de arquivo.** `[ -d "$src" ]` e
  `[ -f "$VENDOR/lib/libwhisper.a" ]` como única condição para pular a
  verificação.
