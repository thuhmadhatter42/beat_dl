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
# plus essentia-tensorflow 2.1b6.dev1110 + numpy 1.26.4 wheels, installed offline into bin/python.
# dev1110 is the newest essentia with macOS 11+ wheels for both CPUs; newer ones need macOS 15,
# which is why pip installed nothing on Studio-E-2 (macOS 14.1). Wheels over 60 MB are split
# into .part-* files (GitHub's 100 MB file limit) and joined at install.
PY="$BIN_DIR/python/bin/python3"
export PY

have_essentia() {
    # find_spec avoids importing essentia (slow); we only need to know it's there
    "$PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)" 2>/dev/null
}

install_python() {
    local arch_dir="$VENDOR_DIR/macos-$(uname -m)" wheels whl part
    echo "▸ Setting up the BPM/key analyzer (one time, about a minute)..."
    rm -rf "$BIN_DIR/python"
    tar -xzf "$arch_dir/python.tar.gz" -C "$BIN_DIR" || { echo "❌ Couldn't unpack Python."; return 1; }
    wheels="$(mktemp -d)"
    cp "$arch_dir"/wheels/*.whl "$wheels"/
    for part in "$arch_dir"/wheels/*.part-aa; do
        [ -e "$part" ] || continue
        whl="$(basename "${part%.part-aa}")"
        cat "${part%aa}"* > "$wheels/$whl"
    done
    "$PY" -m pip install --no-index --find-links "$wheels" --disable-pip-version-check -q essentia-tensorflow numpy
    rm -rf "$wheels"
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

# Copies a bundled tool from vendor/ into bin/. ffmpeg 9.0.2 static builds, one zip per CPU.
install_tool() {  # $1 = yt-dlp | ffmpeg | ffprobe
    if [ "$1" = yt-dlp ]; then
        cp -f "$VENDOR_DIR/yt-dlp" "$BIN_DIR/yt-dlp"
    else
        unzip -oq "$VENDOR_DIR/macos-$(uname -m)/$1.zip" -d "$BIN_DIR"
    fi
    chmod +x "$BIN_DIR/$1" 2>/dev/null
    runs "$1" || echo "❌ $1 won't run on this Mac."
}

# Installs whatever is missing. Prints nothing when everything is present.
ensure_deps() {
    export PATH="$BIN_DIR:$PATH"
    mkdir -p "$BIN_DIR"

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
    touch "$STAMP"
}

# Upgrade if the stamp is missing or older than UPGRADE_EVERY_DAYS.
maybe_upgrade_ytdlp() {
    if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mtime +"$UPGRADE_EVERY_DAYS" 2>/dev/null)" ]; then
        upgrade_ytdlp
    fi
}
