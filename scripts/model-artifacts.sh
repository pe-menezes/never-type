#!/bin/bash
# Shared checks for locally generated models. A receipt records bytes only after
# the producer succeeds; a size floor alone also accepts interrupted output.

model_has_receipt() {
  local file="$1" expected actual
  [ -f "$file" ] && [ -f "$file.sha256" ] || return 1
  expected="$(cat "$file.sha256")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual="$(shasum -a 256 "$file" | cut -d' ' -f1)" || return 1
  [ "$actual" = "$expected" ]
}

model_write_receipt() {
  local file="$1"
  shasum -a 256 "$file" | cut -d' ' -f1 > "$file.sha256.partial" || return 1
  mv "$file.sha256.partial" "$file.sha256"
}

ensure_conversion_python() {
  local venv="$1"
  if [ ! -x "$venv/bin/python" ]; then
    python3 -m venv "$venv" || return 1
  fi
  # A failed pip download leaves a working interpreter but missing packages.
  if ! "$venv/bin/python" -c 'import torch, numpy' >/dev/null 2>&1; then
    "$venv/bin/python" -m ensurepip --upgrade || return 1
    "$venv/bin/python" -m pip install torch numpy || return 1
  fi
  "$venv/bin/python" -c 'import torch, numpy; print("torch", torch.__version__)'
}

ensure_pinned_assets() {
  local directory="$1" url="$2" commit="$3"
  if [ ! -d "$directory/.git" ]; then
    mkdir -p "$directory" || return 1
    git -C "$directory" init -q || return 1
  fi
  # Existing modifications may be someone's work, even in the cache.
  [ -z "$(git -C "$directory" status --porcelain)" ] || {
    printf 'Local changes in %s; move them aside before retrying.\n' "$directory" >&2
    return 1
  }
  if ! git -C "$directory" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$directory" fetch --depth 1 "$url" "$commit" || return 1
  fi
  git -C "$directory" checkout --detach -q "$commit" || return 1
  [ "$(git -C "$directory" rev-parse HEAD)" = "$commit" ]
}
