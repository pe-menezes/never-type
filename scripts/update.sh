#!/bin/bash
# Updates the installed NeverType to what is in the remote repository.
#
# Written to be run by an agent when someone says "update it for me". It refuses
# instead of improvising in the two cases where improvising destroys work:
# uncommitted local changes, and a repository without git.
#
# The permissions survive because the signing certificate is stable across
# builds on the same machine — which is why the signing keychain must never be
# deleted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/NeverType.app"
PLIST="$APP/Contents/Info.plist"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "$REPO_ROOT is not a git clone.
      Automatic update needs git. If you downloaded a tarball, clone the
      repository and run: bash scripts/build-app.sh && bash scripts/install.sh"

# Local changes stop everything, and the script does NOT offer to discard them.
#
# An agent allowed to run `git reset --hard` to "unblock the update" deletes
# someone's work. The decision belongs to the person, not the machine.
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  git -C "$REPO_ROOT" status --short | sed 's/^/      /'
  fail "there are uncommitted local changes (above).
      STOP and ask the person what to do with them. Do not discard them on your
      own — committing, stashing or discarding is their decision."
fi

# Checked before the fetch because `git fetch` in a repository with no remote at
# all returns zero without doing anything — and the failure would only show up
# three lines later, in a message telling you to configure an `origin/...` that
# does not exist.
[ -n "$(git -C "$REPO_ROOT" remote)" ] || fail "this clone has no remote configured.
      There is nowhere to fetch a new version from. If the repository was copied
      instead of cloned, clone it again — or ask whoever gave you the project for
      the URL."

info "Looking for a new version"
git -C "$REPO_ROOT" fetch --quiet || fail "could not reach the remote. Network?"

branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
local_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
remote_sha="$(git -C "$REPO_ROOT" rev-parse --short "@{u}" 2>/dev/null)" \
  || fail "branch $branch does not track any remote branch.
      Run: git -C '$REPO_ROOT' branch --set-upstream-to=origin/$branch"

installed="unknown"
if [ -f "$PLIST" ]; then
  installed="$(defaults read "$PLIST" NeverTypeCommit 2>/dev/null || echo unknown)"
fi

echo "      installed: $installed"
echo "      local:     $local_sha"
echo "      remote:    $remote_sha"

# Idempotency: already up to date redoes no work. It is the contract of the
# other scripts, and recompiling for nothing costs minutes.
if [ "$local_sha" = "$remote_sha" ] && [ "$installed" = "$local_sha" ]; then
  ok "already on the newest version. Nothing to do."
  exit 0
fi

if [ "$local_sha" != "$remote_sha" ]; then
  info "Pulling $remote_sha"
  git -C "$REPO_ROOT" pull --ff-only \
    || fail "the pull was not a fast-forward: the local branch diverged from the remote.
      STOP and ask the person. Resolving the divergence on your own can lose
      their commits."
else
  info "Repository already at $local_sha; only the reinstall is missing"
fi

info "Building and installing"
bash "$REPO_ROOT/scripts/build-app.sh"
bash "$REPO_ROOT/scripts/install.sh"

info "Verifying"
bash "$REPO_ROOT/scripts/verify-install.sh"

echo
ok "updated to $(defaults read "$PLIST" NeverTypeCommit 2>/dev/null || echo '?')"
warn "the permissions still hold, but dictation is only proven once you dictate
      a sentence and the text shows up."
