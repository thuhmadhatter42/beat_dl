#!/bin/bash
# Publish the Beat Key release named in VERSION (J runs this; auto mode blocks public pushes).
# Needs app/build/Beat-Key-<V>.pkg (the download for people) and Beat-Key-<V>.dmg (Sparkle updates),
# both signed, notarized and stapled by app/build.sh, and app/build/appcast.xml.
# Three phases. 1: read-only checks, nothing changes anywhere; any failure stops here.
# 2: publish: tag + push main + push tag, DMG, pkg and beat-key-latest.json to the FLR site on Sofia,
# friends page, and last (the step every installed Beat Key sees) the GitHub release.
# 3: final check: download page answers 303 and beat-key-latest.json names <V>; only then PUBLISHED.
# The whole run is also appended with timestamps to app/build/publish-<V>.log.
# Restarts, shuts down or logs out nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
SSH_RC=${SSH_RC:-$HOME/.claude/scripts/ssh-rc}   # the required wrapper: plain ssh to Sofia always exits 0
HOST=js-mac-pro
V=$(tr -d '[:space:]' < VERSION)
D=app/build/Beat-Key-$V.dmg
P=app/build/Beat-Key-$V.pkg
A=app/build/appcast.xml
TAG=Beat-Key-$V
REPO=thuhmadhatter42/beat_dl
REMOTE_DMG='~/fourletterrecords/beat-key-releases'
REMOTE_JSON='~/fourletterrecords/beat-key-latest.json'
PAGE=https://fourletterrecords.com/account/download/beat-key

mkdir -p app/build
LOG=app/build/publish-$V.log
exec 3>&1
exec > >(while IFS= read -r l; do printf '%s %s\n' "$(date '+%F %T')" "$l" >>"$LOG"; printf '%s\n' "$l" >&3; done) 2>&1

DONE=""; CUR=""
trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "FAILED (exit $rc). Public steps completed:${DONE:- none}. Stopped during: ${CUR:-the checks or final check (no step in progress)}."; fi' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "ok: $1"; }
pub() { CUR=$1; shift; "$@"; DONE="$DONE [$CUR]"; echo "step done: $CUR"; CUR=""; }

echo "== publishing $V: phase 1, checks (read-only)"
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION '$V' is not x.y.z"
[ -f "$D" ] || fail "$D missing; run app/build.sh"
xcrun stapler validate "$D" >/dev/null 2>&1 || fail "$D is not stapled; run app/build.sh"
ok "DMG exists and is stapled"
[ -f "$P" ] || fail "$P missing; run app/build.sh"
pkgutil --check-signature "$P" >/dev/null 2>&1 || fail "$P is not signed (pkgutil --check-signature); run app/build.sh"
xcrun stapler validate "$P" >/dev/null 2>&1 || fail "$P is not stapled; run app/build.sh"
ok "pkg exists, is signed and stapled"
[ -f "$A" ] || fail "$A missing; run app/build.sh"
grep -qF "<sparkle:version>$V</sparkle:version>" "$A" \
  && grep -qF "<sparkle:shortVersionString>$V</sparkle:shortVersionString>" "$A" \
  && grep -qF "https://github.com/$REPO/releases/download/$TAG/Beat-Key-$V.dmg\"" "$A" \
  || fail "$A does not name $V (stale or test-feed build); run app/build.sh"
ok "appcast.xml names $V"
[ "$(git symbolic-ref --short -q HEAD)" = main ] || fail "not on branch main (the script pushes main and tags HEAD); git switch main"
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "tracked files have uncommitted changes; commit or restore them, then rebuild"
ok "HEAD is main, tracked files clean"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists locally; investigate before publishing"
REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/$TAG") || fail "could not ask origin about tags"
[ -z "$REMOTE_TAG" ] || fail "tag $TAG already exists on origin; investigate before publishing"
ok "tag $TAG is free locally and on origin"
if REL=$(gh release view "$TAG" -R "$REPO" 2>&1); then fail "GitHub release $TAG already exists"; fi
case "$REL" in *"release not found"*) ;; *) fail "could not ask GitHub about release $TAG: $REL" ;; esac
ok "no GitHub release $TAG yet"
"$SSH_RC" "$HOST" true >/dev/null || fail "$HOST not reachable"
"$SSH_RC" "$HOST" "test ! -e $REMOTE_DMG/Beat-Key-$V.dmg" || fail "$HOST already holds Beat-Key-$V.dmg (never overwrite)"
"$SSH_RC" "$HOST" "test ! -e $REMOTE_DMG/Beat-Key-$V.pkg" || fail "$HOST already holds Beat-Key-$V.pkg (never overwrite)"
ok "$HOST reachable and does not hold Beat-Key-$V.dmg or Beat-Key-$V.pkg"
[ -f friends-page/index.html ] || fail "friends-page/index.html missing"
ok "friends-page/index.html exists"

echo "== phase 2, publish (irreversible)"
pub "tag $TAG" git tag "$TAG"
pub "push main" git push origin main
pub "push tag" git push origin "$TAG"
pub "DMG to $HOST" scp "$D" "$HOST:fourletterrecords/beat-key-releases/"
pub "pkg to $HOST" scp "$P" "$HOST:fourletterrecords/beat-key-releases/"
pub "beat-key-latest.json" "$SSH_RC" "$HOST" "printf '{\"version\": \"$V\"}\n' > $REMOTE_JSON && cat $REMOTE_JSON"
pub "friends page" scp friends-page/index.html "$HOST:beatkey/"
pub "GitHub release" gh release create "$TAG" -R "$REPO" --title "Beat Key $V" "$P" "$D" "$A"

echo "== phase 3, final check"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$PAGE") || fail "could not reach $PAGE"
[ "$CODE" = 303 ] || fail "$PAGE answered $CODE, expected 303"
ok "download page answers 303"
JSON=$("$SSH_RC" "$HOST" "cat $REMOTE_JSON") || fail "could not read $REMOTE_JSON on $HOST"
grep -qF "\"version\": \"$V\"" <<<"$JSON" || fail "$REMOTE_JSON on $HOST says '$JSON', expected version $V"
ok "beat-key-latest.json names $V"
echo "PUBLISHED $V"
