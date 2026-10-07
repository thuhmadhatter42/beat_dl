#!/bin/bash
# Sofia: kill a hung Pro Tools (same pattern as harvest.py relaunch_pt). --dry lists the pid only.
PAT='Pro Tools[^/]*\.app/Contents/MacOS/Pro Tools$'
pgrep -f "$PAT" | sed 's/^/pt pid /'
[ "$1" = "--dry" ] && exit 0
pkill -9 -f "$PAT" && echo killed
sleep 5
pgrep -f "$PAT" >/dev/null && echo "still running" || echo "gone"
