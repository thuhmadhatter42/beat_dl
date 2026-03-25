#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    printf "\nInput URL: "
    read -r url

    [ -z "$url" ] && break

    echo "Downloading..."

    filepath=$(python3 "$SCRIPT_DIR/downloader.py" "$url")

    if [ $? -ne 0 ] || [ -z "$filepath" ]; then
        continue
    fi

    # Detect BPM + key (4 lines: BPM, key1, key2, key3)
    echo "Analyzing..."
    analysis=$(python3 "$SCRIPT_DIR/bpm.py" "$filepath" 2>/dev/null)

    bpm=$(echo "$analysis" | sed -n '1p')
    key1=$(echo "$analysis" | sed -n '2p')
    key2=$(echo "$analysis" | sed -n '3p')
    key3=$(echo "$analysis" | sed -n '4p')

    if [ -n "$bpm" ]; then
        k1=$(echo "$key1" | sed 's/ (.*//')
        k2=$(echo "$key2" | sed 's/ (.*//')
        k3=$(echo "$key3" | sed 's/ (.*//')
        dir=$(dirname "$filepath")
        base=$(basename "$filepath")
        ext="${base##*.}"
        stem="${base%.*}"
        newpath="$dir/$stem (${bpm} BPM $k1 $k2 $k3).$ext"
        mv "$filepath" "$newpath"
        echo "Downloaded: $(basename "$newpath")"
        echo "Key: $key1 | $key2 | $key3"
    else
        echo "Downloaded: $(basename "$filepath")"
    fi

done
