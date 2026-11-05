#!/bin/bash
# retrain.sh — the README's "when the harvest has landed" chain as one command:
#   labels_from_db -> features (augmented) -> parity -> train (next free ft<N>) -> eval
# Usage (from anywhere): tools/train-tempocnn/retrain.sh [--db DB] [--audio-dir DIR]
#   defaults: docs/research/pt-ground-truth/{pt-ground-truth.sqlite3,audio11k} of the enclosing checkout.
# Creates tools/train-tempocnn/.venv with uv if missing. Stops at the first failing step.
# Log: tools/train-tempocnn/runs/retrain-<stamp>.log
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DATA_ROOT="$ROOT"
case "$ROOT" in */.claude/worktrees/*) DATA_ROOT="${ROOT%%/.claude/worktrees/*}" ;; esac
GT="$DATA_ROOT/docs/research/pt-ground-truth"
DB="$GT/pt-ground-truth.sqlite3"; AUDIO="$GT/audio11k"
while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --audio-dir) AUDIO="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 64 ;;
  esac
done
PY_AN="$DATA_ROOT/bin/python/bin/python3"           # analyzer Python (essentia), gitignored, main checkout
VENV="$HERE/.venv"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HERE/runs"
LOG="$HERE/runs/retrain-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "ERROR: step failed at line $LINENO (exit $?); see $LOG"' ERR
step() { echo; echo "== $(date '+%T') $*"; }

[ -x "$PY_AN" ] || { echo "ERROR: analyzer Python missing at $PY_AN"; exit 2; }
if [ ! -x "$VENV/bin/python" ]; then
  step "creating training venv"
  uv venv -p python3.12 "$VENV"
  uv pip install -p "$VENV/bin/python" -r "$HERE/requirements.txt"
fi
LABELS="$GT/labels.csv"
N=$(find "$ROOT/models" -maxdepth 1 -name 'deeptemp-k16-3-ft*.npz' | sed -E 's/.*-ft([0-9]+)\.npz$/\1/' | grep -E '^[0-9]+$' | sort -n | tail -1 || true)
RUN="ft$(( ${N:-0} + 1 ))"

step "labels from DB";      python3 "$HERE/labels_from_db.py" --db "$DB" --audio-dir "$AUDIO" --out "$LABELS"
step "features (augment)";  "$PY_AN" "$HERE/features.py" --labels "$LABELS" --augment
step "parity";              "$VENV/bin/python" "$HERE/parity.py" --labels "$LABELS"
step "train -> $RUN";       "$VENV/bin/python" "$HERE/train.py" --labels "$LABELS"
step "eval $RUN";           "$PY_AN" "$HERE/eval.py" --run "$RUN" --labels "$LABELS"
step "done: models/deeptemp-k16-3-$RUN.npz, runs/$RUN/eval.md"
