#!/bin/bash
# Compila o NeverType e monta o bundle .app assinado.
#
# Sem Xcode: esta máquina só tem Command Line Tools, então `xcodebuild` e
# `.xcodeproj` estão fora. O executável sai do SwiftPM e o bundle é montado aqui.
#
# A assinatura não é enfeite. O TCC (o subsistema de permissões do macOS) guarda
# o *requisito designado* do app. Assinado ad-hoc, esse requisito aponta para o
# hash do binário, que muda a cada build — e a permissão de Acessibilidade é
# revogada toda vez. Assinado com um certificado estável, o requisito aponta para
# o certificado, e a concessão sobrevive aos rebuilds. Verificado: dois binários
# com cdhash diferente compartilham `certificate leaf = H"5a6bfe7c…"`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/NeverType.app"
BUNDLE_ID="com.nevertype.app"

# O keychain fica em ~/Library/Keychains, e não em .cache/, de propósito: apagar
# o .cache é seguro e documentado como tal, mas perder este certificado faria o
# macOS pedir Acessibilidade de novo.
KEYCHAIN="$HOME/Library/Keychains/nevertype-signing.keychain-db"
IDENTITY="NeverType Local Signing"

# A senha do keychain é derivada do UUID de hardware da máquina, não guardada.
#
# A primeira versão disto sorteava a senha e a guardava no keychain de login. Era
# mais bonito no papel e péssimo na prática: quando o macOS decidia pedir
# autorização para ler o item, abria um diálogo pedindo uma senha que o usuário
# **não tem como saber** — ela é aleatória. Um build que pode travar pedindo um
# segredo impossível é pior que o problema que resolve.
#
# Derivar não é esconder: qualquer um com acesso local à máquina reproduz este
# valor. Mas o objetivo aqui nunca foi guardar segredo de um atacante local —
# isso é impossível com certificado local, como o README explica. O objetivo é
# não versionar credencial e nunca travar o build. Ambos cumpridos.
machine_password() {
  local uuid
  uuid="$(ioreg -rd1 -c IOPlatformExpertDevice \
    | awk -F\" '/IOPlatformUUID/{print $4}')"
  [ -n "$uuid" ] || fail "não consegui ler o identificador da máquina."
  printf 'nevertype-signing-%s' "$uuid" | shasum -a 256 | cut -d" " -f1
}

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "só faz sentido no macOS."
command -v swift >/dev/null || fail "toolchain Swift não encontrado."

# --- identidade de assinatura ------------------------------------------------

# Sem `-v` e sem `-p codesigning` de propósito. Esses filtros só listam
# identidades *confiáveis*, e um certificado self-signed nunca é — mas o codesign
# usa ele do mesmo jeito (verificado: Authority=NeverType Local Signing, requisito
# designado com `certificate leaf`). Com o filtro, este teste falharia sempre, o
# certificado seria recriado a cada build e a permissão de Acessibilidade seria
# revogada toda vez: exatamente o problema que a assinatura estável existe para
# resolver.
identity_present() {
  security find-identity "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"
}

create_identity() {
  info "Criando identidade de assinatura local (uma vez só)"
  local tmp; tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  # RETURN sozinho não dispara quando o script sai por `fail`, e aí a chave RSA
  # sem senha fica esquecida em $TMPDIR. EXIT cobre esse caminho.
  CREATE_TMP="$tmp"
  trap 'rm -rf "${CREATE_TMP:-}"' RETURN
  trap 'rm -rf "${CREATE_TMP:-}"; security lock-keychain "$KEYCHAIN" 2>/dev/null || true' EXIT

  local KEYCHAIN_PASS
  KEYCHAIN_PASS="$(machine_password)"

  cat > "$tmp/req.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/req.cnf" 2>/dev/null \
    || fail "não consegui gerar o certificado."

  # O PKCS12 do OpenSSL 3 usa MAC SHA-256, que o Security framework do macOS
  # rejeita com "MAC verification failed". O LibreSSL do sistema gera no formato
  # que ele lê.
  /usr/bin/openssl pkcs12 -export -out "$tmp/id.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -passout pass:"$KEYCHAIN_PASS" -name "$IDENTITY" -macalg sha1 2>/dev/null \
    || fail "não consegui empacotar o certificado."

  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  # `-T /usr/bin/codesign` e NÃO `-A`. Com `-A`, qualquer aplicativo usa a chave
  # privada diretamente, sem sequer passar pelo codesign nem pela senha. Isto
  # não impede que um atacante local invoque o próprio codesign — mas fecha o
  # acesso programático direto, que era o caminho mais largo.
  security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASS" -T /usr/bin/codesign >/dev/null

  # Esta linha é a que evita o diálogo de keychain travando o build. Sem ela o
  # codesign abre um prompt gráfico e o script fica pendurado para sempre — é
  # também por isso que o certificado não mora no login keychain: lá não teríamos
  # a senha para passar aqui.
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1

  chmod 600 "$KEYCHAIN"
  ok "identidade criada em $(basename "$KEYCHAIN")"
}

