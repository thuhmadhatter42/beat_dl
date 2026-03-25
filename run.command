#!/bin/bash
cd "$(dirname "$0")"

# Load brew into PATH (handles both Apple Silicon and Intel)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

bash run.sh

echo ""
read -p "Press Enter to close..."
