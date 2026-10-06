#!/bin/bash
# Build static, minimal ffmpeg + ffprobe 7.1.1 for arm64 macOS 11.0+ (libmp3lame inside).
# Needs: Xcode command line tools (clang, make), curl, shasum, zip. Nothing is installed system-wide.
# Output: vendor/macos-arm64-legacy/{ffmpeg,ffprobe}.zip (binary at the zip root).
# Usage: tools/build-old-mac/ffmpeg-arm64.sh [work_dir]   (default: ~/.cache/beat_dl-ffbuild)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${1:-$HOME/.cache/beat_dl-ffbuild}"
OUT="$REPO/vendor/macos-arm64-legacy"
JOBS="$(sysctl -n hw.ncpu)"

export MACOSX_DEPLOYMENT_TARGET=11.0
ARCHFLAGS="-arch arm64 -mmacosx-version-min=11.0"

FFMPEG_VER=7.1.1
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz"
# Neither ffmpeg.org nor lame publishes a sha256 file. ffmpeg publishes a GPG signature
# (.asc, release key FCF986EA15E6E293A5644F10B4322F04D67658D8), verified below when gpg exists;
# the hashes here were recorded from those verified downloads.
FFMPEG_SHA256=733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1
FFMPEG_KEY=FCF986EA15E6E293A5644F10B4322F04D67658D8
LAME_VER=3.100
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz"
LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e

[ "$(uname -m)" = arm64 ] || { echo "build on an arm64 Mac"; exit 1; }
mkdir -p "$WORK" "$OUT"

fetch() { # name url sha256 -> $WORK/dl-<name>/<file>; each download in its own directory
  local name=$1 url=$2 sha=$3 dir="$WORK/dl-$1" f
  f="$dir/$(basename "$url")"
  mkdir -p "$dir"
  [ -f "$f" ] || curl -fL --retry 3 -o "$f" "$url"
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$sha" ] || { echo "sha256 mismatch: $f"; rm -f "$f"; exit 1; }
}
fetch ffmpeg "$FFMPEG_URL" "$FFMPEG_SHA256"
fetch lame "$LAME_URL" "$LAME_SHA256"

# GPG signature check for ffmpeg (extra, only if gpg is installed)
if command -v gpg >/dev/null; then
  KD="$WORK/dl-ffmpeg-key"; mkdir -p "$KD"
  [ -f "$KD/ffmpeg-devel.asc" ] || curl -fsSL -o "$KD/ffmpeg-devel.asc" https://ffmpeg.org/ffmpeg-devel.asc
  [ -f "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz.asc" ] || curl -fsSL -o "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz.asc" "$FFMPEG_URL.asc"
  GH="$(mktemp -d /tmp/ffgpg.XXXXXX)"; chmod 700 "$GH"
  gpg --homedir "$GH" --batch --import "$KD/ffmpeg-devel.asc" >/dev/null 2>&1
  gpg --homedir "$GH" --batch --status-fd 1 --verify "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz.asc" \
      "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz" 2>/dev/null | grep -q "VALIDSIG $FFMPEG_KEY" \
      || { echo "ffmpeg GPG signature check failed"; rm -rf "$GH"; exit 1; }
  rm -rf "$GH"
  echo "ffmpeg GPG signature OK"
fi

PREFIX="$WORK/prefix"; rm -rf "$PREFIX" "$WORK/src"; mkdir -p "$PREFIX" "$WORK/src"

echo "== lame $LAME_VER"
tar -xzf "$WORK/dl-lame/lame-$LAME_VER.tar.gz" -C "$WORK/src"
( cd "$WORK/src/lame-$LAME_VER"
  # 3.100's bundled config.sub predates arm64: refresh from the system's automake copy if present
  for d in /opt/homebrew/share/automake-* /usr/local/share/automake-*; do
    [ -f "$d/config.sub" ] && { cp "$d/config.sub" "$d/config.guess" .; break; }
  done
  CC=clang CFLAGS="$ARCHFLAGS -O2" LDFLAGS="-arch arm64" \
  ./configure --prefix="$PREFIX" --host=aarch64-apple-darwin --disable-shared --enable-static \
              --disable-frontend --disable-decoder --disable-gtktest --enable-nasm=no
  make -j"$JOBS" && make install )

echo "== ffmpeg $FFMPEG_VER"
tar -xJf "$WORK/dl-ffmpeg/ffmpeg-$FFMPEG_VER.tar.xz" -C "$WORK/src"
PCM="pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_f64le,pcm_f64be,pcm_u8,pcm_alaw,pcm_mulaw"
( cd "$WORK/src/ffmpeg-$FFMPEG_VER"
  ./configure --prefix="$PREFIX/ff" --arch=arm64 --cc=clang \
    --extra-cflags="$ARCHFLAGS -I$PREFIX/include" --extra-ldflags="-arch arm64 -mmacosx-version-min=11.0 -L$PREFIX/lib" \
    --enable-static --disable-shared \
    --disable-everything --disable-autodetect --disable-doc --disable-debug \
    --disable-ffplay --disable-network \
    --enable-ffmpeg --enable-ffprobe \
    --enable-zlib --enable-libmp3lame \
    --enable-protocol=file,pipe \
    --enable-demuxer=mov,matroska,ogg,mp3,wav,aac,flac,mpegts,ac3,pcm_s16le,pcm_f32le \
    --enable-muxer=mp3,wav,ipod,adts,flac,null,pcm_s16le,pcm_f32le,pcm_s16be,pcm_s24le \
    --enable-parser=aac,aac_latm,opus,vorbis,mpegaudio,flac,ac3 \
    --enable-decoder="aac,aac_latm,opus,vorbis,mp3,mp3float,mp2,mp2float,flac,alac,ac3,$PCM" \
    --enable-encoder="libmp3lame,flac,pcm_s16le,pcm_s24le,pcm_f32le" \
    --enable-bsf=aac_adtstoasc,null,extract_extradata,vp9_superframe \
    --enable-filter=aresample,aformat,anull,anullsrc,anullsink,atrim,asetpts,volume,pan,channelmap,null,nullsink \
    && make -j"$JOBS" ffmpeg ffprobe )

echo "== package"
for t in ffmpeg ffprobe; do
  B="$WORK/src/ffmpeg-$FFMPEG_VER/$t"
  strip -x "$B"
  codesign --force -s - "$B"
  ( cd "$WORK/src/ffmpeg-$FFMPEG_VER" && rm -f "$OUT/$t.zip" && zip -q -X "$OUT/$t.zip" "$t" )
  echo "$t: $(vtool -show-build "$B" | awk '/minos/{print "minos " $2}') $(du -h "$OUT/$t.zip" | cut -f1) zip"
done
