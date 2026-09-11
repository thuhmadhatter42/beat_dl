#!/bin/bash
# Re-create the 40-clip GiantSteps Key subset + both label sets + the OpenKeyScan CNN checkpoint next to this script.
# Audio: JKU mirror of the GiantSteps Key dataset (Knees et al., ISMIR 2015), md5-verified.
# Labels: original repo .key files (ground_truth.json) and GiantSteps+ revised labels (Faraldo, Zenodo 1095691).
set -e
cd "$(dirname "$0")"
[ -d giantsteps-key-dataset-master ] || { curl -sL -m 120 -o gs.zip https://github.com/GiantSteps/giantsteps-key-dataset/archive/refs/heads/master.zip && unzip -qo gs.zip; }
[ -d gsplus ] || { curl -sL -m 120 -o gsplus_keys.zip "https://zenodo.org/api/records/1095691/files/keys.zip/content" && mkdir -p gsplus && unzip -qo gsplus_keys.zip -d gsplus; }
[ -d openkeyscan-analyzer ] || git clone -q --depth 1 https://github.com/rekordcloud/openkeyscan-analyzer.git   # CNN rows only (needs torch)
venv/bin/python fetch_gs.py     # downloads audio/*.mp3 for the ids in ground_truth.json (pins www.cp.jku.at IP; see script)
echo "audio: $(ls audio | wc -l | tr -d ' ') files"
