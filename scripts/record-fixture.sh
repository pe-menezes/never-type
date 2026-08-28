#!/bin/bash
# Grava um áudio de referência já no formato que o whisper-cli consome:
# 16 kHz, mono, PCM 16-bit. Gravar no QuickTime dá 44,1 kHz estéreo em m4a e
# a bancada rejeita — por isso este script existe.
#
# Uso:
#   scripts/record-fixture.sh <nome> [segundos] [índice-do-dispositivo]
#
# Exemplos:
#   scripts/record-fixture.sh 01-fala-normal
#   scripts/record-fixture.sh 02-termos-tecnicos 18
#   scripts/record-fixture.sh 03-frase-curta 12 2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/fixtures"

NAME="${1:-}"
DURATION="${2:-15}"
DEVICE="${3:-0}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

command -v ffmpeg >/dev/null || fail "ffmpeg não encontrado. brew install ffmpeg"

if [ -z "$NAME" ]; then
  echo "uso: scripts/record-fixture.sh <nome> [segundos] [índice-do-dispositivo]"
  echo
  info "Dispositivos de áudio disponíveis:"
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | sed -n '/AVFoundation audio devices/,/^\[in#/p' \
    | grep -E '^\[AVFoundation.*\[[0-9]+\]' \
    | sed -E 's/^\[[^]]*\] /  /'
  echo
  echo "Roteiro do que gravar: fixtures/README.md"
  exit 1
fi

# A janela de 10–20s da spec original foi revogada: a bancada precisa de ditado
# curto E longo, porque o Whisper processa em janelas de 30s e só a variação
# revela esse degrau. Aqui vale um piso de sanidade e um aviso, não uma trava.
if [ "$DURATION" -lt 3 ] || [ "$DURATION" -gt 120 ]; then
  fail "duração fora do razoável para um fixture (pedido: ${DURATION}s). Use de 3 a 120."
fi
if [ "$DURATION" -gt 30 ]; then
  printf '\033[1;33m  !\033[0m  acima de 30s o áudio ocupa mais de uma janela do Whisper.\n'
  printf '\033[1;33m  !\033[0m  É útil ter um assim na bancada, mas não é ditado típico.\n'
fi

mkdir -p "$FIXTURES_DIR"
OUT="$FIXTURES_DIR/${NAME}.wav"

if [ -f "$OUT" ]; then
  printf 'Já existe %s. Sobrescrever? [y/N] ' "$OUT"
  read -r answer
  case "$answer" in
    [yY]*) ;;
    *) echo "cancelado."; exit 0 ;;
  esac
fi

echo
info "Gravando ${DURATION}s no dispositivo [$DEVICE] → $OUT"
echo "    Fale como você fala de verdade: ritmo normal, sem locução."
echo
for i in 3 2 1; do printf '\r    começando em %d... ' "$i"; sleep 1; done
printf '\r\033[1;32m    FALE AGORA\033[0m (%ss)          \n' "$DURATION"

ffmpeg -hide_banner -loglevel error \
  -f avfoundation -i ":$DEVICE" \
  -t "$DURATION" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  -y "$OUT" || fail "ffmpeg falhou. Confira a permissão de Microfone do terminal em
      Ajustes do Sistema → Privacidade e Segurança → Microfone."

echo
info "Verificando formato"
afinfo "$OUT" | grep -E 'Data format|estimated duration' | sed 's/^/    /'

# Confirma que saiu exatamente 16 kHz mono — o resto da bancada depende disso.
if afinfo "$OUT" | grep -q '16000 Hz.*1 ch'; then
  printf '\033[1;32m  ok\033[0m %s pronto\n' "$OUT"
else
  fail "o arquivo não saiu em 16 kHz mono. Não use — regrave."
fi
