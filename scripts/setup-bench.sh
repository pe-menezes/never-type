#!/bin/bash
# Prepares the latency bench: installs whisper-cpp, proves the Metal backend
# loads, and builds the quantized ggml models in models/.
#
# Idempotent: running again redoes nothing that is already done.
#
# Why it does not download the ready-made .bin from Hugging Face: on networks
# that filter by domain, it is often on the blocklist — and that is where the
# ggml files live. OpenAI's CDN, which serves the original .pt checkpoints,
# rarely is. So the path is to get the .pt from there and convert it: one extra
# step, and the setup works on a restricted network.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/model-artifacts.sh"
MODELS_DIR="$REPO_ROOT/models"
BUILD_DIR="$REPO_ROOT/.cache"
PT_CACHE="$HOME/.cache/whisper"
CDN="https://openaipublic.azureedge.net/main/whisper/models"

# Candidates from the spec. Turbo is the favorite; small is the latency floor.
# Format: ggml-name : openai-name : sha256 (also the path on the CDN) : quant : floor in MB
#
# Size floors reject clearly incomplete output. Completed models also require a
# matching SHA-256 receipt before reuse; size alone cannot detect truncation.
MODELS=(
  "large-v3-turbo-q5_0:large-v3-turbo:aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a:q5_0:400"
  "medium-q5_0:medium:345ae4da62f9b3d59415adc60127b97c714f32e89e936602e85993674d08dcb1:q5_0:400"
  "small-q5_1:small:9ecf779972d90ba49c06d968637d720dd632c55bbf19d441fb42bf17a411e794:q5_1:130"
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

size_mb() { echo "$(( $(stat -f%z "$1") / 1048576 ))"; }

# --- prerequisites ------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || fail "this bench only makes sense on macOS."
[ "$(uname -m)" = "arm64" ]  || fail "Apple Silicon is required: without Metal the measurement says nothing."
command -v brew >/dev/null   || fail "Homebrew not found. Install it from https://brew.sh"

info "Checking whisper-cpp"
if command -v whisper-cli >/dev/null 2>&1 && command -v whisper-quantize >/dev/null 2>&1; then
  ok "whisper-cli and whisper-quantize already installed"
else
  info "Installing whisper-cpp via Homebrew (brings ggml with Metal in the bottle)"
  brew install whisper-cpp
fi
command -v whisper-cli      >/dev/null || fail "whisper-cli did not end up on the PATH."
command -v whisper-quantize >/dev/null || fail "whisper-quantize did not end up on the PATH."

# --- smoke test: does the Metal backend load? ---------------------------------
#
# ggml loads backends dynamically. If Metal does not come in, inference falls
# back to the CPU WITH NO ERROR — it just gets ~11x slower (encode 1635 ms
# against 143 ms, measured; see below). Finding that out now, with the tiny
# model Homebrew itself installs, costs seconds. Finding out later costs the
# credibility of every number in the bench.

info "Metal backend smoke test"
SHARE_DIR="$(brew --prefix)/share/whisper-cpp"
[ -f "$SHARE_DIR/for-tests-ggml-tiny.bin" ] && [ -f "$SHARE_DIR/jfk.wav" ] \
  || fail "Homebrew's test files are missing from $SHARE_DIR. Try: brew reinstall whisper-cpp"

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

SMOKE_LOG="$(mktemp -t nevertype-smoke)"
trap 'rm -f "$SMOKE_LOG"' EXIT
whisper-cli -m "$SHARE_DIR/for-tests-ggml-tiny.bin" -f "$SHARE_DIR/jfk.wav" -nt \
  >/dev/null 2>"$SMOKE_LOG" || { cat "$SMOKE_LOG" >&2; fail "whisper-cli failed in the smoke test."; }

if metal_is_active "$SMOKE_LOG"; then
  ok "Metal active:"
  grep -E 'whisper_backend_init_gpu:' "$SMOKE_LOG" | head -3 | sed 's/^/      /'
else
  echo "--- log ---" >&2; cat "$SMOKE_LOG" >&2; echo "-----------" >&2
  fail "the Metal backend did NOT load — inference would run on the CPU.
      Any number measured this way is misleading, so the bench stops here.
      Check: brew reinstall ggml whisper-cpp"
fi

# --- what is still missing ----------------------------------------------------

mkdir -p "$MODELS_DIR" "$PT_CACHE"

# ggml's little-endian magic is 6c6d6767 ("lmgg"). Check it with the size
# floor before generating or verifying a checksum receipt.
GGML_MAGIC_HEX=6c6d6767
is_valid_ggml() {  # <file> <floor in MB>
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" | xxd -p)" = "$GGML_MAGIC_HEX" ] || return 1
  [ "$(( $(stat -f%z "$1") / 1048576 ))" -ge "$2" ]
}

