#!/bin/bash
# Coloca o modelo escolhido onde o app procura.
#
# O modelo em si é construído por scripts/setup-bench.sh, que baixa o checkpoint
# do CDN da OpenAI e converte. Este script só promove o resultado para o caminho
# definitivo, ou explica o que falta.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="ggml-large-v3-turbo-q5_0.bin"
SOURCE="$REPO_ROOT/models/$MODEL"
DEST_DIR="$HOME/Library/Application Support/FalaFlow/models"
DEST="$DEST_DIR/$MODEL"
GGML_MAGIC_HEX=6c6d6767

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

is_valid() {
  [ -f "$1" ] && [ "$(head -c 4 "$1" | xxd -p)" = "$GGML_MAGIC_HEX" ] \
    && [ "$(( $(stat -f%z "$1") / 1048576 ))" -ge 50 ]
}

if is_valid "$DEST"; then
  ok "modelo já instalado ($(( $(stat -f%z "$DEST") / 1048576 )) MB)"
  echo "  $DEST"
  exit 0
fi

is_valid "$SOURCE" || fail "não encontrei um $MODEL válido em models/.
      Rode antes: bash scripts/setup-bench.sh
      Ele baixa o checkpoint do CDN da OpenAI e monta o ggml — a HuggingFace
      está bloqueada na rede corporativa."

info "Instalando o modelo"
mkdir -p "$DEST_DIR"
cp "$SOURCE" "$DEST.partial"
mv "$DEST.partial" "$DEST"
is_valid "$DEST" || { rm -f "$DEST"; fail "a cópia não ficou válida."; }
ok "$(( $(stat -f%z "$DEST") / 1048576 )) MB em $DEST"
