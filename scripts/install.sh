#!/bin/bash
# Installs NeverType into /Applications.
#
# Fixed path on purpose: together with the stable signing identity, it is what
# makes the Accessibility permission survive. Moving the app afterwards breaks
# the grant and macOS asks again.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/build/NeverType.app"
DEST="/Applications/NeverType.app"
MODEL_DIR="$HOME/Library/Application Support/NeverType/models"
MODEL="ggml-large-v3-turbo-q5_0.bin"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "only runs on macOS."
[ "$(uname -m)" = "arm64" ]  || fail "needs Apple Silicon: without Metal, transcription is far too slow."

# Checked now, not after minutes of compiling: on a managed Mac or with a
# non-admin user, /Applications is not writable, and finding that out at the end
# is the surest way to make the person give up.
[ -w /Applications ] || fail "no write permission in /Applications.
      Ask someone with administrator rights, or install elsewhere:
        cp -R build/NeverType.app ~/Applications/"

# --- the app ------------------------------------------------------------------

if [ ! -d "$SOURCE" ]; then
  info "Compiling (the first time takes a few minutes)"
  bash "$REPO_ROOT/scripts/build-app.sh" || fail "the build failed."
fi
[ -d "$SOURCE" ] || fail "could not find $SOURCE."

info "Installing into $DEST"
# `pkill`, not `osascript quit`.
#
# Sending an Apple event to a new app requires TCC Automation authorization, and
# macOS opens a modal dialog asking for it — hanging the installer right after
# "Installing into /Applications", with no hint of why. And it waits for the
# process to actually die: with a fixed `sleep`, an app that takes a while to
# quit survives, the single-instance guard blocks the new one, and the person
# keeps running the old binary thinking they updated.
if pgrep -x NeverType >/dev/null; then
  info "Quitting the running instance"
  pkill -x NeverType || true
  for _ in $(seq 1 30); do
    pgrep -x NeverType >/dev/null || break
    sleep 0.2
  done
  pgrep -x NeverType >/dev/null && fail "NeverType did not quit. Quit it from the menu bar menu and run again."
fi
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST" || fail "the signature does not verify at $DEST."
ok "installed and verified"

# The build/ copy is a build artifact and stays there. Opening it by mistake
# does not duplicate the app — the second instance yields to the first —, but
# it confuses.
[ -d "$SOURCE" ] && warn "the build/ copy is still in the repository; always use $DEST"

# --- the model ----------------------------------------------------------------
#
# It does not ship in the app: it is 547 MB. How to get it depends on the
# network — some corporate networks block Hugging Face, so the setup downloads
# the checkpoint from OpenAI's CDN and converts it.

info "Checking the model"
# 400 MB for a 547 MB model — the same floor as ModelStore.minimumBytes in the
# app, fetch-model.sh and verify-install.sh. A low floor would approve an
# interrupted download: reproduced with 100 KB of the real model, whisper.cpp
# accepts it as an "empty model" and the process dies on the first inference
# (exit 134, see docs/pitfalls.md).
MODEL_MIN_MB=400
if [ -f "$MODEL_DIR/$MODEL" ] && [ "$(( $(stat -f%z "$MODEL_DIR/$MODEL") / 1048576 ))" -ge "$MODEL_MIN_MB" ]; then
  ok "model present ($(( $(stat -f%z "$MODEL_DIR/$MODEL") / 1048576 )) MB)"
elif [ -f "$REPO_ROOT/models/$MODEL" ]; then
  bash "$REPO_ROOT/scripts/fetch-model.sh"
else
  warn "the model does not exist on this machine yet."
  echo "     It is 547 MB and is built from OpenAI's checkpoint:"
  echo
  echo "       bash scripts/setup-bench.sh   # downloads and converts three models;"
  echo "                                     # requires Homebrew and python3"
  echo "       bash scripts/fetch-model.sh   # validates and installs it in the right place"
  echo
  echo "     Faster alternative if someone else already has it: copy the file"
  echo "     into models/ (inside the repository) and run only the second step:"
  echo
  echo "       cp /wherever/it/came/from/$MODEL models/"
  echo "       bash scripts/fetch-model.sh"
  echo
  echo "     Do not copy straight into $MODEL_DIR/: that skips fetch-model.sh's"
  echo "     magic and size validation, and a bad file is only refused when the"
  echo "     app opens — the message shows up in the menu, under \"Model:\" (hold"
  echo "     Option as you open it), not here."
  echo
fi

# --- permissions --------------------------------------------------------------

cat <<'MSG'

==> Two permissions are left for you to grant

  Open the app and macOS will ask for both. Both are required:

    Microphone      without it there is no audio
    Accessibility   without it the app cannot paste at the cursor. If you try to
                    dictate, recording is blocked before audio is captured and
                    an alert offers to open the right System Settings page

  If the Accessibility window does not show up, go to
  System Settings › Privacy & Security › Accessibility and turn on NeverType.

==> How to use

  Hold Right ⌘, speak, release. The text appears wherever the cursor is.
  Pressing any regular key (or Esc) during the hold cancels and discards the audio.

  Hands-free: two quick taps on the key lock the recording; one tap finishes
  and transcribes; Esc discards. While locked, typing does not cancel. A second
  key can lock with one tap: "Choose a hands-free key…" under "Hands-free".

  In the menu bar menu: the key (the three quick picks Right ⌘, Right ⌥ and
  Right ⌃, or another supported modifier, Fn or an extra mouse button through
  "Other key or mouse button…", which takes the next press) and the sounds are
  under "Hotkey"; the latest transcriptions under "Copy Last Transcription" and
  "History", where clicking copies and "Clear History" deletes the file; terms
  and replacements under "Vocabulary…". Clicking the floating orb opens that
  same menu, which is how you reach it in full screen. Holding Option as it
  opens adds the trigger, the model and the version.

MSG

info "Opening"
open "$DEST"
ok "done"