# O keychain precisa estar na lista de busca do usuário: `codesign --keychain`
# sozinho não basta (verificado — responde "no identity found" sem isto).
#
# `list-keychains -s` SUBSTITUI a lista inteira. Se a leitura vier vazia e a
# gente escrever só o nosso, o keychain de login sai da lista e o usuário perde
# resolução de senhas de Wi-Fi, Safari e apps. Daí o guarda-corpo.
#
# Para reverter à mão:
#   security list-keychains -d user -s ~/Library/Keychains/login.keychain-db
ensure_in_search_list() {
  local current=() line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # tira espaço à esquerda
    line="${line#\"}"; line="${line%\"}"      # tira as aspas
    [ -n "$line" ] && current+=("$line")
  done < <(security list-keychains -d user)

  local k
  for k in "${current[@]}"; do [ "$k" = "$KEYCHAIN" ] && return; done

  [ ${#current[@]} -gt 0 ] \
    || fail "a lista de keychains do usuário voltou vazia; não vou reescrevê-la às cegas."
  security list-keychains -d user -s "${current[@]}" "$KEYCHAIN"
}

info "Verificando identidade de assinatura"
KEYCHAIN_PASS="$(machine_password)"
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" 2>/dev/null || true
fi
identity_present || create_identity
ensure_in_search_list
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
identity_present || fail "a identidade '$IDENTITY' não ficou disponível no keychain."

# O keychain volta a ficar travado ao fim do build, com ou sem erro. Reduz a
# janela em que a chave está utilizável sem a senha.
trap 'security lock-keychain "$KEYCHAIN" 2>/dev/null || true' EXIT

perms="$(stat -f%Lp "$KEYCHAIN")"
[ "$perms" = "600" ] || { chmod 600 "$KEYCHAIN"; warn "permissões do keychain eram $perms, corrigidas para 600"; }
ok "$IDENTITY"

# --- whisper.cpp estático ------------------------------------------------------
#
# Estático, e não a dylib do Homebrew. O hardened runtime liga validação de
# bibliotecas — que é o que fecha injeção de código num processo com
# Acessibilidade — e ela recusa dylib assinada por outra equipe. Com linkagem
# dinâmica o app morria no dyld com "different Team IDs".
#
# De quebra o .app fica autocontido: quem for usar não precisa de Homebrew, e
# desinstalar o whisper-cpp não quebra nada.

VENDOR="$REPO_ROOT/vendor/whisper"
WHISPER_TAG="v1.9.2"
# O commit exato, não só a tag.
#
# `v1.9.2` é uma tag leve — um ponteiro que o mantenedor, ou quem comprometer a
# conta, move sem deixar rastro. Isto aqui vira ~300 mil linhas de C++ compiladas
# e linkadas dentro do binário que detém Acessibilidade, então merece pelo menos
# o mesmo rigor que já se aplica ao conversor de modelo em setup-bench.sh — que é
# um script Python que roda offline uma vez. O critério estava invertido.
WHISPER_COMMIT="306c88f4d1286aec1bf96e544632897886af5501"

build_whisper_static() {
  command -v cmake >/dev/null || fail "cmake não encontrado. Rode: brew install cmake"
  local src="$REPO_ROOT/.cache/whisper-src" build="$REPO_ROOT/.cache/whisper-static"
  local log="$REPO_ROOT/.cache/whisper-build.log"

  if [ ! -d "$src" ]; then
    info "Clonando whisper.cpp $WHISPER_TAG"
    git clone --depth 1 -b "$WHISPER_TAG" -q https://github.com/ggml-org/whisper.cpp.git "$src" \
      || fail "não consegui clonar o whisper.cpp."
  fi

  # Confere sempre, inclusive num clone preexistente: reusar .cache/ só por
  # existir significa compilar o que quer que esteja lá.
  local got; got="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo desconhecido)"
  [ "$got" = "$WHISPER_COMMIT" ] || fail "o whisper.cpp em $src não é o commit esperado.
      esperado: $WHISPER_COMMIT
      obtido:   $got
      Apague $src e rode de novo. Não vou compilar fonte não verificado."
  if ! git -C "$src" diff --quiet HEAD 2>/dev/null; then
    fail "há modificações locais em $src. Apague o diretório e rode de novo."
  fi
  ok "fonte conferida ($WHISPER_COMMIT)"

  info "Compilando whisper.cpp estático (uma vez só)"
  # Do zero: um diretório de build meio-configurado faz o cmake falhar de forma
  # obscura, e reaproveitá-lo não economiza nada que importe.
  rm -rf "$build"
  # GGML_METAL_EMBED_LIBRARY embute o fonte dos shaders e compila em runtime:
  # é o que dispensa o toolchain Metal, que não existe sem Xcode completo.
  # GGML_BACKEND_DL=OFF liga o backend Metal direto, em vez de carregá-lo de
  # um dylib externo — que é justamente o que estamos eliminando.
  # O deployment target acompanha o do pacote; sem isso o linker avisa que os
  # objetos foram construídos para um macOS mais novo que o alvo.
  cmake -S "$src" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BACKEND_DL=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF -DWHISPER_USE_SYSTEM_GGML=OFF >"$log" 2>&1 \
    || fail "configuração do cmake falhou. Diagnóstico em: $log
      $(tail -3 "$log" | sed 's/^/      /')"
  cmake --build "$build" --config Release -j "$(sysctl -n hw.ncpu)" >>"$log" 2>&1 \
    || fail "compilação do whisper.cpp falhou. Diagnóstico em: $log
      $(tail -3 "$log" | sed 's/^/      /')"

  rm -rf "$VENDOR"
  mkdir -p "$VENDOR/lib" "$VENDOR/include"
  # Lista explícita, não "tudo menos o parakeet": qualquer .a novo do upstream
  # entraria no diretório de link em silêncio.
  local lib
  for lib in libwhisper.a libggml.a libggml-base.a libggml-cpu.a libggml-metal.a libggml-blas.a; do
    local found; found="$(find "$build" -name "$lib" -print -quit)"
    [ -n "$found" ] || fail "o build não produziu $lib."
    cp "$found" "$VENDOR/lib/"
  done
  cp "$src/include/whisper.h" "$VENDOR/include/"
  cp "$src/ggml/include/"*.h "$VENDOR/include/"
  # Manifesto do que foi produzido. Sem isto, reusar vendor/ numa execução
  # seguinte confiaria nos .a só por existirem — e é código que vai para dentro
  # do binário que detém Acessibilidade.
  ( cd "$VENDOR/lib" && shasum -a 256 ./*.a ) > "$VENDOR/MANIFEST"
  ok "vendor/whisper pronto ($(du -sh "$VENDOR" | cut -f1), $(wc -l < "$VENDOR/MANIFEST" | tr -d ' ') libs conferidas)"
}

vendor_intact() {
  [ -f "$VENDOR/MANIFEST" ] && [ -f "$VENDOR/include/whisper.h" ] || return 1
  ( cd "$VENDOR/lib" && shasum -a 256 --status -c "$VENDOR/MANIFEST" ) 2>/dev/null
}

info "Verificando whisper.cpp estático"
if vendor_intact; then
  ok "vendor/whisper íntegro (checksums conferem)"
elif [ -d "$VENDOR" ]; then
  warn "vendor/whisper não confere com o manifesto — reconstruindo do zero"
  build_whisper_static
else
  build_whisper_static
fi

# --- compilação ---------------------------------------------------------------

info "Compilando (release)"
cd "$REPO_ROOT"
swift build -c release --product NeverType
BIN="$(swift build -c release --product NeverType --show-bin-path)/NeverType"
[ -x "$BIN" ] || fail "binário não encontrado em $BIN"
ok "$(basename "$BIN")"

# --- bundle -------------------------------------------------------------------

# O commit vai carimbado no bundle.
#
# Sem isto não há como responder "tem versão nova?" sem recompilar às cegas: o
# app instalado não carrega nenhuma pista de onde veio. Com o carimbo, comparar
# o que está em /Applications com o que está no repositório é uma linha.
#
# `desconhecido` quando não há git — alguém que baixou um tarball em vez de
# clonar. O app funciona igual; só o caminho de atualização automática não serve.
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo desconhecido)"

info "Montando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeverType"

# LSUIElement mantém o app fora do Dock: ele vive só na menu bar.
# NSMicrophoneUsageDescription é obrigatório — sem ele o macOS mata o processo
# quando o microfone é aberto, em vez de pedir permissão.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NeverType</string>
  <key>CFBundleDisplayName</key><string>NeverType</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>NeverType</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NeverTypeCommit</key><string>$COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>O NeverType grava sua voz para transcrever localmente. Nenhum áudio sai da sua máquina.</string>
</dict>
</plist>
PLIST
ok "bundle montado"

# --- assinatura ---------------------------------------------------------------

info "Assinando"
# Hardened runtime liga a validação de bibliotecas. Sem ela, um processo que
# detém Acessibilidade — ou seja, que pode ler e injetar teclas no sistema todo —
# aceita injeção de código de terceiros. É o segundo caminho para o mesmo prêmio,
# e este dá para fechar.
ENTITLEMENTS="$REPO_ROOT/build/NeverType.entitlements"
cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" \
  --options runtime --entitlements "$ENTITLEMENTS" \
  --keychain "$KEYCHAIN" --timestamp=none "$APP" \
  || fail "codesign falhou."

codesign --verify --deep --strict "$APP" || fail "a assinatura não verifica."
ok "assinado e verificado"

echo
info "Requisito designado (é isto que o TCC guarda)"
codesign -dvvv "$APP" 2>&1 | grep -E '^Authority' | sed 's/^/  /'
codesign -d -r- "$APP" 2>&1 | grep -i designated | sed 's/^/  /'
echo
echo "  App:  $APP"
echo "  Abra: open '$APP'"
echo
echo "  Na primeira execução o macOS vai pedir Microfone e Acessibilidade."
echo "  Depois de concedidas, elas sobrevivem aos próximos builds — é para isso"
echo "  que serve a identidade estável acima."
