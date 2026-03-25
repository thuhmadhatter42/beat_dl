#!/bin/bash
cd "$(dirname "$0")"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  beat_dl installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Homebrew ────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    echo "▸ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "✓ Homebrew already installed"
fi

# Load brew into PATH (handles both Apple Silicon and Intel)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# ── yt-dlp ──────────────────────────────────────────────────────────────────
echo ""
if ! command -v yt-dlp &>/dev/null; then
    echo "▸ Installing yt-dlp..."
    brew install yt-dlp
else
    echo "✓ yt-dlp already installed"
fi

# ── ffmpeg ──────────────────────────────────────────────────────────────────
echo ""
if ! command -v ffmpeg &>/dev/null; then
    echo "▸ Installing ffmpeg..."
    brew install ffmpeg
else
    echo "✓ ffmpeg already installed"
fi

# ── librosa ─────────────────────────────────────────────────────────────────
echo ""
if python3 -c "import librosa" &>/dev/null; then
    echo "✓ librosa already installed"
else
    echo "▸ Installing librosa..."
    pip3 install librosa --break-system-packages
fi

# ── Permissions ─────────────────────────────────────────────────────────────
echo ""
echo "▸ Setting permissions..."
chmod +x run.sh run.command install.command

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Done! Double-click run.command to start."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Press Enter to close..."