pending=()
for entry in "${MODELS[@]}"; do
  IFS=':' read -r ggml_name _ _ _ min_mb <<< "$entry"
  if ! is_valid_ggml "$MODELS_DIR/ggml-${ggml_name}.bin" "$min_mb" \
      || ! model_has_receipt "$MODELS_DIR/ggml-${ggml_name}.bin"; then
    pending+=("$entry")
  fi
done

if [ ${#pending[@]} -eq 0 ]; then
  info "Models in $MODELS_DIR"
  for entry in "${MODELS[@]}"; do
    IFS=':' read -r ggml_name _ _ _ _ <<< "$entry"
    printf '  %-26s %5s MB\n' "$ggml_name" "$(size_mb "$MODELS_DIR/ggml-${ggml_name}.bin")"
  done
  echo
  ok "Bench ready."
  echo "  Next: record 3 fixtures with scripts/record-fixture.sh (see fixtures/README.md),"
  echo "        then run scripts/bench.sh"
  exit 0
fi

# --- conversion tooling -------------------------------------------------------
#
# Only set up when there is a model to build: it is ~300 MB of torch.

mkdir -p "$BUILD_DIR"
CA_BUNDLE="$BUILD_DIR/corp-ca.pem"
VENV="$BUILD_DIR/venv"
WHISPER_REPO="$BUILD_DIR/whisper-repo"
CONVERTER="$BUILD_DIR/convert-pt-to-ggml.py"

# A TLS-inspecting proxy injects its own certificate, and that breaks Python
# (CERTIFICATE_VERIFY_FAILED) while curl passes, because curl uses the macOS
# keychain. Exporting the system CA is the right fix: Python starts trusting the
# anchor the machine already has, instead of turning verification off.
if [ ! -s "$CA_BUNDLE" ]; then
  info "Exporting the system CA (a TLS-inspecting proxy breaks Python without it)"
  security find-certificate -a -p /Library/Keychains/System.keychain  >"$CA_BUNDLE" 2>/dev/null || true
  security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain >>"$CA_BUNDLE" 2>/dev/null || true
  [ -s "$CA_BUNDLE" ] || fail "could not export the system CA."
  ok "$(grep -c 'BEGIN CERTIFICATE' "$CA_BUNDLE") certificates"
fi
export SSL_CERT_FILE="$CA_BUNDLE" REQUESTS_CA_BUNDLE="$CA_BUNDLE"

ensure_conversion_python "$VENV" || fail "could not prepare Python dependencies. Check the error above and rerun this script."

# The converter needs the assets from OpenAI's repo (mel filters and tokenizers).
# Same rigor as the converter right below: the commit is pinned and checked.
# This repository supplies the assets (mel filters and tokenizers) that feed the
# model conversion — if they change without notice, the model comes out
# different in silence.
OPENAI_WHISPER_COMMIT="5f86d1d86363843179951550570367b37c5d6f78"
ensure_pinned_assets "$WHISPER_REPO" https://github.com/openai/whisper.git "$OPENAI_WHISPER_COMMIT" \
  || fail "could not prepare the pinned openai/whisper assets. Check the error above and rerun."

# Pinned to tag v1.9.2, the same whisper-cpp version Homebrew installs, and
# checked by checksum. Downloading from `master` and executing it would be
# trusting a moving target: any upstream commit would start running on this
# machine without review.
CONVERTER_URL="https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.9.2/models/convert-pt-to-ggml.py"
CONVERTER_SHA256="e874333f95c52725c23541b39e71594e01442a2a687c96e2e882493c45b887a2"

if [ ! -s "$CONVERTER" ] || [ "$(shasum -a 256 "$CONVERTER" | cut -d' ' -f1)" != "$CONVERTER_SHA256" ]; then
  info "Downloading the whisper.cpp converter (v1.9.2)"
  curl -sSL --fail --max-time 60 -o "$CONVERTER" "$CONVERTER_URL" \
    || fail "could not download the converter from $CONVERTER_URL"
  got="$(shasum -a 256 "$CONVERTER" | cut -d' ' -f1)"
  if [ "$got" != "$CONVERTER_SHA256" ]; then
    rm -f "$CONVERTER"
    fail "the converter's checksum does not match.
      expected: $CONVERTER_SHA256
      got:      $got
      The file was removed. Do not execute a downloaded script that does not match."
  fi
  ok "converter verified"
fi

# --- building the models ------------------------------------------------------

for entry in "${pending[@]}"; do
  IFS=':' read -r ggml_name pt_name sha quant min_mb <<< "$entry"
  pt_file="$PT_CACHE/${pt_name}.pt"
  out_ggml="$MODELS_DIR/ggml-${ggml_name}.bin"

  info "Model $ggml_name"

  # 1. .pt checkpoint on OpenAI's CDN (the sha256 is also the path)
  if [ -f "$pt_file" ] && [ "$(shasum -a 256 "$pt_file" | cut -d' ' -f1)" = "$sha" ]; then
    ok "checkpoint already cached ($(size_mb "$pt_file") MB)"
  else
    [ -f "$pt_file" ] && warn "checkpoint with the wrong checksum, downloading again"
    curl -L --fail --retry 5 --retry-delay 3 --progress-bar \
         -o "$pt_file" "$CDN/$sha/${pt_name}.pt" \
      || fail "download of ${pt_name}.pt failed.
      If it returned 403, check whether OpenAI's CDN is also on your network's blocklist:
        curl -sIL $CDN/$sha/${pt_name}.pt"
    [ "$(shasum -a 256 "$pt_file" | cut -d' ' -f1)" = "$sha" ] \
      || { rm -f "$pt_file"; fail "${pt_name}.pt downloaded corrupt (checksum) and was removed."; }
    ok "downloaded and verified ($(size_mb "$pt_file") MB)"
  fi

  # Both producers write into temporary locations. A killed conversion must
  # never become a cached input on the next run.
  f16_dir="$(mktemp -d "$BUILD_DIR/f16-${ggml_name}.XXXXXX")"
  out_partial="$(mktemp "$MODELS_DIR/.${ggml_name}.XXXXXX")"
  trap 'rm -f "$SMOKE_LOG" "${out_partial:-}"; rm -rf "${f16_dir:-}"' EXIT
  info "  converting to ggml f16"
  "$VENV/bin/python" "$CONVERTER" "$pt_file" "$WHISPER_REPO" "$f16_dir" >/dev/null \
    || fail "conversion of $pt_name failed."
  is_valid_ggml "$f16_dir/ggml-model.bin" "$min_mb" \
    || fail "conversion did not produce a valid ggml."

  info "  quantizing to $quant"
  whisper-quantize "$f16_dir/ggml-model.bin" "$out_partial" "$quant" >/dev/null \
    || fail "quantization of $ggml_name failed."
  is_valid_ggml "$out_partial" "$min_mb" \
    || fail "quantization produced an invalid file."
  # Clear the old receipt before replacement: interruption between the two
  # renames causes a safe rebuild, never approval of unverified bytes.
  rm -f "$out_ggml.sha256"
  mv "$out_partial" "$out_ggml"
  model_write_receipt "$out_ggml" || fail "could not record the model checksum."
  rm -rf "$f16_dir"
  ok "$ggml_name ready ($(size_mb "$out_ggml") MB)"
done

# --- summary ------------------------------------------------------------------

echo
info "Models in $MODELS_DIR"
missing=0
for entry in "${MODELS[@]}"; do
  IFS=':' read -r ggml_name _ _ _ min_mb <<< "$entry"
  f="$MODELS_DIR/ggml-${ggml_name}.bin"
  if is_valid_ggml "$f" "$min_mb" && model_has_receipt "$f"; then
    printf '  %-26s %5s MB\n' "$ggml_name" "$(size_mb "$f")"
  else
    printf '  %-26s %s\n' "$ggml_name" "MISSING"
    missing=$((missing + 1))
  fi
done
echo
[ "$missing" -eq 0 ] || fail "$missing model(s) missing. Run the script again."

ok "Bench ready."
echo "  Next: record 3 fixtures with scripts/record-fixture.sh (see fixtures/README.md),"
echo "        then run scripts/bench.sh"
