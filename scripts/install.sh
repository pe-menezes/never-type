#!/bin/bash
# Instala o NeverType em /Applications.
#
# Caminho fixo de propósito: junto com a identidade de assinatura estável, é o
# que faz a permissão de Acessibilidade sobreviver. Mover o app depois quebra a
# concessão e o macOS pede de novo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/build/NeverType.app"
DEST="/Applications/NeverType.app"
MODEL_DIR="$HOME/Library/Application Support/NeverType/models"
MODEL="ggml-large-v3-turbo-q5_0.bin"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "só roda no macOS."
[ "$(uname -m)" = "arm64" ]  || fail "precisa de Apple Silicon: sem Metal a transcrição é lenta demais."

# Conferido agora, e não depois de compilar por minutos: num Mac gerido ou com
# usuário não-admin, /Applications não é gravável, e descobrir isso no fim é o
# jeito mais certo de a pessoa desistir.
[ -w /Applications ] || fail "sem permissão de escrita em /Applications.
      Peça a alguém com direitos de administrador, ou instale em outro lugar:
        cp -R build/NeverType.app ~/Applications/"

# --- o app -------------------------------------------------------------------

if [ ! -d "$SOURCE" ]; then
  info "Compilando (primeira vez leva alguns minutos)"
  bash "$REPO_ROOT/scripts/build-app.sh" || fail "a compilação falhou."
fi
[ -d "$SOURCE" ] || fail "não encontrei $SOURCE."

info "Instalando em $DEST"
# `pkill`, e não `osascript quit`.
#
# Mandar Apple event para um app novo exige autorização de Automação do TCC, e o
# macOS abre um diálogo modal pedindo isso — travando o instalador logo depois de
# "Instalando em /Applications", sem nenhuma pista do motivo. E espera o processo
# morrer de fato: com `sleep` fixo, um app que demora a sair sobrevive, a guarda
# de instância única barra o novo, e a pessoa segue rodando o binário velho
# achando que atualizou.
if pgrep -x NeverType >/dev/null; then
  info "Encerrando a instância em execução"
  pkill -x NeverType || true
  for _ in $(seq 1 30); do
    pgrep -x NeverType >/dev/null || break
    sleep 0.2
  done
  pgrep -x NeverType >/dev/null && fail "o NeverType não encerrou. Encerre pelo menu da bandeja e rode de novo."
fi
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST" || fail "a assinatura não verifica em $DEST."
ok "instalado e verificado"

# A cópia de build/ é artefato de compilação e continua lá. Abrir ela por engano
# não duplica o app — a segunda instância cede à primeira —, mas confunde.
[ -d "$SOURCE" ] && warn "a cópia de build/ continua no repositório; use sempre $DEST"

# --- o modelo ----------------------------------------------------------------
#
# Ele não vem no app: são 547 MB. O jeito de obtê-lo depende de onde você está —
# na rede corporativa a HuggingFace está bloqueada, então o setup baixa o
# checkpoint do CDN da OpenAI e converte.

info "Verificando o modelo"
# 400 MB para um modelo de 547 MB — o mesmo piso de ModelStore.minimumBytes no
# app, de fetch-model.sh e de verify-install.sh. Um piso baixo aprovaria
# um download interrompido: reproduzido com 100 KB do modelo real, o whisper.cpp
# aceita como "modelo vazio" e o processo morre na primeira inferência (exit 134,
# ver docs/pitfalls.md).
MODEL_MIN_MB=400
if [ -f "$MODEL_DIR/$MODEL" ] && [ "$(( $(stat -f%z "$MODEL_DIR/$MODEL") / 1048576 ))" -ge "$MODEL_MIN_MB" ]; then
  ok "modelo presente ($(( $(stat -f%z "$MODEL_DIR/$MODEL") / 1048576 )) MB)"
elif [ -f "$REPO_ROOT/models/$MODEL" ]; then
  bash "$REPO_ROOT/scripts/fetch-model.sh"
else
  warn "o modelo ainda não existe nesta máquina."
  echo "     Ele tem 547 MB e é construído a partir do checkpoint da OpenAI:"
  echo
  echo "       bash scripts/setup-bench.sh   # baixa e converte três modelos (~10 min);"
  echo "                                     # exige Homebrew e python3"
  echo "       bash scripts/fetch-model.sh   # valida e instala no lugar certo"
  echo
  echo "     Alternativa mais rápida se alguém do time já tem: copie o arquivo"
  echo "     para models/ (dentro do repositório) e rode só a segunda etapa:"
  echo
  echo "       cp /de/onde/veio/$MODEL models/"
  echo "       bash scripts/fetch-model.sh"
  echo
  echo "     Não copie direto para $MODEL_DIR/: isso pula a validação de magic e"
  echo "     tamanho do fetch-model.sh, e um arquivo ruim só é recusado quando o"
  echo "     app abre — a mensagem aparece no menu, em \"Modelo:\", não aqui."
  echo
fi

# --- permissões ---------------------------------------------------------------

cat <<'MSG'

==> Falta você conceder duas permissões

  Abra o app e o macOS vai pedir as duas. As duas são necessárias:

    Microfone       sem ele não há áudio
    Acessibilidade  sem ela o app não recebe a tecla global. Ele avisa — ícone
                    cortado (mic.slash), "Acessibilidade: faltando" e "Abrir
                    Ajustes de Acessibilidade…" no menu, linha no log e o pedido
                    do próprio macOS —, mas a tecla não faz nada

  Se a janela de Acessibilidade não aparecer, vá em
  Ajustes do Sistema › Privacidade e Segurança › Acessibilidade e ligue o NeverType.

==> Como usar

  Segure ⌘ direito, fale, solte. O texto aparece onde o cursor estiver.
  Apertar qualquer tecla comum (ou Esc) durante o hold cancela e descarta o áudio.

  Mãos-livres: dois toques rápidos na tecla travam a gravação; um toque encerra
  e transcreve; Esc descarta. Travado, teclar não cancela.

  No menu da bandeja: a tecla (⌘, ⌥ ou ⌃ direito) e os sons ficam em "Tecla";
  as últimas transcrições em "Copiar última transcrição" e "Histórico", onde
  clicar copia e "Limpar histórico" apaga o arquivo; termos e substituições em
  "Vocabulário…".

MSG

info "Abrindo"
open "$DEST"
ok "pronto"
