#!/bin/bash
# Dependency check + install, shared by install.command and run.sh.
# Source this file, then call ensure_deps (every launch) and maybe_upgrade_ytdlp.

DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DEPS_DIR/.last-ytdlp-upgrade"
UPGRADE_EVERY_DAYS=7

# yt-dlp, ffmpeg and ffprobe live in ./bin as standalone binaries, owned by whoever
# cloned the repo. No Homebrew: a brew owned by another Mac user can't install or
# upgrade anything, and a brew upgrade can break brew's yt-dlp (seen 2026-10-06).
BIN_DIR="$DEPS_DIR/bin"
export PATH="$BIN_DIR:$PATH"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
# Static macOS builds, ffmpeg 9.0.2 (ffmpeg doesn't go stale, so pinned)
case "$(uname -m)" in
    arm64) FFMPEG_BASE="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2" ;;
    *)     FFMPEG_BASE="https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2" ;;
esac

load_brew() {
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

have_librosa() {
    # find_spec avoids importing librosa (slow); we only need to know it's there
    python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('librosa') else 1)" 2>/dev/null
}

have_essentia() {
    # essentia-tensorflow (TempoCNN BPM + HPCP key detector); same find_spec trick
    python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('essentia') else 1)" 2>/dev/null
}

numba_imports() {
    # librosa needs numba, and numba refuses to import when it lags numpy (seen 2026-09-11:
    # numpy 2.5.3 needed numba >= 0.67). ~0.5 s; a full "import librosa.beat" would be ~3 s.
    python3 -c "import numba" 2>/dev/null
}

runs() { "$BIN_DIR/$1" -version &>/dev/null || "$BIN_DIR/$1" --version &>/dev/null; }

install_ytdlp() {
    echo "▸ Installing yt-dlp..."
    curl -fsSL "$YTDLP_URL" -o "$BIN_DIR/yt-dlp" && chmod +x "$BIN_DIR/yt-dlp"
    runs yt-dlp || echo "❌ yt-dlp didn't install. Check the internet connection and run again."
}

install_ffmpeg_tool() {  # $1 = ffmpeg | ffprobe
    echo "▸ Installing $1..."
    local tmp; tmp="$(mktemp -d)"
    if curl -fsSL "$FFMPEG_BASE/$1.zip" -o "$tmp/$1.zip" \
       && [ "$(shasum -a 256 "$tmp/$1.zip" | cut -d' ' -f1)" = "$(curl -fsSL "$FFMPEG_BASE/$1.zip.sha256" | cut -d' ' -f1)" ] \
       && unzip -oq "$tmp/$1.zip" -d "$tmp"; then
        mv -f "$tmp/$1" "$BIN_DIR/$1" && chmod +x "$BIN_DIR/$1"
    fi
    rm -rf "$tmp"
    runs "$1" || echo "❌ $1 didn't install. Check the internet connection and run again."
}

# Installs whatever is missing. Prints nothing when everything is present.
ensure_deps() {
    load_brew   # only so python3/pip3 from an existing brew are on PATH; brew itself is never run
    export PATH="$BIN_DIR:$PATH"
    mkdir -p "$BIN_DIR"

    runs yt-dlp || install_ytdlp
    for tool in ffmpeg ffprobe; do
        runs "$tool" || install_ffmpeg_tool "$tool"
    done

    # One analyzer, picked automatically. bpm.py uses whichever is installed:
    #   essentia-tensorflow (best; needs a wheel for this Mac's macOS/CPU/Python)
    #   librosa             (fallback; installs almost everywhere)
    if ! have_essentia && ! have_librosa; then
        echo "▸ Installing the BPM/key analyzer..."
        if pip3 install essentia-tensorflow --break-system-packages --prefer-binary >/dev/null 2>&1 \
           && python3 -c "import essentia.standard" >/dev/null 2>&1; then
            echo "  ✓ essentia (TempoCNN + HPCP)"
        else
            pip3 uninstall -y essentia-tensorflow >/dev/null 2>&1
            echo "  no essentia build for this Mac — installing librosa instead"
            # --prefer-binary avoids compiling llvmlite from source
            pip3 install librosa --break-system-packages --prefer-binary >/dev/null 2>&1
            if have_librosa; then
                echo "  ✓ librosa"
            else
                echo "❌ Neither analyzer installed. Downloads still work; no BPM/key tags."
                echo "   Try:  brew install llvm   then run install.command again."
            fi
        fi
    fi

    # librosa's numba refuses to import when it lags numpy (seen 2026-09-11)
    if ! have_essentia && have_librosa && ! numba_imports; then
        echo "▸ Repairing librosa (numba/numpy mismatch)..."
        pip3 install -U numba --break-system-packages --prefer-binary >/dev/null 2>&1
        numba_imports || echo "❌ librosa still broken; no BPM/key tags until fixed."
    fi

    chmod +x "$DEPS_DIR"/run.sh "$DEPS_DIR"/run.command "$DEPS_DIR"/install.command 2>/dev/null
}

# Upgrades yt-dlp (the only dep that goes stale) and stamps the time.
upgrade_ytdlp() {
    echo "▸ Updating yt-dlp..."
    "$BIN_DIR/yt-dlp" -U >/dev/null 2>&1 || install_ytdlp
    touch "$STAMP"
}

# Upgrade if the stamp is missing or older than UPGRADE_EVERY_DAYS.
maybe_upgrade_ytdlp() {
    if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mtime +"$UPGRADE_EVERY_DAYS" 2>/dev/null)" ]; then
        upgrade_ytdlp
    fi
}
