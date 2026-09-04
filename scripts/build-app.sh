#!/bin/bash
# Builds NeverType and assembles the signed .app bundle.
#
# No Xcode: the project builds with Command Line Tools only, so `xcodebuild` and
# `.xcodeproj` are out. The executable comes out of SwiftPM and the bundle is
# assembled here.
#
# The signature is not decoration. TCC (the macOS permission subsystem) stores
# the app's *designated requirement*. Signed ad hoc, that requirement points at
# the binary's hash, which changes with every build — and the Accessibility
# permission is revoked every time. Signed with a stable certificate, the
# requirement points at the certificate, and the grant survives rebuilds.
# Verified: two binaries with different cdhashes share
# `certificate leaf = H"5a6bfe7c…"`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/NeverType.app"
BUNDLE_ID="com.nevertype.app"

# The keychain lives in ~/Library/Keychains, not in .cache/, on purpose: deleting
# .cache is safe and documented as such, but losing this certificate would make
# macOS ask for Accessibility again.
KEYCHAIN="$HOME/Library/Keychains/nevertype-signing.keychain-db"
IDENTITY="NeverType Local Signing"

# The keychain password is derived from the machine's hardware UUID, not stored.
#
# The first version of this drew a random password and kept it in the login
# keychain. Prettier on paper and terrible in practice: whenever macOS decided to
# ask for authorization to read the item, it opened a dialog asking for a
# password the user **has no way of knowing** — it is random. A build that can
# hang asking for an impossible secret is worse than the problem it solves.
#
# Deriving is not hiding: anyone with local access to the machine can reproduce
# this value. But the goal here was never to keep a secret from a local attacker
# — that is impossible with a local certificate, as the README explains. The
# goal is to never version a credential and never hang the build. Both met.
machine_password() {
  local uuid
  uuid="$(ioreg -rd1 -c IOPlatformExpertDevice \
    | awk -F\" '/IOPlatformUUID/{print $4}')"
  [ -n "$uuid" ] || fail "could not read the machine identifier."
  printf 'nevertype-signing-%s' "$uuid" | shasum -a 256 | cut -d" " -f1
}

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "only makes sense on macOS."
command -v swift >/dev/null || fail "Swift toolchain not found. Run: xcode-select --install"

# Command Line Tools that have sat unupdated still answer `swift`, with a
# compiler older than this package, and what comes out then names nothing
# useful. On 6.0.3 the build reached FocusHandback and printed four
# actor-isolation errors, measured 2026-09-04 on a commit CI had approved on a
# full Xcode (docs/pitfalls.md). Below 6.0 the manifest itself stops compiling
# and SwiftPM answers "Invalid manifest". The floor is the manifest's own
# swift-tools-version.
#
# This reads the compiler and nothing else. A 6.x compiler that loads a pre-6
# PackageDescription from another toolchain also reports "Invalid manifest",
# and passes this check: separate failure, same message, still open.
swift_version="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p')"
[ -n "$swift_version" ] || fail "could not read a version out of \`swift --version\`:
$(swift --version 2>&1)"
[ "${swift_version%%.*}" -ge 6 ] || fail "Swift $swift_version is too old; this needs 6.0 or later.
It comes from the toolchain at $(xcode-select -p), and updating that toolchain
replaces the compiler. Ask before reinstalling anything."

# --- signing identity ---------------------------------------------------------

# No `-v` and no `-p codesigning`, on purpose. Those filters only list *trusted*
# identities, and a self-signed certificate never is — but codesign uses it all
# the same (verified: Authority=NeverType Local Signing, designated requirement
# with `certificate leaf`). With the filter, this check would always fail, the
# certificate would be recreated on every build and the Accessibility permission
# would be revoked every time: exactly the problem the stable signature exists
# to solve.
identity_present() {
  security find-identity "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"
}

create_identity() {
  info "Creating the local signing identity (one time only)"
  local tmp; tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  # RETURN alone does not fire when the script exits through `fail`, and then
  # the passwordless RSA key is left behind in $TMPDIR. EXIT covers that path.
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
    || fail "could not generate the certificate."

  # OpenSSL 3's PKCS12 uses a SHA-256 MAC, which the macOS Security framework
  # rejects with "MAC verification failed". The system LibreSSL produces the
  # format it reads.
  /usr/bin/openssl pkcs12 -export -out "$tmp/id.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -passout pass:"$KEYCHAIN_PASS" -name "$IDENTITY" -macalg sha1 2>/dev/null \
    || fail "could not package the certificate."

  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  # `-T /usr/bin/codesign` and NOT `-A`. With `-A`, any application uses the
  # private key directly, without even going through codesign or the password.
  # This does not stop a local attacker from invoking codesign itself — but it
  # closes direct programmatic access, which was the widest path.
  security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASS" -T /usr/bin/codesign >/dev/null

  # This line is what keeps the keychain dialog from hanging the build. Without
  # it codesign opens a graphical prompt and the script hangs forever — it is
  # also why the certificate does not live in the login keychain: there we would
  # not have the password to pass here.
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1

  chmod 600 "$KEYCHAIN"
  ok "identity created in $(basename "$KEYCHAIN")"
}

