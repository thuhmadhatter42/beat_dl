#!/bin/bash
# Sofia: last N lines (default 12) of logs/batch.log since the last batch (re)start, grpc noise dropped.
cd "$HOME/pt-harvest" || exit 1
awk '/harvest batch start/{b=""} {b=b $0 "\n"} END{printf "%s", b}' logs/batch.log \
  | grep -v -E '^I[0-9]{4} |^F[0-9]{4} |^    @|ev_poll|Check failure' | cut -c1-${2:-420} | tail -n "${1:-12}"
[ -f BLOCKED ] && echo "BLOCKED: $(cat BLOCKED)"
[ -f STOP ] && echo "STOP present"
[ -f batch.pid ] && kill -0 "$(cat batch.pid)" 2>/dev/null && echo "supervisor alive" || echo "supervisor NOT running"
