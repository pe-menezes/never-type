#!/bin/bash
# Prepara a bancada de latência: instala whisper-cpp, prova que o backend Metal
# carrega, e constrói os modelos ggml quantizados em models/.
#
# Idempotente: rodar de novo não refaz nada que já está pronto.
#
# Por que não baixa o .bin pronto da HuggingFace: em redes que filtram por
# domínio, ela costuma estar na lista de bloqueio — e é lá que moram os arquivos
# ggml. O CDN da OpenAI, que serve os checkpoints .pt originais, raramente está.
# Então o caminho é pegar o .pt de lá e converter: um passo a mais, e o setup
# funciona em rede restrita.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$REPO_ROOT/models"
BUILD_DIR="$REPO_ROOT/.cache"
PT_CACHE="$HOME/.cache/whisper"
CDN="https://openaipublic.azureedge.net/main/whisper/models"

# Candidatos da spec. Turbo é o favorito; small é o piso de latência.
# Formato: nome-ggml : nome-openai : sha256 (que também é o path no CDN) : quant : piso em MB
#
# O piso é por modelo e proporcional ao artefato real (docs/armadilhas.md): o
# magic está certo num arquivo truncado, então só o tamanho pega conversão ou
# quantização interrompida. Tamanhos registrados neste repositório: turbo-q5_0
# tem 547 MB (piso 400 — o mesmo que o app exige em ModelStore.minimumBytes) e
# small-q5_1 tem 181 MB (piso 130). O de medium-q5_0 não foi registrado; pelo
# CLAUDE.md os três somam 1,2 GB, o que o põe entre ~420 e ~520 MB, e 400 fica
# abaixo de qualquer leitura disso. Confira: stat -f%z models/ggml-medium-q5_0.bin
MODELS=(
  "large-v3-turbo-q5_0:large-v3-turbo:aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a:q5_0:400"
  "medium-q5_0:medium:345ae4da62f9b3d59415adc60127b97c714f32e89e936602e85993674d08dcb1:q5_0:400"
  "small-q5_1:small:9ecf779972d90ba49c06d968637d720dd632c55bbf19d441fb42bf17a411e794:q5_1:130"
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

size_mb() { echo "$(( $(stat -f%z "$1") / 1048576 ))"; }

# --- pré-requisitos ---------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || fail "esta bancada só faz sentido no macOS."
[ "$(uname -m)" = "arm64" ]  || fail "é preciso Apple Silicon: sem Metal a medição não diz nada."
command -v brew >/dev/null   || fail "Homebrew não encontrado. Instale em https://brew.sh"

info "Verificando whisper-cpp"
if command -v whisper-cli >/dev/null 2>&1 && command -v whisper-quantize >/dev/null 2>&1; then
  ok "whisper-cli e whisper-quantize já instalados"
else
  info "Instalando whisper-cpp via Homebrew (traz ggml com Metal no bottle)"
  brew install whisper-cpp
fi
command -v whisper-cli      >/dev/null || fail "whisper-cli não ficou no PATH."
command -v whisper-quantize >/dev/null || fail "whisper-quantize não ficou no PATH."

# --- smoke test: o backend Metal carrega? -----------------------------------
#
# O ggml carrega backends dinamicamente. Se o Metal não entrar, a inferência cai
# pra CPU SEM ERRO — só fica ~11x mais lenta (encode 1635 ms contra 143 ms,
# medido; ver abaixo). Descobrir isso agora, com o modelo tiny que o próprio
# Homebrew instala, custa segundos. Descobrir depois custa a credibilidade de
# todos os números da bancada.

info "Smoke test do backend Metal"
SHARE_DIR="$(brew --prefix)/share/whisper-cpp"
[ -f "$SHARE_DIR/for-tests-ggml-tiny.bin" ] && [ -f "$SHARE_DIR/jfk.wav" ] \
  || fail "arquivos de teste do Homebrew ausentes em $SHARE_DIR. Tente: brew reinstall whisper-cpp"

# O ggml inicializa o device Metal só para enumerá-lo, mesmo quando a inferência
# roda em CPU: um log de `whisper-cli -ng` contém 37 linhas com a palavra "metal".
# Procurar por "metal" prova que o dylib carregou, não que a GPU foi usada — foi
# esse falso negativo que a auditoria da Parte 1 pegou. O discriminador real é o
# backend que o whisper escolheu. Custo do erro, medido: encode 1635 ms em CPU
# contra 143 ms em Metal, no mesmo modelo e áudio.
metal_is_active() {
  local log="$1"
  grep -q 'whisper_backend_init_gpu: no GPU found' "$log" && return 1
  grep -Eq 'whisper_backend_init_gpu:.*MTL' "$log"
}

SMOKE_LOG="$(mktemp -t nevertype-smoke)"
trap 'rm -f "$SMOKE_LOG"' EXIT
whisper-cli -m "$SHARE_DIR/for-tests-ggml-tiny.bin" -f "$SHARE_DIR/jfk.wav" -nt \
  >/dev/null 2>"$SMOKE_LOG" || { cat "$SMOKE_LOG" >&2; fail "whisper-cli falhou no smoke test."; }

if metal_is_active "$SMOKE_LOG"; then
  ok "Metal ativo:"
  grep -E 'whisper_backend_init_gpu:' "$SMOKE_LOG" | head -3 | sed 's/^/      /'
else
  echo "--- log ---" >&2; cat "$SMOKE_LOG" >&2; echo "-----------" >&2
  fail "backend Metal NÃO carregou — a inferência rodaria em CPU.
      Qualquer número medido assim é enganoso, então a bancada para aqui.
      Verifique: brew reinstall ggml whisper-cpp"
fi

# --- o que ainda falta ------------------------------------------------------

mkdir -p "$MODELS_DIR" "$PT_CACHE"

# Um .bin ggml válido começa com o magic 0x67676d6c. Ele é gravado como uint32
# little-endian, então os bytes no arquivo saem invertidos: 6c6d6767, que lido
# como texto vira "lmgg", não "ggml". Comparar o hex evita esse tropeço.
# Checar o magic pega download truncado e, principalmente, página de erro HTML
# salva como se fosse modelo — que é o que um proxy de filtragem devolve.
GGML_MAGIC_HEX=6c6d6767
# O piso de tamanho vem da tabela MODELS, por modelo. Até 29/08/2026 era um
# único GGML_MIN_MB=50 para os três — que aprovava um turbo de 547 MB parado em
# qualquer ponto acima disso. O magic sozinho não pega download nem conversão
# interrompidos no meio, porque os quatro primeiros bytes já teriam chegado.
is_valid_ggml() {  # <arquivo> <piso em MB>
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" | xxd -p)" = "$GGML_MAGIC_HEX" ] || return 1
  [ "$(( $(stat -f%z "$1") / 1048576 ))" -ge "$2" ]
}