# The keychain needs to be in the user's search list: `codesign --keychain`
# alone is not enough (verified — it answers "no identity found" without this).
#
# `list-keychains -s` REPLACES the whole list. If the read comes back empty and
# we write only ours, the login keychain drops out of the list and the user
# loses password resolution for Wi-Fi, Safari and apps. Hence the guard rail.
#
# To revert by hand:
#   security list-keychains -d user -s ~/Library/Keychains/login.keychain-db
ensure_in_search_list() {
  local current=() line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
    line="${line#\"}"; line="${line%\"}"      # strip the quotes
    [ -n "$line" ] && current+=("$line")
  done < <(security list-keychains -d user)

  local k
  for k in "${current[@]}"; do [ "$k" = "$KEYCHAIN" ] && return; done

  [ ${#current[@]} -gt 0 ] \
    || fail "the user's keychain list came back empty; refusing to rewrite it blindly."
  security list-keychains -d user -s "${current[@]}" "$KEYCHAIN"
}

info "Checking the signing identity"
KEYCHAIN_PASS="$(machine_password)"
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" 2>/dev/null || true
fi
identity_present || create_identity
ensure_in_search_list
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
identity_present || fail "the identity '$IDENTITY' did not become available in the keychain."

# The keychain is locked again at the end of the build, with or without an
# error. Shrinks the window in which the key is usable without the password.
trap 'security lock-keychain "$KEYCHAIN" 2>/dev/null || true' EXIT

perms="$(stat -f%Lp "$KEYCHAIN")"
[ "$perms" = "600" ] || { chmod 600 "$KEYCHAIN"; warn "keychain permissions were $perms, corrected to 600"; }
ok "$IDENTITY"

# --- static whisper.cpp -------------------------------------------------------
#
# Static, not the Homebrew dylib. The hardened runtime turns on library
# validation — which is what closes code injection into a process that holds
# Accessibility — and it refuses a dylib signed by another team. With dynamic
# linking the app died in dyld with "different Team IDs".
#
# As a bonus the .app is self-contained: whoever uses it does not need Homebrew,
# and uninstalling whisper-cpp breaks nothing.

VENDOR="$REPO_ROOT/vendor/whisper"
WHISPER_TAG="v1.9.2"
# The exact commit, not just the tag.
#
# `v1.9.2` is a lightweight tag — a pointer that the maintainer, or whoever
# compromises the account, can move without a trace. This becomes ~300 thousand
# lines of C++ compiled and linked into the binary that holds Accessibility, so
# it deserves at least the same rigor already applied to the model converter in
# setup-bench.sh — which is a Python script that runs offline once. The
# criterion was inverted.
WHISPER_COMMIT="306c88f4d1286aec1bf96e544632897886af5501"

build_whisper_static() {
  command -v cmake >/dev/null || fail "cmake not found. Run: brew install cmake"
  local src="$REPO_ROOT/.cache/whisper-src" build="$REPO_ROOT/.cache/whisper-static"
  local log="$REPO_ROOT/.cache/whisper-build.log"

  if [ ! -d "$src" ]; then
    info "Cloning whisper.cpp $WHISPER_TAG"
    git clone --depth 1 -b "$WHISPER_TAG" -q https://github.com/ggml-org/whisper.cpp.git "$src" \
      || fail "could not clone whisper.cpp."
  fi

  # Always checked, including on a preexisting clone: reusing .cache/ just
  # because it exists means compiling whatever happens to be there.
  local got; got="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
  [ "$got" = "$WHISPER_COMMIT" ] || fail "the whisper.cpp in $src is not the expected commit.
      expected: $WHISPER_COMMIT
      got:      $got
      Delete $src and run again. Refusing to compile unverified source."
  if ! git -C "$src" diff --quiet HEAD 2>/dev/null; then
    fail "there are local modifications in $src. Delete the directory and run again."
  fi
  ok "source verified ($WHISPER_COMMIT)"

  info "Compiling static whisper.cpp (one time only)"
  # From scratch: a half-configured build directory makes cmake fail in obscure
  # ways, and reusing it saves nothing that matters.
  rm -rf "$build"
  # GGML_METAL_EMBED_LIBRARY embeds the shader source and compiles it at
  # runtime: it is what removes the need for the Metal toolchain, which does not
  # exist without full Xcode.
  # GGML_BACKEND_DL=OFF links the Metal backend in directly, instead of loading
  # it from an external dylib — which is precisely what we are eliminating.
  # The deployment target follows the package's; without it the linker warns
  # that the objects were built for a newer macOS than the target.
  cmake -S "$src" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BACKEND_DL=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF -DWHISPER_USE_SYSTEM_GGML=OFF >"$log" 2>&1 \
    || fail "cmake configuration failed. Diagnostics in: $log
      $(tail -3 "$log" | sed 's/^/      /')"
  cmake --build "$build" --config Release -j "$(sysctl -n hw.ncpu)" >>"$log" 2>&1 \
    || fail "whisper.cpp compilation failed. Diagnostics in: $log
      $(tail -3 "$log" | sed 's/^/      /')"

  rm -rf "$VENDOR"
  mkdir -p "$VENDOR/lib" "$VENDOR/include"
  # Explicit list, not "everything but the parakeet": any new .a from upstream
  # would enter the link directory silently.
  local lib
  for lib in libwhisper.a libggml.a libggml-base.a libggml-cpu.a libggml-metal.a libggml-blas.a; do
    local found; found="$(find "$build" -name "$lib" -print -quit)"
    [ -n "$found" ] || fail "the build did not produce $lib."
    cp "$found" "$VENDOR/lib/"
  done
  cp "$src/include/whisper.h" "$VENDOR/include/"
  cp "$src/ggml/include/"*.h "$VENDOR/include/"
  # Manifest of what was produced. Without it, reusing vendor/ on a later run
  # would trust the .a files just because they exist — and this is code that
  # goes inside the binary that holds Accessibility.
  ( cd "$VENDOR/lib" && shasum -a 256 ./*.a ) > "$VENDOR/MANIFEST"
  ok "vendor/whisper ready ($(du -sh "$VENDOR" | cut -f1), $(wc -l < "$VENDOR/MANIFEST" | tr -d ' ') libs verified)"
}

vendor_intact() {
  [ -f "$VENDOR/MANIFEST" ] && [ -f "$VENDOR/include/whisper.h" ] || return 1
  ( cd "$VENDOR/lib" && shasum -a 256 --status -c "$VENDOR/MANIFEST" ) 2>/dev/null
}

info "Checking static whisper.cpp"
if vendor_intact; then
  ok "vendor/whisper intact (checksums match)"
elif [ -d "$VENDOR" ]; then
  warn "vendor/whisper does not match the manifest — rebuilding from scratch"
  build_whisper_static
else
  build_whisper_static
fi

# --- compilation --------------------------------------------------------------

info "Compiling (release)"
cd "$REPO_ROOT"
swift build -c release --product NeverType
BIN="$(swift build -c release --product NeverType --show-bin-path)/NeverType"
[ -x "$BIN" ] || fail "binary not found at $BIN"
ok "$(basename "$BIN")"

# --- bundle -------------------------------------------------------------------

# The commit is stamped into the bundle.
#
# Without it there is no way to answer "is there a new version?" without
# recompiling blindly: the installed app carries no clue of where it came from.
# With the stamp, comparing what is in /Applications with what is in the
# repository is one line.
#
# `unknown` when there is no git — someone who downloaded a tarball instead of
# cloning. The app works the same; only the automatic update path is unusable.
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

info "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeverType"

# Keep the source icon as a small, reviewable vector. The app bundle still needs
# an icns file for Finder and System Settings, so the built-in macOS tools render
# every required scale during assembly.
ICON_SOURCE="$REPO_ROOT/assets/NeverTypeIcon.svg"
ICONSET="$REPO_ROOT/build/NeverType.iconset"
[ -f "$ICON_SOURCE" ] || fail "app icon source not found at $ICON_SOURCE"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
while read -r pixels filename; do
  sips -s format png -z "$pixels" "$pixels" "$ICON_SOURCE" \
    --out "$ICONSET/$filename" >/dev/null \
    || fail "could not render $filename from the app icon source."
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/NeverType.icns" \
  || fail "could not assemble NeverType.icns."
rm -rf "$ICONSET"
[ -s "$APP/Contents/Resources/NeverType.icns" ] || fail "NeverType.icns is empty."

# LSUIElement keeps the app out of the Dock: it lives only in the menu bar.
# NSMicrophoneUsageDescription is mandatory — without it macOS kills the process
# when the microphone is opened, instead of asking for permission.
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
  <key>CFBundleIconFile</key><string>NeverType</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NeverTypeCommit</key><string>$COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>NeverType records your voice to transcribe it locally. No audio ever leaves your Mac.</string>
</dict>
</plist>
PLIST
ok "bundle assembled"

# --- signing ------------------------------------------------------------------

info "Signing"
# The hardened runtime turns on library validation. Without it, a process that
# holds Accessibility — that is, one that can read and inject keystrokes across
# the whole system — accepts third-party code injection. It is the second path
# to the same prize, and this one can be closed.
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
  || fail "codesign failed."

codesign --verify --deep --strict "$APP" || fail "the signature does not verify."
ok "signed and verified"

echo
info "Designated requirement (this is what TCC stores)"
codesign -dvvv "$APP" 2>&1 | grep -E '^Authority' | sed 's/^/  /'
codesign -d -r- "$APP" 2>&1 | grep -i designated | sed 's/^/  /'
echo
echo "  App:  $APP"
echo "  Open: open '$APP'"
echo
echo "  On first launch macOS will ask for Microphone and Accessibility."
echo "  Once granted, they survive the next builds — that is what the stable"
echo "  identity above is for."
