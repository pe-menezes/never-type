#!/bin/bash
# Records a reference audio clip already in the format whisper-cli consumes:
# 16 kHz, mono, 16-bit PCM. Recording in QuickTime gives 44.1 kHz stereo m4a and
# the bench rejects it — that is why this script exists.
#
# Usage:
#   scripts/record-fixture.sh <name> [seconds] [device-index]
#
# Examples:
#   scripts/record-fixture.sh 01-normal-speech
#   scripts/record-fixture.sh 02-technical-terms 18
#   scripts/record-fixture.sh 03-short-sentence 12 2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/fixtures"

NAME="${1:-}"
DURATION="${2:-15}"
DEVICE="${3:-0}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v ffmpeg >/dev/null || fail "ffmpeg not found. brew install ffmpeg"

if [ -z "$NAME" ]; then
  echo "usage: scripts/record-fixture.sh <name> [seconds] [device-index]"
  echo
  info "Available audio devices:"
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | sed -n '/AVFoundation audio devices/,/^\[in#/p' \
    | grep -E '^\[AVFoundation.*\[[0-9]+\]' \
    | sed -E 's/^\[[^]]*\] /  /'
  echo
  echo "Script of what to record: fixtures/README.md"
  exit 1
fi

# The original spec's 10–20 s window was revoked: the bench needs short AND long
# dictation, because Whisper processes in 30 s windows and only the variation
# reveals that step. What belongs here is a sanity floor and a warning, not a
# lock.
if [ "$DURATION" -lt 3 ] || [ "$DURATION" -gt 120 ]; then
  fail "duration out of the reasonable range for a fixture (requested: ${DURATION}s). Use 3 to 120."
fi
if [ "$DURATION" -gt 30 ]; then
  printf '\033[1;33m  !\033[0m  above 30 s the audio occupies more than one Whisper window.\n'
  printf '\033[1;33m  !\033[0m  Having one like that in the bench is useful, but it is not typical dictation.\n'
fi

mkdir -p "$FIXTURES_DIR"
OUT="$FIXTURES_DIR/${NAME}.wav"

if [ -f "$OUT" ]; then
  printf '%s already exists. Overwrite? [y/N] ' "$OUT"
  read -r answer
  case "$answer" in
    [yY]*) ;;
    *) echo "cancelled."; exit 0 ;;
  esac
fi

echo
info "Recording ${DURATION}s on device [$DEVICE] → $OUT"
echo "    Speak the way you really speak: normal pace, no announcer voice."
echo
for i in 3 2 1; do printf '\r    starting in %d... ' "$i"; sleep 1; done
printf '\r\033[1;32m    SPEAK NOW\033[0m (%ss)          \n' "$DURATION"

ffmpeg -hide_banner -loglevel error \
  -f avfoundation -i ":$DEVICE" \
  -t "$DURATION" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  -y "$OUT" || fail "ffmpeg failed. Check the terminal's Microphone permission in
      System Settings → Privacy & Security → Microphone."

echo
info "Checking the format"
afinfo "$OUT" | grep -E 'Data format|estimated duration' | sed 's/^/    /'

# Confirms it came out exactly 16 kHz mono — the rest of the bench depends on it.
if afinfo "$OUT" | grep -q '16000 Hz.*1 ch'; then
  printf '\033[1;32m  ok\033[0m %s ready\n' "$OUT"
else
  fail "the file did not come out as 16 kHz mono. Do not use it — re-record."
fi
