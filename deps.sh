#!/bin/bash
# Dependency check + install, shared by install.command and run.sh.
# Source this file, then call ensure_deps (every launch) and maybe_upgrade_ytdlp.

DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DEPS_DIR/.last-ytdlp-upgrade"
UPGRADE_EVERY_DAYS=7

# yt-dlp, ffmpeg and ffprobe ship inside the repo (vendor/) and run from ./bin.
# No Homebrew: a brew owned by another Mac user can't install or upgrade anything,
# and a brew upgrade broke brew's yt-dlp on Studio-E-2 (2026-10-06).
# vendor/ is tracked; bin/ is not, so yt-dlp can self-update without dirtying git pull.
VENDOR_DIR="$DEPS_DIR/vendor"
BIN_DIR="$DEPS_DIR/bin"
export PATH="$BIN_DIR:$PATH"

# The BPM/key analyzer ships too: a standalone Python 3.11 (python-build-standalone 20261003)
# plus our own essentia build and numpy 1.26.4, installed offline into bin/python.
# The essentia wheel is built by tools/build-old-mac/essentia.sh without TensorFlow, ffmpeg or SDL:
# the PyPI essentia-tensorflow wheels needed macOS 13.1/12.1 and popped a "Failed loading SDL2
# library" dialog (then hung) on any Mac without Homebrew's SDL2. TempoCNN runs in numpy
# (tempocnn_np.py) and bpm.py decodes with ./bin/ffmpeg; same BPM + top-3 keys on all 80 bench tracks.
PY="$BIN_DIR/python/bin/python3"
export PY
# The bundled Python sees only what's in bin/python: no ~/.local packages (a user's numpy 2 would
# break essentia), no PYTHONPATH/PYTHONHOME, and pip ignores pip.conf ("user = true" on Sofia sent
# the analyzer into ~/.local, 2026-10-06).
export PYTHONNOUSERSITE=1 PIP_CONFIG_FILE=/dev/null
unset PYTHONPATH PYTHONHOME

# Every Mac gets the newest build that runs on it. Minimum macOS of each vendored build, measured
# over every Mach-O inside it with vtool/otool (2026-10-06):
#   yt-dlp_macos universal         10.15  upstream's stated floor
#   ffmpeg/ffprobe arm64 9.0.2     12.0   martin-riedl.de; no prebuilt static arm64 build goes lower
#   ffmpeg/ffprobe arm64 7.1.1     11.0   macos-arm64-legacy, ours: tools/build-old-mac/ffmpeg-arm64.sh
#                                         (minimal: just what yt-dlp's MP3 extraction + ffprobe use)
#   ffmpeg/ffprobe x86_64 7.1.1    10.9   evermeet.cx
#   python 3.11 arm64 / x86_64     11.0 / 10.15
#   essentia (ours) arm64 / x86_64 11.0 / 10.15
MIN_MACOS=10.15             # Intel; every Apple Silicon Mac runs macOS 11+
FFMPEG_ARM64_MIN=12.0
PICKS="$BIN_DIR/.picks"
ANALYZER_BUILD=essentia-notf-1   # bump when the vendored analyzer changes, so bin/python is rebuilt

MACOS="$(sw_vers -productVersion)"
# hw.optional.arm64 is 1 on Apple Silicon even inside a Rosetta terminal, where uname -m lies
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then CPU=arm64; else CPU=x86_64; fi

at_least() {  # $1 >= $2, dotted versions
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}

# Sets FF_ARCH for this Mac (the only component with more than one build per CPU).
pick_builds() {
    FF_ARCH=x86_64
    if [ "$CPU" = arm64 ]; then
        FF_ARCH=arm64-legacy
        at_least "$MACOS" "$FFMPEG_ARM64_MIN" && FF_ARCH=arm64
    fi
}

have_essentia() {
    # find_spec avoids importing essentia (slow); we only need to know it's there
    "$PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)" 2>/dev/null
}

install_python() {
    local arch_dir="$VENDOR_DIR/macos-$CPU"
    echo "▸ Setting up the BPM/key analyzer (one time, under a minute)..."
    rm -rf "$BIN_DIR/python"
    tar -xzf "$arch_dir/python.tar.gz" -C "$BIN_DIR" || { echo "❌ Couldn't unpack Python."; return 1; }
    "$PY" -m pip install --no-user --no-index --find-links "$arch_dir/wheels" --disable-pip-version-check -q essentia numpy
    if "$PY" -c "import essentia.standard" >/dev/null 2>&1; then
        echo "  ✓ analyzer ready"
    else
        echo "❌ The analyzer didn't install. Downloads still work, without BPM/key in the name."
        return 1
    fi
}

ensure_python() {
    have_essentia || install_python
}

runs() { "$BIN_DIR/$1" -version &>/dev/null || "$BIN_DIR/$1" --version &>/dev/null; }

# Copies a bundled tool from vendor/ into bin/. ffmpeg/ffprobe: the zip picked for this Mac.
install_tool() {  # $1 = yt-dlp | ffmpeg | ffprobe
    if [ "$1" = yt-dlp ]; then
        cp -f "$VENDOR_DIR/yt-dlp" "$BIN_DIR/yt-dlp"
    else
        unzip -oq "$VENDOR_DIR/macos-$FF_ARCH/$1.zip" -d "$BIN_DIR"
    fi
    chmod +x "$BIN_DIR/$1" 2>/dev/null
    runs "$1" || echo "❌ $1 won't run on this Mac (macOS $MACOS, $CPU)."
}

# Installs whatever is missing. Prints nothing when everything is present and runs.
ensure_deps() {
    export PATH="$BIN_DIR:$PATH"
    mkdir -p "$BIN_DIR"

    if ! at_least "$MACOS" "$MIN_MACOS"; then
        echo "❌ beat_dl needs macOS $MIN_MACOS or newer; this Mac has $MACOS."
        return 1
    fi

    # A macOS update (or a bin/ copied from another Mac) can change which builds fit:
    # drop the picked ones so they're reinstalled for this Mac.
    pick_builds
    local picks="macos=$MACOS cpu=$CPU ffmpeg=$FF_ARCH analyzer=$ANALYZER_BUILD"
    if [ "$(cat "$PICKS" 2>/dev/null)" != "$picks" ]; then
        rm -rf "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe" "$BIN_DIR/python"
        echo "$picks" > "$PICKS"
    fi

    for tool in yt-dlp ffmpeg ffprobe; do
        runs "$tool" || install_tool "$tool"
    done

    ensure_python

    chmod +x "$DEPS_DIR"/run.sh "$DEPS_DIR"/run.command "$DEPS_DIR"/install.command 2>/dev/null
}

# Upgrades yt-dlp (the only dep that goes stale) and stamps the time.
upgrade_ytdlp() {
    echo "▸ Updating yt-dlp..."
    "$BIN_DIR/yt-dlp" -U >/dev/null 2>&1
    # An update that no longer runs here (upstream raised its macOS floor) goes back to the bundled one
    runs yt-dlp || cp -f "$VENDOR_DIR/yt-dlp" "$BIN_DIR/yt-dlp"
    touch "$STAMP"
}

# Upgrade if the stamp is missing or older than UPGRADE_EVERY_DAYS.
maybe_upgrade_ytdlp() {
    if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mtime +"$UPGRADE_EVERY_DAYS" 2>/dev/null)" ]; then
        upgrade_ytdlp
    fi
}
