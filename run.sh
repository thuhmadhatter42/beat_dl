#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf "Input URL: "
read -r url

[ -z "$url" ] && exit 0

python3 "$SCRIPT_DIR/downloader.py" "$url"
