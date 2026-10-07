#!/bin/bash
# Sofia: wait up to $1 s for a NEW line in logs/batch.log (written after this starts) matching $2
# (default: trouble). Prints the match (short) or "quiet <n>s"; then the last 3 results.
cd "$HOME/pt-harvest" || exit 1
max=${1:-570}; rx='EXC|BLOCKED|errors in a row|watchdog|gave up|8 crashes|exited rc=[^0]|target reached|exhausted'
[ "$2" = results ] && rx="#[0-9]{4} (ok|skip|excluded|silent|error)|$rx"
start=$(wc -l < logs/batch.log); t0=$(date +%s)
while :; do
    hit=$(tail -n +$((start + 1)) logs/batch.log | grep -E -m1 "$rx")
    [ -n "$hit" ] && { echo "NEW: ${hit:0:300}"; break; }
    [ $(( $(date +%s) - t0 )) -ge "$max" ] && { echo "quiet ${max}s"; break; }
    sleep 10
done
grep -E '#[0-9]{4} (ok|skip|excluded|silent|error)' logs/batch.log | tail -n 3 | cut -c1-170
[ -f BLOCKED ] && echo "BLOCKED: $(cat BLOCKED)"
[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null || echo "supervisor NOT running"
