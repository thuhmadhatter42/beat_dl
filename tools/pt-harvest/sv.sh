#!/bin/bash
# MBP side. sv.sh push            -> copy tools/pt-harvest/*.py|*.sh to Sofia ~/pt-harvest/
#           sv.sh view <tag> [view.py opts]  -> name-safe screenshot derivatives, copied to $OUT
#           sv.sh run <script.py> [args]     -> run ~/pt-harvest/<script> with the harvest venv
# Every remote call goes through ssh-rc (plain Tailscale ssh always exits 0).
set -u
HOST=js-mac-pro
RC="$HOME/.claude/scripts/ssh-rc"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${PTH_OUT:-${TMPDIR:-/tmp}/pth_view}"
mkdir -p "$OUT"
case "${1:-}" in
push)
    scp -q "$HERE"/*.py "$HERE"/*.sh "$HOST:pt-harvest/" && echo pushed ;;
view)
    shift
    paths=$("$RC" $HOST "~/pt-harvest/.venv/bin/python ~/pt-harvest/view.py $*") || { echo "$paths"; exit 1; }
    for p in $paths; do
        case "$p" in /tmp/*) scp -q "$HOST:$p" "$OUT/" && echo "$OUT/$(basename "$p")" ;; *) echo "$p" ;; esac
    done ;;
run)
    shift
    "$RC" $HOST "cd ~/pt-harvest && ./.venv/bin/python $*" ;;
bg)  # sv.sh bg <logname> <script.py> [args] -> nohup on Sofia, log ~/pt-harvest/logs/<logname>.log, prints pid
    shift; lg="$1"; shift
    "$RC" $HOST "cd ~/pt-harvest && mkdir -p logs && (nohup ./.venv/bin/python $* > logs/$lg.log 2>&1 < /dev/null & echo pid \$!)" ;;
wait)  # sv.sh wait <logname> <maxsec> <regex> -> poll ~/pt-harvest/logs/<logname>.log (+ clicker.log) until regex matches
    lg="$2"; max="$3"; rx="$4"; t0=$(date +%s)
    while :; do
        o=$("$RC" $HOST "cd ~/pt-harvest && grep -h -E '$rx' logs/$lg.log logs/clicker.log 2>/dev/null | tail -5")
        [ -n "$o" ] && { echo "$o"; echo "after $(( $(date +%s) - t0 ))s"; exit 0; }
        [ $(( $(date +%s) - t0 )) -ge "$max" ] && { echo "timeout ${max}s"; exit 1; }
        sleep 6
    done ;;
sh)  # sv.sh sh '<cmd>' -> plain shell on Sofia in ~/pt-harvest (caller keeps names out of output)
    shift
    "$RC" $HOST "cd ~/pt-harvest && $*" ;;
*) sed -n 2,5p "$0"; exit 64 ;;
esac