pending=()
for entry in "${MODELS[@]}"; do
  IFS=':' read -r ggml_name _ _ _ min_mb <<< "$entry"
  is_valid_ggml "$MODELS_DIR/ggml-${ggml_name}.bin" "$min_mb" || pending+=("$entry")
done

if [ ${#pending[@]} -eq 0 ]; then
  info "Modelos em $MODELS_DIR"
  for entry in "${MODELS[@]}"; do
    IFS=':' read -r ggml_name _ _ _ _ <<< "$entry"
    printf '  %-26s %5s MB\n' "$ggml_name" "$(size_mb "$MODELS_DIR/ggml-${ggml_name}.bin")"
  done
  echo
  ok "Bancada pronta."
  echo "  Próximo: grave 3 fixtures com scripts/record-fixture.sh (veja fixtures/README.md),"
  echo "           depois rode scripts/bench.sh"
  exit 0
fi

# --- ferramental de conversão ------------------------------------------------
#
# Só montado quando há modelo a construir: são ~300 MB de torch.

mkdir -p "$BUILD_DIR"
CA_BUNDLE="$BUILD_DIR/corp-ca.pem"
VENV="$BUILD_DIR/venv"
WHISPER_REPO="$BUILD_DIR/whisper-repo"
CONVERTER="$BUILD_DIR/convert-pt-to-ggml.py"

# Proxy que inspeciona TLS injeta certificado próprio, e isso quebra o Python
# (CERTIFICATE_VERIFY_FAILED) enquanto o curl passa, porque o curl usa o keychain
# do macOS. Exportar o CA do sistema é a correção certa: passa a confiar na
# âncora que a máquina já tem, em vez de desligar a verificação.
if [ ! -s "$CA_BUNDLE" ]; then
  info "Exportando CA do sistema (proxy que inspeciona TLS quebra o Python sem isso)"
  security find-certificate -a -p /Library/Keychains/System.keychain  >"$CA_BUNDLE" 2>/dev/null || true
  security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain >>"$CA_BUNDLE" 2>/dev/null || true
  [ -s "$CA_BUNDLE" ] || fail "não consegui exportar o CA do sistema."
  ok "$(grep -c 'BEGIN CERTIFICATE' "$CA_BUNDLE") certificados"
fi
export SSL_CERT_FILE="$CA_BUNDLE" REQUESTS_CA_BUNDLE="$CA_BUNDLE"

if [ ! -x "$VENV/bin/python" ]; then
  info "Criando venv com torch (necessário só pra converter)"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" -q install --upgrade pip
  "$VENV/bin/pip" -q install torch numpy
fi
ok "torch $("$VENV/bin/python" -c 'import torch;print(torch.__version__)')"

# O conversor precisa dos assets do repo da OpenAI (mel filters e tokenizers).
# Mesmo rigor do conversor logo abaixo: o commit é fixado e conferido. Este
# repositório fornece os assets (mel filters e tokenizers) que alimentam a
# conversão do modelo — se mudarem sem aviso, o modelo sai diferente em silêncio.
OPENAI_WHISPER_COMMIT="5f86d1d86363843179951550570367b37c5d6f78"
if [ ! -d "$WHISPER_REPO/whisper/assets" ]; then
  info "Clonando assets de openai/whisper (GitHub passa na rede)"
  git clone --depth 1 -q https://github.com/openai/whisper.git "$WHISPER_REPO"
fi
got_commit="$(git -C "$WHISPER_REPO" rev-parse HEAD 2>/dev/null || echo desconhecido)"
[ "$got_commit" = "$OPENAI_WHISPER_COMMIT" ] || fail "openai/whisper em $WHISPER_REPO não é o commit esperado.
      esperado: $OPENAI_WHISPER_COMMIT
      obtido:   $got_commit
      Apague $WHISPER_REPO e rode de novo."

# Pinado na tag v1.9.2, a mesma versão do whisper-cpp que o Homebrew instala, e
# conferido por checksum. Baixar de `master` e executar seria confiar num alvo
# móvel: qualquer commit no upstream passaria a rodar nesta máquina sem revisão.
CONVERTER_URL="https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.9.2/models/convert-pt-to-ggml.py"
CONVERTER_SHA256="e874333f95c52725c23541b39e71594e01442a2a687c96e2e882493c45b887a2"

if [ ! -s "$CONVERTER" ] || [ "$(shasum -a 256 "$CONVERTER" | cut -d' ' -f1)" != "$CONVERTER_SHA256" ]; then
  info "Baixando conversor do whisper.cpp (v1.9.2)"
  curl -sSL --fail --max-time 60 -o "$CONVERTER" "$CONVERTER_URL" \
    || fail "não consegui baixar o conversor de $CONVERTER_URL"
  got="$(shasum -a 256 "$CONVERTER" | cut -d' ' -f1)"
  if [ "$got" != "$CONVERTER_SHA256" ]; then
    rm -f "$CONVERTER"
    fail "checksum do conversor não confere.
      esperado: $CONVERTER_SHA256
      obtido:   $got
      O arquivo foi removido. Não execute script baixado que não confere."
  fi
  ok "conversor conferido"
fi

# --- construção dos modelos --------------------------------------------------

for entry in "${pending[@]}"; do
  IFS=':' read -r ggml_name pt_name sha quant min_mb <<< "$entry"
  pt_file="$PT_CACHE/${pt_name}.pt"
  out_ggml="$MODELS_DIR/ggml-${ggml_name}.bin"

  info "Modelo $ggml_name"

  # 1. checkpoint .pt no CDN da OpenAI (o sha256 é também o path)
  if [ -f "$pt_file" ] && [ "$(shasum -a 256 "$pt_file" | cut -d' ' -f1)" = "$sha" ]; then
    ok "checkpoint já em cache ($(size_mb "$pt_file") MB)"
  else
    [ -f "$pt_file" ] && warn "checkpoint com checksum errado, rebaixando"
    curl -L --fail --retry 5 --retry-delay 3 --progress-bar \
         -o "$pt_file" "$CDN/$sha/${pt_name}.pt" \
      || fail "download de ${pt_name}.pt falhou.
      Se voltou 403, confira se o CDN da OpenAI também caiu na blocklist:
        curl -sIL $CDN/$sha/${pt_name}.pt"
    [ "$(shasum -a 256 "$pt_file" | cut -d' ' -f1)" = "$sha" ] \
      || { rm -f "$pt_file"; fail "${pt_name}.pt baixou corrompido (checksum) e foi removido."; }
    ok "baixado e conferido ($(size_mb "$pt_file") MB)"
  fi

  # 2. .pt -> ggml f16
  #
  # O f16 é maior que o quantizado (ocupa gigabytes, ver abaixo), então o piso
  # do quantizado vale para ele também: folgado, mas pega conversão interrompida.
  f16_dir="$BUILD_DIR/f16-$ggml_name"
  mkdir -p "$f16_dir"
  if ! is_valid_ggml "$f16_dir/ggml-model.bin" "$min_mb"; then
    info "  convertendo para ggml f16"
    "$VENV/bin/python" "$CONVERTER" "$pt_file" "$WHISPER_REPO" "$f16_dir" >/dev/null \
      || fail "conversão de $pt_name falhou."
  fi
  is_valid_ggml "$f16_dir/ggml-model.bin" "$min_mb" \
    || fail "conversão não produziu ggml válido (magic ggml e pelo menos $min_mb MB)."

  # 3. f16 -> quantizado
  info "  quantizando para $quant"
  whisper-quantize "$f16_dir/ggml-model.bin" "$out_ggml" "$quant" >/dev/null \
    || fail "quantização de $ggml_name falhou."
  is_valid_ggml "$out_ggml" "$min_mb" \
    || { rm -f "$out_ggml"; fail "quantização produziu arquivo inválido (magic ggml e pelo menos $min_mb MB)."; }

  # O f16 é intermediário e ocupa gigabytes. O .pt fica em cache: é a origem.
  rm -rf "$f16_dir"
  ok "$ggml_name pronto ($(size_mb "$out_ggml") MB)"
done

# --- resumo -----------------------------------------------------------------

echo
info "Modelos em $MODELS_DIR"
missing=0
for entry in "${MODELS[@]}"; do
  IFS=':' read -r ggml_name _ _ _ min_mb <<< "$entry"
  f="$MODELS_DIR/ggml-${ggml_name}.bin"
  if is_valid_ggml "$f" "$min_mb"; then
    printf '  %-26s %5s MB\n' "$ggml_name" "$(size_mb "$f")"
  else
    printf '  %-26s %s\n' "$ggml_name" "AUSENTE"
    missing=$((missing + 1))
  fi
done
echo
[ "$missing" -eq 0 ] || fail "$missing modelo(s) faltando. Rode o script de novo."

ok "Bancada pronta."
echo "  Próximo: grave 3 fixtures com scripts/record-fixture.sh (veja fixtures/README.md),"
echo "           depois rode scripts/bench.sh"
