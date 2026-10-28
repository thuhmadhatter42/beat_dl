#!/bin/bash
# Builds and signs the bundled tool runtime: app/build/runtime/{arm64,x86_64}/
#   python/  (python-build-standalone 3.11 + essentia + numpy, installed offline from vendor wheels)
#   bin/     ffmpeg ffprobe yt-dlp   (arm64 also gets bin-legacy/ = ffmpeg 7.1.1 for macOS 11)
#   scripts/ downloader.py bpm.py tempocnn_np.py app_run.py models/
# Usage: app/runtime.sh build | scripts | sign | all
#   scripts = refresh only scripts/ (+ their .pyc) in an already built runtime: fast; build.sh runs it every time
set -euo pipefail
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$APP/.." && pwd)"
OUT="$APP/build/runtime"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: J Shriver (9WTFGV63S2)}"
ENTS="$APP/entitlements.plist"
ENTS_YTDLP="$APP/entitlements-ytdlp.plist"   # yt-dlp only: see that file
ARCHES="arm64 x86_64"

export PYTHONNOUSERSITE=1 PIP_CONFIG_FILE=/dev/null PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH PYTHONHOME

run_arch() {  # run a command natively for arch $1
  local a="$1"; shift
  if [ "$a" = x86_64 ]; then arch -x86_64 "$@"; else "$@"; fi
}

build_arch() {
  local a="$1" v="$ROOT/vendor/macos-$1" d="$OUT/$1"
  echo "== build $a"
  rm -rf "$d"; mkdir -p "$d/bin"
  tar -xzf "$v/python.tar.gz" -C "$d"
  [ -x "$d/python/bin/python3" ] || { echo "python/ not found after untar"; exit 1; }
  run_arch "$a" "$d/python/bin/python3" -m pip install --no-user --no-index --find-links "$v/wheels" \
    --disable-pip-version-check -q essentia numpy
  unzip -oq "$v/ffmpeg.zip" -d "$d/bin"; unzip -oq "$v/ffprobe.zip" -d "$d/bin"
  cp -f "$ROOT/vendor/yt-dlp" "$d/bin/yt-dlp"
  if [ "$a" = arm64 ]; then
    mkdir -p "$d/bin-legacy"
    unzip -oq "$ROOT/vendor/macos-arm64-legacy/ffmpeg.zip" -d "$d/bin-legacy"
    unzip -oq "$ROOT/vendor/macos-arm64-legacy/ffprobe.zip" -d "$d/bin-legacy"
  fi
  chmod +x "$d"/bin/* 2>/dev/null || true
  [ -d "$d/bin-legacy" ] && chmod +x "$d"/bin-legacy/*
  rm -rf "$d/python/include" "$d/python/share"
}

build_scripts() {
  local s="$OUT/scripts" f
  rm -rf "$s"; mkdir -p "$s/models"
  for f in downloader.py bpm.py tempocnn_np.py; do cp -f "$ROOT/$f" "$s/"; done
  if [ -f "$ROOT/app_run.py" ]; then cp -f "$ROOT/app_run.py" "$s/"; else echo "  (app_run.py not present yet: Task 2)"; fi
  cp -f "$ROOT/models/deeptemp-k16-3.npz" "$s/models/"
}

precompile() {
  # Each arch's own python writes its .pyc; the signed tree is never written at run time.
  local a
  for a in $ARCHES; do
    run_arch "$a" "$OUT/$a/python/bin/python3" -m compileall -q "$OUT/$a/python" >/dev/null || true  # essentia ships py2 example scripts that cannot compile
  done
  "$OUT/arm64/python/bin/python3" -m compileall -q "$OUT/scripts"
  # pip is never run on a user's Mac: drop its bytecode
  find "$OUT" -type d -name __pycache__ -path '*/site-packages/pip/*' -prune -exec rm -rf {} +
}

do_build() {
  mkdir -p "$OUT"
  local a
  for a in $ARCHES; do build_arch "$a"; done
  build_scripts
  precompile
  echo "built: $OUT"
}

do_sign() {
  echo "== sign with: $IDENTITY"
  local list; list="$(mktemp)"
  find "$OUT" -type f -exec file {} + | grep -F 'Mach-O' | sed -e 's/ (for architecture [^)]*)//' -e 's/:[[:space:]].*//' | sort -u > "$list"
  # deepest first
  awk -F/ '{print NF "\t" $0}' "$list" | sort -rn | cut -f2- | while IFS= read -r f; do
    if [ "${SKIP_YTDLP:-0}" = 1 ] && [ "$(basename "$f")" = yt-dlp ]; then echo "  skip $f"; continue; fi
    chmod u+w "$f"
    ents="$ENTS"; [ "$(basename "$f")" = yt-dlp ] && ents="$ENTS_YTDLP"
    codesign --force --options runtime --timestamp --entitlements "$ents" --sign "$IDENTITY" "$f"
  done
  local bad=0 f
  while IFS= read -r f; do
    codesign --verify --strict "$f" 2>&1 || { echo "VERIFY FAIL $f"; bad=1; }
  done < "$list"
  echo "verified $(wc -l < "$list" | tr -d ' ') Mach-O files"
  rm -f "$list"
  return $bad
}

case "${1:-}" in
  build) do_build ;;
  scripts) build_scripts; "$OUT/arm64/python/bin/python3" -m compileall -q "$OUT/scripts" ;;
  sign) do_sign ;;
  all) do_build; do_sign ;;
  *) echo "usage: $0 build|scripts|sign|all"; exit 2 ;;
esac
