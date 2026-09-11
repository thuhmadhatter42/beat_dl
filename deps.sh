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

    if ! have_essentia; then
        echo "▸ Installing essentia-tensorflow (BPM + key detector)..."
        # Single wheel, no compile. Do NOT also install plain "essentia": same package dir, this one is a superset.
        pip3 install essentia-tensorflow --break-system-packages --prefer-binary
        if ! have_essentia; then
            echo "❌ essentia-tensorflow failed to install. BPM/key will fall back to librosa (less accurate)."
        fi
    fi

    # librosa is the fallback only (used when essentia-tensorflow is missing); keep it installable.
    if ! have_librosa; then
        echo "▸ Installing librosa (fallback analyzer)..."
        # --prefer-binary avoids compiling llvmlite from source, which fails on many systems
        pip3 install librosa --break-system-packages --prefer-binary
        if ! have_librosa; then
            echo "❌ librosa failed to install. Fine as long as essentia-tensorflow is present."
            echo "   Try:  brew install llvm   then run install.command again."
        fi
    fi

    if have_librosa && ! numba_imports; then
        echo "▸ Updating numba (librosa's numba lags numpy)..."
        pip3 install -U numba --break-system-packages --prefer-binary
        if ! numba_imports; then
            echo "❌ numba still does not import. librosa fallback is unusable; essentia path unaffected."
        fi
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
