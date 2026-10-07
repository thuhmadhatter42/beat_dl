#!/bin/bash
# MBP: emit one line per new harvest result / supervisor event on Sofia (for a Monitor). Name-free
# (harvest.py already redacts). Polls every 60 s; ends after $1 seconds (default 1750).
RC="$HOME/.claude/scripts/ssh-rc"
end=$(( $(date +%s) + ${1:-1750} ))
seen=""
while [ "$(date +%s)" -lt "$end" ]; do
    out=$("$RC" js-mac-pro "grep -E '#[0-9]{4} (ok|skip|excluded|silent|error|mix-only (True|False))|supervisor|BLOCKED|STOP|EXC|target reached|exhausted|errors in a row' ~/pt-harvest/logs/batch.log | tail -n 6; test -f ~/pt-harvest/BLOCKED && echo BLOCKED-FILE" 2>/dev/null || true)
    while IFS= read -r l; do
        [ -z "$l" ] && continue
        case "$seen" in *"$l"*) ;; *) echo "$l" | cut -c1-330; seen="$seen
$l";; esac
    done <<< "$out"
    sleep 60
done
