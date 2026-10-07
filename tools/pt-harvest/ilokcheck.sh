#!/bin/bash
# Sofia: is an iLok on USB, which licence helpers run, is Pro Tools up (no names printed).
echo "-- USB iLok:"; system_profiler SPUSBDataType 2>/dev/null | grep -i -A2 'ilok' | grep -iE 'ilok|serial' | sed 's/Serial Number:.*/Serial Number: <present>/' | head -6
echo "-- licence processes:"; pgrep -fl -i 'pace|ilok|eden|licens' | awk '{print $1, $NF}' | sed 's|.*/||' | head -8
echo "-- pro tools:"; pgrep -f 'Pro Tools[^/]*\.app/Contents/MacOS/Pro Tools$' || echo "not running"
