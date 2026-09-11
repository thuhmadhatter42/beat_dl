#!/bin/bash
# Re-create the 40-clip GiantSteps Tempo subset + TempoCNN models next to this script.
# Audio: JKU mirror of the GiantSteps Tempo dataset (Knees et al., ISMIR 2015), md5-verified.
# Ground truth: annotations_v2 (Schreiber & Müller 2018 crowd-corrected tempi).
set -e
cd "$(dirname "$0")"
[ -d gs ] || git clone -q --depth 1 https://github.com/GiantSteps/giantsteps-tempo-dataset.git gs
mkdir -p audio models
# curl on J's MBP can't resolve www.cp.jku.at (Tailscale DNS); pin the IP. Drop --resolve if DNS works.
IP=$(nslookup www.cp.jku.at 2>/dev/null | awk '/^Address/ && $2!~/#/ {print $2}' | tail -1); IP=${IP:-140.78.124.154}
while IFS=$'\t' read -r n genre bpm; do
  [ -s "audio/$n.mp3" ] && continue
  curl -sL -m 120 --resolve "www.cp.jku.at:443:$IP" -o "audio/$n.mp3" "https://www.cp.jku.at/datasets/giantsteps/backup/$n.mp3"
  [ "$(md5 -q "audio/$n.mp3")" = "$(awk '{print $1}' "gs/md5/$n.md5")" ] || echo "md5 mismatch: $n"
done < subset.tsv
for m in deeptemp-k16-3 deepsquare-k16-3; do
  [ -s "models/$m.pb" ] || curl -sL -m 120 -o "models/$m.pb" "https://essentia.upf.edu/models/tempo/tempocnn/$m.pb"
done
echo "audio: $(ls audio | wc -l | tr -d ' ') files, models: $(ls models)"
