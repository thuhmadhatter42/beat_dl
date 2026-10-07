#!/bin/bash
# Sofia-side supervisor for the harvest batch (plan §6). Start it with nohup from ~/pt-harvest:
#   cd ~/pt-harvest && nohup ./run_batch.sh 200 > logs/batch.log 2>&1 < /dev/null &
# - keeps dialog_clicker.py running (restarts it if it dies)
# - runs `harvest.py batch --target N`; restarts it after a crash (max 8), resumable by DB
# - stops for good on: target reached / manifest exhausted (rc 0), BLOCKED (rc 3), 4 errors in a row (rc 4),
#   or a STOP file (touch ~/pt-harvest/STOP)
# Pid of this supervisor: ~/pt-harvest/batch.pid
cd "$HOME/pt-harvest" || exit 1
TARGET="${1:-200}"
export GRPC_VERBOSITY=ERROR GRPC_ENABLE_FORK_SUPPORT=false PYTHONUNBUFFERED=1
echo $$ > batch.pid
PY=./.venv/bin/python
ensure_clicker() {
    if ! { [ -f clicker.pid ] && kill -0 "$(cat clicker.pid)" 2>/dev/null; }; then
        nohup $PY dialog_clicker.py >> logs/clicker.log 2>&1 < /dev/null &
        sleep 2
        echo "$(date '+%F %T') supervisor: dialog_clicker started pid $(cat clicker.pid 2>/dev/null)"
    fi
}
crashes=0
while :; do
    [ -f STOP ] && { echo "$(date '+%F %T') supervisor: STOP file, exiting"; break; }
    ensure_clicker
    ( while sleep 60; do ensure_clicker; done ) & keeper=$!
    echo "$(date '+%F %T') supervisor: harvest batch start (target $TARGET)"
    $PY harvest.py batch --target "$TARGET"
    rc=$?
    kill $keeper 2>/dev/null
    echo "$(date '+%F %T') supervisor: harvest batch exited rc=$rc"
    case $rc in
        0|3|4) break ;;
        *) crashes=$((crashes + 1)); [ $crashes -ge 8 ] && { echo "supervisor: 8 crashes, giving up"; break; }
           sleep 30 ;;
    esac
done
echo "$(date '+%F %T') supervisor: done (dialog_clicker left running for the open Pro Tools: stop it with kill \$(cat clicker.pid))"
rm -f batch.pid
