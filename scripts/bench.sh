#!/bin/bash
# Latency bench: runs every model against every fixture, measures wall-clock
# time, separates the model load time, and prints the table that backs the
# decision in docs/model-choice.md.
#
# Usage: scripts/bench.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$REPO_ROOT/models"
FIXTURES_DIR="$REPO_ROOT/fixtures"
# Every run gets its own directory: the evidence that backs the model decision
# cannot be silently overwritten by the next run.
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$REPO_ROOT/bench-out/$RUN_ID"

# Ceiling declared in the PRD: above it the dictation flow breaks and the person
# goes back to typing.
CEILING_MS=1500

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f", time()*1000'; }

# ggml initializes the Metal device just to enumerate it, even when inference
# runs on the CPU: a `whisper-cli -ng` log contains 37 lines with the word
# "metal". Searching for "metal" proves the dylib loaded, not that the GPU was
# used — that false negative is what the Part 1 audit caught. The real
# discriminator is the backend whisper chose. Cost of the mistake, measured:
# encode 1635 ms on CPU against 143 ms on Metal, same model and audio.
metal_is_active() {
  local log="$1"
  grep -q 'whisper_backend_init_gpu: no GPU found' "$log" && return 1
  grep -Eq 'whisper_backend_init_gpu:.*MTL' "$log"
}

command -v whisper-cli >/dev/null || fail "whisper-cli not found. Run scripts/setup-bench.sh"
command -v afinfo      >/dev/null || fail "afinfo not found (it should ship with macOS)."

# --- collection ---------------------------------------------------------------

