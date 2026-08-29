#!/bin/bash
# Checks what can be checked from the outside about a NeverType installation.
#
# Exists because the installation has a failure mode that is easy to miss:
# without the Accessibility permission the app opens and does not react to the
# key. It warns — slashed icon (mic.slash), "Accessibility: missing" and "Open
# Accessibility Settings…" in the menu, a line in nevertype.log and macOS's own
# prompt —, but whoever opens neither the menu nor the log concludes it is
# installed.
#
# This script does NOT verify permissions, and says so out loud at the end. It
# is not an implementation limitation: what matters is not TCC saying it
# granted, but dictation inserting text. Only dictating proves that.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/NeverType.app"
MODEL="$HOME/Library/Application Support/NeverType/models/ggml-large-v3-turbo-q5_0.bin"

# The ggml magic is 0x67676d6c written as a little-endian uint32, so in the file
# it comes out reversed: 6c6d6767, which read as text becomes "lmgg". Comparing
# in hexadecimal avoids that trip-up — and catches the case that matters most
# here, which is a filtering proxy returning an HTML error page under a model's
# name.
GGML_MAGIC_HEX=6c6d6767
# 400 MB for a 547 MB model — the same floor as ModelStore.minimumBytes in the
# app, install.sh and fetch-model.sh. A low floor would approve an interrupted
# download: reproduced with 100 KB of the real model, whisper.cpp accepts it as
# an "empty model" and the process dies on the first inference
# (docs/pitfalls.md).
MODEL_MIN_MB=400

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# `problem` instead of `fail` in the body, on purpose: whoever reads this script
# is usually an agent, and exiting on the first error would make it fix one
# thing, run again, discover the second. Here it sees the whole list at once.
problems=0
problem() {
  printf '\033[1;31m  x\033[0m  %s\n' "$*" >&2
  problems=$((problems + 1))
}

[ "$(uname -s)" = "Darwin" ] || fail "only runs on macOS."
[ "$(uname -m)" = "arm64" ]  || fail "needs Apple Silicon: without Metal, transcription is far too slow."

# Checked at the start because every fix message below says to run
# `bash scripts/...`, and that only works from inside the repository. An agent
# that copied this script somewhere else would get instructions that do not
# work.
[ -x "$REPO_ROOT/scripts/install.sh" ] || fail "could not find $REPO_ROOT/scripts/install.sh.
      Run this script from inside the cloned repository, not from a loose copy."

# --- the app ------------------------------------------------------------------

info "Application"
if [ -d "$APP" ]; then
  ok "installed at $APP"
  # The diagnostics go to a variable instead of /dev/null: a signature that does
  # not verify needs to say why, or the next step is guessing.
  if signature="$(codesign --verify --strict "$APP" 2>&1)"; then
    ok "signature verifies"
  else
    problem "the signature of $APP does not verify:
      ${signature:-no output from codesign}
      Rebuild and reinstall: bash scripts/build-app.sh && bash scripts/install.sh"
  fi
else
  problem "$APP does not exist.
      Run: bash scripts/install.sh"
fi

# --- the process --------------------------------------------------------------

info "Process"
if pid="$(pgrep -x NeverType)"; then
  ok "running (pid $pid)"
else
  problem "NeverType is not running.
      Open it: open $APP"
fi

# --- the model ----------------------------------------------------------------

info "Model"
if [ ! -f "$MODEL" ]; then
  problem "model missing at $MODEL.
      Run: bash scripts/setup-bench.sh && bash scripts/fetch-model.sh
      If your network blocks the download, see docs/INSTALL.md — copying from
      another machine is a valid path, but the file has to come in through models/."
else
  model_magic="$(head -c 4 "$MODEL" | xxd -p)"
  model_mb=$(( $(stat -f%z "$MODEL") / 1048576 ))
  if [ "$model_magic" != "$GGML_MAGIC_HEX" ]; then
    problem "the file at $MODEL is not a ggml: magic $model_magic, expected $GGML_MAGIC_HEX.
      A filtering proxy returns an HTML error page under a model's name, and
      this is exactly how that shows up. Delete it and redo: rm '$MODEL'"
  elif [ "$model_mb" -lt "$MODEL_MIN_MB" ]; then
    problem "truncated model: $model_mb MB, minimum $MODEL_MIN_MB MB.
      The first bytes of an interrupted download are right, so the magic alone
      does not catch this. Delete it and redo: rm '$MODEL'"
  else
    ok "valid ($model_mb MB)"
  fi
fi

# --- what this script does not know -------------------------------------------

echo
if [ "$problems" -gt 0 ]; then
  fail "$problems check(s) failed. Fix the above and run again."
fi

info "The part only you can verify"
cat <<'MSG'
  Microphone and Accessibility were NOT verified here, and cannot be verified
  from the outside. Without Accessibility the app opens and does not react to
  the key; what it shows is the slashed icon (mic.slash) and, in the menu,
  "Accessibility: missing" with the item "Open Accessibility Settings…". It is
  the most likely failure mode of a fresh installation.

  Prove it by dictating:

    1. Open any text field.
    2. Hold Right ⌘, say a sentence, release.
    3. The text has to appear where the cursor is.

  Did it not appear? System Settings › Privacy & Security › Accessibility, and
  turn on NeverType. After that, quit and reopen the app.
MSG
ok "structure verified"
