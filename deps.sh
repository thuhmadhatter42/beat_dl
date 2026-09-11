#!/bin/bash
# Dependency check + install, shared by install.command and run.sh.
# Source this file, then call ensure_deps (every launch) and maybe_upgrade_ytdlp.

DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$DEPS_DIR/.last-ytdlp-upgrade"
UPGRADE_EVERY_DAYS=7

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

# Installs whatever is missing. Prints nothing when everything is present.
ensure_deps() {
    load_brew

    if ! command -v brew &>/dev/null; then
        echo "▸ Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        load_brew
    fi

    for tool in yt-dlp ffmpeg; do
        if ! command -v "$tool" &>/dev/null; then
            echo "▸ Installing $tool..."
            brew install "$tool"
        fi
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
    brew upgrade yt-dlp >/dev/null 2>&1
    touch "$STAMP"
}

# Upgrade if the stamp is missing or older than UPGRADE_EVERY_DAYS.
maybe_upgrade_ytdlp() {
    command -v brew &>/dev/null || return
    if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mtime +"$UPGRADE_EVERY_DAYS" 2>/dev/null)" ]; then
        upgrade_ytdlp
    fi
}
