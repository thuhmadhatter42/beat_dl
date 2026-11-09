#!/bin/bash
# sync_from_sofia.sh — pull the PT harvest ground truth from Sofia (Mac Pro, js-mac-pro) into this checkout.
# READ-ONLY on Sofia: only `ssh-rc` existence checks and rsync reads; nothing is written or deleted there.
#   ~/pt-harvest/pt-ground-truth.sqlite3   -> docs/research/pt-ground-truth/pt-ground-truth.sqlite3
#   ~/pt-harvest/audio11k/                 -> docs/research/pt-ground-truth/audio11k/
#   --full also pulls ~/pt-harvest/audio/ (full-rate bounces) -> docs/research/pt-ground-truth/audio/
# The old local DB is copied to docs/research/pt-ground-truth/archive/pt-ground-truth-<stamp>.sqlite3 first.
# Local audio is only added/updated, never deleted (no --delete).
# Log: docs/research/pt-ground-truth/logs/sync_from_sofia-<stamp>.log
# Usage: tools/pt-harvest/sync_from_sofia.sh [--full] [--dry-run]
# After it: re-run tools/train-tempocnn/key_baseline.py (see runs/key-baseline-2026-11-05/eval.md).
set -euo pipefail

HOST="${SOFIA_HOST:-js-mac-pro}"
REMOTE="${SOFIA_HARVEST:-pt-harvest}"            # relative to the remote $HOME
SSH_RC="${SSH_RC:-$HOME/.claude/scripts/ssh-rc}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# Agent worktrees live inside the main checkout and lack the (untracked) data; use the enclosing one.
DEST="$ROOT/docs/research/pt-ground-truth"
case "$ROOT" in */.claude/worktrees/*) DEST="${ROOT%%/.claude/worktrees/*}/docs/research/pt-ground-truth" ;; esac
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST/logs" "$DEST/archive"
LOG="$DEST/logs/sync_from_sofia-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "ERROR: line $LINENO exited $? (see $LOG)"' ERR

FULL=0; DRY=()
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;;
    --dry-run) DRY=(--dry-run) ;;
    *) echo "unknown arg: $a"; exit 64 ;;
  esac
done
echo "$(date '+%F %T') sync from $HOST:~/$REMOTE -> $DEST (full=$FULL ${DRY[*]:-})"

# 1. Sofia reachable and the files there? (ssh-rc returns the real exit code; plain ssh over Tailscale always says 0)
if ! "$SSH_RC" "$HOST" "test -s ~/$REMOTE/pt-ground-truth.sqlite3 && test -d ~/$REMOTE/audio11k && ls ~/$REMOTE/audio11k | wc -l"; then
  echo "ERROR: Sofia unreachable or ~/$REMOTE/pt-ground-truth.sqlite3 / audio11k missing; nothing changed locally."
  exit 2
fi

# 2. back up the local DB before it is replaced
if [ -f "$DEST/pt-ground-truth.sqlite3" ] && [ ${#DRY[@]} -eq 0 ]; then
  cp -p "$DEST/pt-ground-truth.sqlite3" "$DEST/archive/pt-ground-truth-$STAMP.sqlite3"
  echo "backed up local DB -> archive/pt-ground-truth-$STAMP.sqlite3"
fi

# 3. pull (DB to a temp name first, so a dropped link never leaves a half-copied DB in place)
RS=(/usr/bin/rsync -a --partial --timeout=60 -e "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8" ${DRY[@]+"${DRY[@]}"})
"${RS[@]}" "$HOST:$REMOTE/pt-ground-truth.sqlite3" "$DEST/pt-ground-truth.sqlite3.incoming"
if [ ${#DRY[@]} -eq 0 ]; then
  /usr/bin/sqlite3 "$DEST/pt-ground-truth.sqlite3.incoming" "PRAGMA integrity_check;" | grep -qx ok \
    || { echo "ERROR: pulled DB fails integrity_check; local DB left as it was"; exit 3; }
  mv -f "$DEST/pt-ground-truth.sqlite3.incoming" "$DEST/pt-ground-truth.sqlite3"
fi
"${RS[@]}" "$HOST:$REMOTE/audio11k/" "$DEST/audio11k/"
[ "$FULL" = 1 ] && "${RS[@]}" "$HOST:$REMOTE/audio/" "$DEST/audio/"

# 4. report (counts only, no names)
if [ ${#DRY[@]} -eq 0 ]; then
  echo "rows: $(/usr/bin/sqlite3 "$DEST/pt-ground-truth.sqlite3" "select count(*) from sessions")," \
       "keyed: $(/usr/bin/sqlite3 "$DEST/pt-ground-truth.sqlite3" "select count(*) from sessions where key is not null and key != ''")," \
       "audio11k files: $(find "$DEST/audio11k" -name '*.wav' | wc -l | tr -d ' ')"
fi
echo "$(date '+%F %T') done"
