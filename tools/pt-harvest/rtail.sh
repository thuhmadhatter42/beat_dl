#!/bin/bash
# Sofia: last N per-session results from logs/batch.log (default 8), short, + supervisor/BLOCKED/STOP state.
cd "$HOME/pt-harvest" || exit 1
grep -E '#[0-9]{4} (ok|skip|excluded|silent|error|mix-only)' logs/batch.log | tail -n "${1:-8}" | cut -c1-${2:-240}
[ -f BLOCKED ] && echo "BLOCKED: $(cat BLOCKED)"
[ -f STOP ] && echo "STOP present"
[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null && echo "supervisor alive" || echo "supervisor NOT running"
