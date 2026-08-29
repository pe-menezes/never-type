#!/bin/bash
# Atualiza o FalaFlow instalado para o que está no repositório remoto.
#
# Escrito para ser executado por um agente quando alguém diz "atualiza pra mim".
# Ele recusa em vez de improvisar nos dois casos em que improvisar destrói
# trabalho: alterações locais não commitadas, e repositório sem git.
#
# As permissões sobrevivem porque o certificado de assinatura é estável entre
# compilações da mesma máquina — é por isso que o keychain de assinatura nunca
# deve ser apagado.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/FalaFlow.app"
PLIST="$APP/Contents/Info.plist"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "$REPO_ROOT não é um clone git.
      Atualização automática precisa de git. Se você baixou um tarball, clone o
      repositório e rode: bash scripts/build-app.sh && bash scripts/install.sh"

# Alterações locais param tudo, e o script NÃO oferece descartar.
#
# Um agente com permissão de rodar `git reset --hard` para "desbloquear a
# atualização" apaga trabalho de alguém. A decisão é da pessoa, não da máquina.
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  git -C "$REPO_ROOT" status --short | sed 's/^/      /'
  fail "há alterações locais não commitadas (acima).
      PARE e pergunte à pessoa o que fazer com elas. Não descarte por conta
      própria — commitar, guardar em stash ou descartar é decisão dela."
fi

# Conferido antes do fetch porque `git fetch` num repositório sem remoto nenhum
# retorna zero sem fazer nada — e a falha só apareceria três linhas depois, numa
# mensagem mandando configurar `origin/...` que não existe.
[ -n "$(git -C "$REPO_ROOT" remote)" ] || fail "este clone não tem remoto configurado.
      Não há de onde buscar versão nova. Se o repositório foi copiado em vez de
      clonado, clone de novo — ou peça a URL a quem te passou o projeto."

info "Procurando versão nova"
git -C "$REPO_ROOT" fetch --quiet || fail "não consegui falar com o remoto. Rede?"

branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
local_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
remote_sha="$(git -C "$REPO_ROOT" rev-parse --short "@{u}" 2>/dev/null)" \
  || fail "a branch $branch não acompanha nenhuma remota.
      Rode: git -C '$REPO_ROOT' branch --set-upstream-to=origin/$branch"

installed="desconhecido"
if [ -f "$PLIST" ]; then
  installed="$(defaults read "$PLIST" FalaFlowCommit 2>/dev/null || echo desconhecido)"
fi

echo "      instalado: $installed"
echo "      local:     $local_sha"
echo "      remoto:    $remote_sha"

# Idempotência: já atualizado não refaz trabalho. É o contrato dos outros
# scripts, e recompilar à toa custa minutos.
if [ "$local_sha" = "$remote_sha" ] && [ "$installed" = "$local_sha" ]; then
  ok "já está na versão mais nova. Nada a fazer."
  exit 0
fi

if [ "$local_sha" != "$remote_sha" ]; then
  info "Trazendo $remote_sha"
  git -C "$REPO_ROOT" pull --ff-only \
    || fail "o pull não foi fast-forward: a branch local divergiu da remota.
      PARE e pergunte à pessoa. Resolver divergência por conta própria pode
      perder commits dela."
else
  info "Repositório já em $local_sha; falta só reinstalar"
fi

info "Compilando e instalando"
bash "$REPO_ROOT/scripts/build-app.sh"
bash "$REPO_ROOT/scripts/install.sh"

info "Conferindo"
bash "$REPO_ROOT/scripts/verificar-instalacao.sh"

echo
ok "atualizado para $(defaults read "$PLIST" FalaFlowCommit 2>/dev/null || echo '?')"
warn "as permissões continuam valendo, mas o ditado só está provado depois que
      você ditar uma frase e o texto aparecer."
