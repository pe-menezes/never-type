#!/bin/bash
# Puts the chosen model where the app looks for it.
#
# The model itself is built by scripts/setup-bench.sh, which downloads the
# checkpoint from OpenAI's CDN and converts it. This script only promotes the
# result to its final path, or explains what is missing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="ggml-large-v3-turbo-q5_0.bin"
SOURCE="$REPO_ROOT/models/$MODEL"
DEST_DIR="$HOME/Library/Application Support/NeverType/models"
DEST="$DEST_DIR/$MODEL"
GGML_MAGIC_HEX=6c6d6767
# 400 MB for a 547 MB model — the same floor as ModelStore.minimumBytes in the
# app, install.sh and verify-install.sh. Until 2026-08-29 it was 50, which
# approved a download interrupted at any point above that: the magic is right
# in a truncated file, and whisper.cpp accepts the truncated file as an "empty
# model" and dies on the first inference (docs/pitfalls.md).
MODEL_MIN_MB=400

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

is_valid() {
  [ -f "$1" ] && [ "$(head -c 4 "$1" | xxd -p)" = "$GGML_MAGIC_HEX" ] \
    && [ "$(( $(stat -f%z "$1") / 1048576 ))" -ge "$MODEL_MIN_MB" ]
}

if is_valid "$DEST"; then
  ok "model already installed ($(( $(stat -f%z "$DEST") / 1048576 )) MB)"
  echo "  $DEST"
  exit 0
fi

is_valid "$SOURCE" || fail "could not find a valid $MODEL (ggml magic and at least $MODEL_MIN_MB MB) in models/.
      Run first: bash scripts/setup-bench.sh
      It downloads the checkpoint from OpenAI's CDN and builds the ggml — some
      corporate networks block Hugging Face."

info "Installing the model"
mkdir -p "$DEST_DIR"
cp "$SOURCE" "$DEST.partial"
mv "$DEST.partial" "$DEST"
is_valid "$DEST" || { rm -f "$DEST"; fail "the copy did not come out valid."; }
ok "$(( $(stat -f%z "$DEST") / 1048576 )) MB at $DEST"