shopt -s nullglob
MODELS=( "$MODELS_DIR"/ggml-*.bin )
FIXTURES=( "$FIXTURES_DIR"/*.wav )
shopt -u nullglob

[ ${#MODELS[@]} -gt 0 ]   || fail "no model in $MODELS_DIR. Run scripts/setup-bench.sh"
[ ${#FIXTURES[@]} -gt 0 ] || fail "no fixture in $FIXTURES_DIR.
      Record with: scripts/record-fixture.sh <name>
      Script in: fixtures/README.md"

if [ ${#FIXTURES[@]} -lt 3 ]; then
  warn "only ${#FIXTURES[@]} fixture(s). The spec asks for at least 3, with at least one"
  warn "mixing Portuguese and English technical terms. The bench runs, but the"
  warn "decision comes out weak."
fi

# whisper-cli requires 16 kHz. Validating here gives a useful message instead of
# a raw error deep inside, one model later.
for wav in "${FIXTURES[@]}"; do
  if ! afinfo "$wav" | grep -q '16000 Hz'; then
    fail "$(basename "$wav") is not 16 kHz.
      Re-record with scripts/record-fixture.sh — QuickTime records at 44.1 kHz."
  fi
done

# Duration of each fixture, in ms. Without it a 5 s clip cannot be compared with
# a 61 s one: raw wall-clock time would say more about the file size than about
# the model.
declare -a DURS
for wav in "${FIXTURES[@]}"; do
  d=$(afinfo "$wav" | sed -n 's/.*estimated duration: \([0-9.]*\) sec.*/\1/p')
  DURS+=("$(echo "$d" | awk '{printf "%.0f", $1*1000}')")
done

mkdir -p "$OUT_DIR"
ln -sfn "$RUN_ID" "$REPO_ROOT/bench-out/latest"

# Warm the page cache before measuring.
#
# Without this, the first access to each model pays the fault-in of hundreds of
# MB from disk — measured: 5087 ms of wall-clock against 976 ms of actual
# processing. The old metric (wall-clock minus `load time`) did not discount
# that, because whisper's counter covers only deserialization, not reading the
# file. The result was a verdict that depended on whether the model was cached.
info "Warming the models' page cache"
for model_path in "${MODELS[@]}"; do
  cat "$model_path" > /dev/null
done

info "${#MODELS[@]} model(s) × ${#FIXTURES[@]} fixture(s) = $(( ${#MODELS[@]} * ${#FIXTURES[@]} )) runs"
echo

# --- execution ----------------------------------------------------------------

RESULTS=()   # "model|fixture|wall_ms|load_ms|hot_ms"

for model_path in "${MODELS[@]}"; do
  model_name="$(basename "$model_path" .bin)"; model_name="${model_name#ggml-}"

  fi=-1
  for wav in "${FIXTURES[@]}"; do
    fi=$((fi + 1))
    dur_ms="${DURS[$fi]}"
    fixture_name="$(basename "$wav" .wav)"
    tag="${model_name}__${fixture_name}"
    txt="$OUT_DIR/${tag}.txt"
    log="$OUT_DIR/${tag}.log"

    printf '  %-26s %-24s ' "$model_name" "$fixture_name"

    t0=$(now_ms)
    if ! whisper-cli -m "$model_path" -f "$wav" -l pt -nt >"$txt" 2>"$log"; then
      echo "FAILED"
      cat "$log" >&2
      fail "whisper-cli failed on $tag"
    fi
    t1=$(now_ms)
    wall=$(( t1 - t0 ))

    # DoD 4: without Metal, the measured number is CPU and misleads. The bench stops.
    if ! metal_is_active "$log"; then
      echo "NO METAL"
      grep -E 'whisper_backend_init_gpu:' "$log" >&2 || true
      fail "inference did not run on Metal in this run.
      Any time measured this way is CPU and does not represent the app.
      Check: brew reinstall ggml whisper-cpp"
    fi

    # The `|| true` is not decoration: under `set -e` and `pipefail`, a grep that
    # does not match takes the whole script down at the assignment, and the
    # fallback below never ran.
    field_ms() { { grep -i "$1" "$log" || true; } \
      | tail -1 | sed -E 's/.*=[[:space:]]*([0-9.]+).*/\1/' | cut -d. -f1; }

    load_ms=$(field_ms 'load time'); [ -n "${load_ms:-}" ] || load_ms=0
    total_ms=$(field_ms 'total time'); [ -n "${total_ms:-}" ] || total_ms=0

    # Whisper's own stopwatch, not wall-clock time.
    #
    # Wall-clock includes process spawn, dyld, and the model fault-in — noise
    # that does not exist in the app, where the model is already loaded. `total
    # time` is measured inside the process and is what comes closest to the real
    # cost of a dictation.
    hot_ms=$(( total_ms > 0 ? total_ms - load_ms : wall - load_ms ))
    [ "$hot_ms" -gt 0 ] || hot_ms=1

    # Whisper processes in 30s windows: a 5s dictation costs the same as a 25s
    # one. Measuring "per second of audio" would describe the real cost badly —
    # what matters is how many windows the audio occupies and what each one costs.
    windows=$(( (dur_ms + 29999) / 30000 ))
    per_w=$(( hot_ms / windows ))
    printf '%6s ms wall · %5s ms internal · %s window(s) · cost ~%5s ms\n' \
      "$wall" "$total_ms" "$windows" "$hot_ms"
    RESULTS+=("${model_name}|${fixture_name}|${wall}|${load_ms}|${hot_ms}|${dur_ms}|${windows}|${per_w}")
  done
done

# --- table --------------------------------------------------------------------

echo
info "Results"
echo
printf '  %-24s %-14s %7s %8s %10s %10s %11s\n' "MODEL" "FIXTURE" "AUDIO" "WINDOWS" "WALL" "HOT" "PER WINDOW"
printf '  %-24s %-14s %7s %8s %10s %10s %11s\n' "------------------------" "--------------" "-------" "--------" "----------" "----------" "-----------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r m f wall load hot dur win per <<< "$r"
  printf '  %-24s %-14s %5ss %8s %8s ms %8s ms %8s ms\n' "$m" "$f" "$(( dur / 1000 ))" "$win" "$wall" "$hot" "$per"
done

# --- transcriptions -----------------------------------------------------------

echo
info "Transcriptions (this is where technical vocabulary is judged)"
for model_path in "${MODELS[@]}"; do
  model_name="$(basename "$model_path" .bin)"; model_name="${model_name#ggml-}"
  echo
  printf '\033[1m  %s\033[0m\n' "$model_name"
  for wav in "${FIXTURES[@]}"; do
    fixture_name="$(basename "$wav" .wav)"
    printf '    %s:\n' "$fixture_name"
    txt="$OUT_DIR/${model_name}__${fixture_name}.txt"
    # An empty transcription is a legitimate bench result (silent audio, a model
    # that recognized nothing) and needs to show up as such — not take the
    # report down.
    if grep -q '[^[:space:]]' "$txt" 2>/dev/null; then
      sed 's/^[[:space:]]*//' "$txt" | grep -v '^$' | sed 's/^/      /'
    else
      printf '      \033[1;31m(empty — the model transcribed nothing)\033[0m\n'
    fi
  done
done

# --- reading for the decision document ----------------------------------------

echo
info "Cost of a real dictation (PRD ceiling: ${CEILING_MS} ms)"
echo
echo "  A dictation of up to 30s occupies one window and costs the same, whether 5s or 25s."
echo "  That is the number measured below — not projected."
echo

printf '  %-24s %16s %14s   %s\n' "MODEL" "DICTATION <=30s" "PER WINDOW" "VERDICT"
for model_path in "${MODELS[@]}"; do
  model_name="$(basename "$model_path" .bin)"; model_name="${model_name#ggml-}"
  sum_short=0; n_short=0; sum_w=0; n_w=0
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r m f wall load hot dur win per <<< "$r"
    [ "$m" = "$model_name" ] || continue
    sum_w=$(( sum_w + per )); n_w=$(( n_w + 1 ))
    if [ "$win" -eq 1 ]; then sum_short=$(( sum_short + hot )); n_short=$(( n_short + 1 )); fi
  done
  [ "$n_w" -gt 0 ] || continue
  avg_w=$(( sum_w / n_w ))
  if [ "$n_short" -gt 0 ]; then avg_short=$(( sum_short / n_short )); else avg_short="$avg_w"; fi
  if [ "$avg_short" -le "$CEILING_MS" ]; then
    verdict=$'\033[1;32mwithin the ceiling\033[0m'
  else
    verdict=$'\033[1;31mover the ceiling\033[0m'
  fi
  printf '  %-24s %13s ms %11s ms   %b\n' "$model_name" "$avg_short" "$avg_w" "$verdict"
done

echo
echo "  HOT comes from whisper's internal stopwatch (total minus load), not from"
echo "  wall-clock time: wall-clock includes process spawn and reading the model"
echo "  from disk, which do not exist in the app with the model already loaded."
echo "  PER WINDOW divides by the number of 30s windows, to compare long clips."
echo
echo "  Raw output in: bench-out/$RUN_ID/  (shortcut: bench-out/latest/)"
echo "  Now fill in: docs/model-choice.md"
