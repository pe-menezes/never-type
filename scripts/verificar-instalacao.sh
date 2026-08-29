#!/bin/bash
# Confere o que dá para conferir de fora sobre uma instalação do FalaFlow.
#
# Existe porque a instalação tem um modo de falha silencioso: sem a permissão de
# Acessibilidade o app abre, desenha o ícone na barra e simplesmente não reage à
# tecla — sem erro, sem log, sem nada. Quem instalou conclui que instalou.
#
# Este script NÃO verifica permissão, e diz isso em voz alta no fim. Não é
# limitação de implementação: o que interessa não é o TCC dizer que concedeu, e
# sim o ditado inserir texto. Só ditar prova isso.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/FalaFlow.app"
MODEL="$HOME/Library/Application Support/FalaFlow/models/ggml-large-v3-turbo-q5_0.bin"

# O magic do ggml é 0x67676d6c gravado como uint32 little-endian, então no
# arquivo ele sai invertido: 6c6d6767, que lido como texto vira "lmgg". Comparar
# em hexadecimal evita esse tropeço — e pega o caso que mais importa aqui, que é
# proxy de filtragem devolvendo página HTML de erro com nome de modelo.
GGML_MAGIC_HEX=6c6d6767
# 400 MB, não 50: o modelo tem 547 MB, e um piso baixo aprovaria download
# interrompido — que o app aceita como "modelo vazio" e derruba no primeiro uso.
MODEL_MIN_MB=400

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

# `problem` em vez de `fail` no corpo, de propósito: quem lê este script costuma
# ser um agente, e sair no primeiro erro o faria consertar uma coisa, rodar de
# novo, descobrir a segunda. Aqui ele vê a lista inteira de uma vez.
problems=0
problem() {
  printf '\033[1;31m  x\033[0m  %s\n' "$*" >&2
  problems=$((problems + 1))
}

[ "$(uname -s)" = "Darwin" ] || fail "só roda no macOS."
[ "$(uname -m)" = "arm64" ]  || fail "precisa de Apple Silicon: sem Metal a transcrição é lenta demais."

# Conferido no começo porque todas as mensagens de correção abaixo mandam rodar
# `bash scripts/...`, e isso só funciona de dentro do repositório. Um agente que
# copiasse este script para outro lugar receberia instruções que não funcionam.
[ -x "$REPO_ROOT/scripts/install.sh" ] || fail "não achei $REPO_ROOT/scripts/install.sh.
      Rode este script de dentro do repositório clonado, não de uma cópia solta."

# --- o app --------------------------------------------------------------------

info "Aplicativo"
if [ -d "$APP" ]; then
  ok "instalado em $APP"
  # O diagnóstico vai para uma variável em vez de /dev/null: assinatura que não
  # verifica precisa dizer por quê, senão o próximo passo é adivinhar.
  if signature="$(codesign --verify --strict "$APP" 2>&1)"; then
    ok "assinatura verifica"
  else
    problem "a assinatura de $APP não verifica:
      ${signature:-sem saída do codesign}
      Recompile e reinstale: bash scripts/build-app.sh && bash scripts/install.sh"
  fi
else
  problem "não existe $APP.
      Rode: bash scripts/install.sh"
fi

# --- o processo ---------------------------------------------------------------

info "Processo"
if pid="$(pgrep -x FalaFlow)"; then
  ok "rodando (pid $pid)"
else
  problem "o FalaFlow não está rodando.
      Abra: open $APP"
fi

# --- o modelo -----------------------------------------------------------------

info "Modelo"
if [ ! -f "$MODEL" ]; then
  problem "modelo ausente em $MODEL.
      Rode: bash scripts/setup-bench.sh && bash scripts/fetch-model.sh
      Se a rede bloquear o download, veja docs/INSTALL.md — copiar de outra
      máquina é um caminho válido, mas o arquivo precisa entrar por models/."
else
  model_magic="$(head -c 4 "$MODEL" | xxd -p)"
  model_mb=$(( $(stat -f%z "$MODEL") / 1048576 ))
  if [ "$model_magic" != "$GGML_MAGIC_HEX" ]; then
    problem "o arquivo em $MODEL não é um ggml: magic $model_magic, esperado $GGML_MAGIC_HEX.
      Um proxy de filtragem devolve HTML de erro com nome de modelo, e é
      exatamente assim que isso aparece. Apague e refaça: rm '$MODEL'"
  elif [ "$model_mb" -lt "$MODEL_MIN_MB" ]; then
    problem "modelo truncado: $model_mb MB, mínimo $MODEL_MIN_MB MB.
      Os primeiros bytes de um download interrompido estão certos, então o
      magic sozinho não pega isto. Apague e refaça: rm '$MODEL'"
  else
    ok "válido ($model_mb MB)"
  fi
fi

# --- o que este script não sabe -----------------------------------------------

echo
if [ "$problems" -gt 0 ]; then
  fail "$problems verificação(ões) falharam. Corrija acima e rode de novo."
fi

info "A parte que só você pode verificar"
cat <<'MSG'
  Microfone e Acessibilidade NÃO foram verificados aqui, e não dá para verificar
  de fora. Sem Acessibilidade o app abre, mostra o ícone e não reage à tecla —
  sem erro nenhum. É o modo de falha mais provável de uma instalação nova.

  Prove ditando:

    1. Abra um campo de texto qualquer.
    2. Segure ⌘ direito, fale uma frase, solte.
    3. O texto tem que aparecer onde o cursor está.

  Não apareceu? Ajustes do Sistema › Privacidade e Segurança › Acessibilidade,
  e ligue o FalaFlow. Depois disso, encerre e reabra o app.
MSG
ok "estrutura verificada"
