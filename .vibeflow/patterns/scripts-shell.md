---
tags: [shell, idempotency, build-scripts, cli, developer-experience]
modules: [scripts/]
applies_to: [commands, configs]
confidence: inferred
---
# Pattern: Contrato dos scripts de shell

<!-- vibeflow:auto:start -->
## What

Os oito scripts em `scripts/` seguem o mesmo esqueleto: mesmo modo estrito,
mesma resolução de raiz, mesmas quatro funções de saída, idempotência e
verificação antes de destruir. Um script novo que não siga isso destoa na hora.

## Where

`scripts/setup-bench.sh`, `bench.sh`, `record-fixture.sh`, `build-app.sh`,
`fetch-model.sh`, `install.sh`, `verify-install.sh`, `update.sh` — os
oito, sem exceção.

## The Pattern

*Os trechos citados nesta seção são fotografia de antes da tradução de
29/08/2026 (o `fail` com `erro:`, "sem permissão de escrita em /Applications…",
"o NeverType não encerrou…"); hoje os scripts imprimem `error:`, "no write
permission in /Applications…" e "NeverType did not quit…". O esqueleto é o mesmo.*

```bash
#!/bin/bash
# <uma frase do que faz>
#
# <por que faz assim, quando não for óbvio — inclusive o que já deu errado>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }
```

`REPO_ROOT` vem de `BASH_SOURCE`, nunca do diretório de trabalho: um script
copiado para `/tmp` resolveria caminhos a partir de `/` e procuraria em
`//models`.

**Pré-requisito caro é conferido antes do trabalho caro.** Descobrir no fim é o
jeito mais certo de a pessoa desistir:

```bash
# scripts/install.sh
# Conferido agora, e não depois de compilar por minutos: num Mac gerido ou com
# usuário não-admin, /Applications não é gravável, e descobrir isso no fim é o
# jeito mais certo de a pessoa desistir.
[ -w /Applications ] || fail "sem permissão de escrita em /Applications. ..."
```

**Esperar por evento, não por relógio:**

```bash
# scripts/install.sh
pkill -x NeverType || true
for _ in $(seq 1 30); do
  pgrep -x NeverType >/dev/null || break
  sleep 0.2
done
pgrep -x NeverType >/dev/null && fail "o NeverType não encerrou. ..."
```

## Rules

- `set -euo pipefail` sempre. Sob `pipefail`, `grep` que pode não casar vai entre
  `{ grep ... || true; }` — senão derruba o script antes do fallback.
- Todo script roda duas vezes seguidas sem quebrar e sem refazer trabalho pronto.
- Pré-requisito que pode faltar é conferido no começo, com a instrução de
  correção na mensagem.
- Espera por condição observável, com limite e falha explícita. Nunca `sleep` fixo.
- Artefato baixado é conferido (checksum ou commit) antes de ser usado; se não
  conferir, é removido.
- Diretório de build é recriado do zero: reaproveitar meio-configurado faz o
  cmake falhar de forma obscura.
- Nada de `osascript` para controlar app: exige autorização de Automação do TCC
  e trava o script num diálogo modal na primeira execução de qualquer máquina.

## Examples from this codebase

File: `scripts/setup-bench.sh` — validação com magic e tamanho, com o piso por
modelo (vem da tabela `MODELS`, proporcional ao artefato real), e remoção do que
não confere:
```bash
is_valid_ggml() {  # <arquivo> <piso em MB>
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" | xxd -p)" = "$GGML_MAGIC_HEX" ] || return 1
  [ "$(( $(stat -f%z "$1") / 1048576 ))" -ge "$2" ]
}
```

File: `scripts/build-app.sh` — trava de keychain devolvida em qualquer saída:
```bash
trap 'security lock-keychain "$KEYCHAIN" 2>/dev/null || true' EXIT
```
<!-- vibeflow:auto:end -->

## Anti-patterns

- **`trap ... RETURN` sozinho para limpar temporário.** Não dispara quando o
  script sai por `fail`, e uma chave RSA sem senha ficava esquecida em `$TMPDIR`.
  Some `EXIT`.
- **`>/dev/null 2>&1` em comando que pode falhar.** O usuário via "configuração
  do cmake falhou" sem nenhuma causa. Grave em log e cite-o no `fail`.
- **`find ... ! -name 'algo.a'` para escolher artefatos.** Exclusão por nome é
  frágil: qualquer arquivo novo do upstream entra em silêncio. Liste o que quer.
