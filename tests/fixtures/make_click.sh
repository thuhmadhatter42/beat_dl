#!/bin/bash
# Synthesizes tests/fixtures/click120.wav: 30 s, 120 BPM click (10 ms 1 kHz burst every 0.5 s,
# 44.1 kHz mono) over a quiet A-minor drone (A3 + C4 + E4). No real audio involved.
# Uses the bundled ffmpeg (app/build/runtime), else ./bin, else PATH; override with FFMPEG=.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FF="${FFMPEG:-}"
if [ -z "$FF" ]; then
  for c in "$ROOT/app/build/runtime/arm64/bin/ffmpeg" "$ROOT/app/build/runtime/x86_64/bin/ffmpeg" "$ROOT/bin/ffmpeg"; do
    if [ -x "$c" ]; then FF="$c"; break; fi
  done
fi
[ -n "$FF" ] || FF="$(command -v ffmpeg || true)"
[ -n "$FF" ] || { echo "no ffmpeg found (run app/runtime.sh build first)"; exit 1; }
EXPR="if(lt(mod(t\,0.5)\,0.01)\,0.9*sin(2*PI*1000*t)\,0)+0.08*(sin(2*PI*220*t)+sin(2*PI*261.63*t)+sin(2*PI*329.63*t))"
"$FF" -v error -y -f lavfi -i "aevalsrc=${EXPR}:s=44100:d=30" -c:a pcm_s16le "$HERE/click120.wav"
echo "wrote $HERE/click120.wav"
