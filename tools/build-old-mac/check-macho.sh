#!/bin/bash
# check-macho.sh <wheel|dir|file> <max-minos>
# For every Mach-O inside: print arch + minos (LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX), fail if any
# minos > max, fail on any linked library outside /usr/lib and /System, fail on SDL / libav* / tensorflow
# references.
set -euo pipefail
src="$1"; max="$2"
tmp=""
if [ -f "$src" ] && [ "${src##*.}" = whl ]; then
    tmp="$(mktemp -d)"; unzip -q "$src" -d "$tmp"; root="$tmp"
else
    root="$src"
fi
vercmp_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }
fail=0; n=0
while IFS= read -r -d '' f; do
    file -b "$f" | grep -q Mach-O || continue
    n=$((n + 1))
    for a in $(lipo -archs "$f"); do
        minos="$(otool -arch "$a" -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit} /LC_VERSION_MIN_MACOSX/{v=1} v&&/version/{print $2; exit}')"
        printf '%-8s minos %-6s %s\n' "$a" "${minos:-?}" "${f#"$root"/}"
        if [ -z "$minos" ] || ! vercmp_le "$minos" "$max"; then echo "  FAIL: minos ${minos:-missing} > $max"; fail=1; fi
        while read -r lib; do
            case "$lib" in
                /usr/lib/*|/System/*) ;;
                *) echo "  FAIL: links $lib"; fail=1 ;;
            esac
        done < <(otool -arch "$a" -L "$f" | tail -n +2 | awk '{print $1}')
    done
    hits="$(strings -a "$f" | grep -iE 'libSDL|SDL2|libavcodec|libavformat|libavdevice|libtensorflow' || true)"
    if [ -n "$hits" ]; then
        echo "  FAIL: SDL/ffmpeg/tensorflow reference in $(basename "$f"):"
        printf '%s\n' "$hits" | head -5 | sed 's/^/    /'
        fail=1
    fi
done < <(find "$root" -type f -print0)
if [ -n "$tmp" ] && [ -d "$tmp" ]; then rm -r "${tmp:?}"; fi
[ "$n" -gt 0 ] || { echo "no Mach-O files found"; exit 1; }
if [ "$fail" != 0 ]; then exit 1; fi
echo "OK: $n Mach-O file(s), all minos <= $max, only /usr/lib + /System, no SDL/ffmpeg/TF"
