#!/bin/bash
# Bancada de latência: roda cada modelo contra cada fixture, mede tempo de
# parede, separa o tempo de carga do modelo e imprime a tabela que sustenta a
# decisão em docs/decisao-modelo.md.
#
# Uso: scripts/bench.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$REPO_ROOT/models"
FIXTURES_DIR="$REPO_ROOT/fixtures"
# Cada execução ganha seu diretório: a evidência que sustenta a decisão de
# modelo não pode ser sobrescrita silenciosamente pela execução seguinte.
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$REPO_ROOT/bench-out/$RUN_ID"

# Teto declarado no PRD: acima disso o fluxo de ditado quebra e a pessoa
# volta a digitar.
CEILING_MS=1500

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f", time()*1000'; }

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

command -v whisper-cli >/dev/null || fail "whisper-cli não encontrado. Rode scripts/setup-bench.sh"
command -v afinfo      >/dev/null || fail "afinfo não encontrado (deveria vir com o macOS)."

# --- coleta -----------------------------------------------------------------

shopt -s nullglob
MODELS=( "$MODELS_DIR"/ggml-*.bin )
FIXTURES=( "$FIXTURES_DIR"/*.wav )
shopt -u nullglob

[ ${#MODELS[@]} -gt 0 ]   || fail "nenhum modelo em $MODELS_DIR. Rode scripts/setup-bench.sh"
[ ${#FIXTURES[@]} -gt 0 ] || fail "nenhum fixture em $FIXTURES_DIR.
      Grave com: scripts/record-fixture.sh <nome>
      Roteiro em: fixtures/README.md"

if [ ${#FIXTURES[@]} -lt 3 ]; then
  warn "só ${#FIXTURES[@]} fixture(s). A spec pede ao menos 3, com pelo menos um"
  warn "misturando português e termos técnicos em inglês. A bancada roda, mas a"
  warn "decisão fica fraca."
fi

# whisper-cli exige 16 kHz. Validar aqui dá mensagem útil em vez de erro cru
# lá dentro, um modelo depois.
for wav in "${FIXTURES[@]}"; do
  if ! afinfo "$wav" | grep -q '16000 Hz'; then
    fail "$(basename "$wav") não está em 16 kHz.
      Regrave com scripts/record-fixture.sh — o QuickTime grava em 44,1 kHz."
  fi
done

# Duração de cada fixture, em ms. Sem isso não dá para comparar um clipe de 5 s
# com um de 61 s: o tempo bruto de parede diria mais sobre o tamanho do arquivo
# do que sobre o modelo.
declare -a DURS
for wav in "${FIXTURES[@]}"; do
  d=$(afinfo "$wav" | sed -n 's/.*estimated duration: \([0-9.]*\) sec.*/\1/p')
  DURS+=("$(echo "$d" | awk '{printf "%.0f", $1*1000}')")
done

mkdir -p "$OUT_DIR"
ln -sfn "$RUN_ID" "$REPO_ROOT/bench-out/latest"

# Aquece o cache de página antes de medir.
#
# Sem isto, o primeiro acesso a cada modelo paga o fault-in de centenas de MB do
# disco — medido: 5087 ms de parede contra 976 ms de processamento real. A
# métrica antiga (parede menos `load time`) não descontava isso, porque o
# contador do whisper cobre só a desserialização, não a leitura do arquivo. O
# resultado era um veredito que dependia de o modelo estar em cache ou não.
info "Aquecendo o cache de página dos modelos"
for model_path in "${MODELS[@]}"; do
  cat "$model_path" > /dev/null
done

info "${#MODELS[@]} modelo(s) × ${#FIXTURES[@]} fixture(s) = $(( ${#MODELS[@]} * ${#FIXTURES[@]} )) execuções"
echo

# --- execução ---------------------------------------------------------------

RESULTS=()   # "modelo|fixture|wall_ms|load_ms|hot_ms"

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
      echo "FALHOU"
      cat "$log" >&2
      fail "whisper-cli falhou em $tag"
    fi
    t1=$(now_ms)
    wall=$(( t1 - t0 ))

    # DoD 4: sem Metal, o número medido é de CPU e engana. A bancada para.
    if ! metal_is_active "$log"; then
      echo "SEM METAL"
      grep -E 'whisper_backend_init_gpu:' "$log" >&2 || true
      fail "a inferência não rodou em Metal nesta execução.
      Qualquer tempo medido assim é de CPU e não representa o app.
      Verifique: brew reinstall ggml whisper-cpp"
    fi

    # O `|| true` não é decoração: com `set -e` e `pipefail`, um grep que não casa
    # derruba o script inteiro na atribuição, e o fallback abaixo nunca rodava.
    field_ms() { { grep -i "$1" "$log" || true; } \
      | tail -1 | sed -E 's/.*=[[:space:]]*([0-9.]+).*/\1/' | cut -d. -f1; }

    load_ms=$(field_ms 'load time'); [ -n "${load_ms:-}" ] || load_ms=0
    total_ms=$(field_ms 'total time'); [ -n "${total_ms:-}" ] || total_ms=0

    # O cronômetro do próprio whisper, e não o tempo de parede.
    #
    # Parede inclui spawn do processo, dyld, e fault-in do modelo — ruído que não
    # existe no app, onde o modelo já está carregado. `total time` é medido dentro
    # do processo e é o que mais se aproxima do custo real de um ditado.
    hot_ms=$(( total_ms > 0 ? total_ms - load_ms : wall - load_ms ))
    [ "$hot_ms" -gt 0 ] || hot_ms=1

    # O Whisper processa em janelas de 30s: um ditado de 5s custa o mesmo que um
    # de 25s. Medir "por segundo de áudio" descreveria mal o custo real — o que
    # importa é quantas janelas o áudio ocupa e quanto custa cada uma.
    windows=$(( (dur_ms + 29999) / 30000 ))
    per_w=$(( hot_ms / windows ))
    printf '%6s ms parede · %5s ms interno · %s janela(s) · custo ~%5s ms\n' \
      "$wall" "$total_ms" "$windows" "$hot_ms"
    RESULTS+=("${model_name}|${fixture_name}|${wall}|${load_ms}|${hot_ms}|${dur_ms}|${windows}|${per_w}")
  done
done

# --- tabela -----------------------------------------------------------------

echo
info "Resultados"
echo
printf '  %-24s %-14s %7s %8s %10s %10s %11s\n' "MODELO" "FIXTURE" "ÁUDIO" "JANELAS" "PAREDE" "QUENTE" "POR JANELA"
printf '  %-24s %-14s %7s %8s %10s %10s %11s\n' "------------------------" "--------------" "-------" "--------" "----------" "----------" "-----------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r m f wall load hot dur win per <<< "$r"
  printf '  %-24s %-14s %5ss %8s %8s ms %8s ms %8s ms\n' "$m" "$f" "$(( dur / 1000 ))" "$win" "$wall" "$hot" "$per"
done

# --- transcrições -----------------------------------------------------------

echo
info "Transcrições (é aqui que se julga o vocabulário técnico)"
for model_path in "${MODELS[@]}"; do
  model_name="$(basename "$model_path" .bin)"; model_name="${model_name#ggml-}"
  echo
  printf '\033[1m  %s\033[0m\n' "$model_name"
  for wav in "${FIXTURES[@]}"; do
    fixture_name="$(basename "$wav" .wav)"
    printf '    %s:\n' "$fixture_name"
    txt="$OUT_DIR/${model_name}__${fixture_name}.txt"
    # Transcrição vazia é resultado legítimo da bancada (áudio mudo, modelo que
    # não reconheceu) e precisa aparecer como tal — não derrubar o relatório.
    if grep -q '[^[:space:]]' "$txt" 2>/dev/null; then
      sed 's/^[[:space:]]*//' "$txt" | grep -v '^$' | sed 's/^/      /'
    else
      printf '      \033[1;31m(vazio — o modelo não transcreveu nada)\033[0m\n'
    fi
  done
done

# --- leitura pro documento de decisão ---------------------------------------

echo
info "Custo de um ditado real (teto do PRD: ${CEILING_MS} ms)"
echo
echo "  Um ditado de até 30s ocupa uma janela e custa o mesmo, seja de 5s ou de 25s."
echo "  Esse é o número medido abaixo — não projetado."
echo

printf '  %-24s %16s %14s   %s\n' "MODELO" "DITADO ATÉ 30s" "POR JANELA" "VEREDITO"
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
    verdict=$'\033[1;32mdentro do teto\033[0m'
  else
    verdict=$'\033[1;31mestoura o teto\033[0m'
  fi
  printf '  %-24s %13s ms %11s ms   %b\n' "$model_name" "$avg_short" "$avg_w" "$verdict"
done

echo
echo "  QUENTE vem do cronômetro interno do whisper (total menos carga), não do tempo"
echo "  de parede: parede inclui spawn de processo e leitura do modelo do disco, que"
echo "  não existem no app com o modelo já carregado."
echo "  POR JANELA divide pelo número de janelas de 30s, para comparar clipes longos."
echo
echo "  Saída bruta em: bench-out/$RUN_ID/  (atalho: bench-out/latest/)"
echo "  Agora preencha: docs/decisao-modelo.md"
