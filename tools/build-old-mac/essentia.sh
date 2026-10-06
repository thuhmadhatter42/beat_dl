#!/bin/bash
# Build essentia (no TensorFlow, no ffmpeg/SDL, everything static) as a CPython 3.11 wheel for old macOS.
#
#   tools/build-old-mac/essentia.sh arm64     -> vendor/macos-arm64/wheels-legacy/essentia-2.1b6.dev1110-cp311-cp311-macosx_11_0_arm64.whl
#   tools/build-old-mac/essentia.sh x86_64    -> vendor/macos-x86_64/wheels-legacy/essentia-2.1b6.dev1110-cp311-cp311-macosx_10_15_x86_64.whl
#
# Runs on an Apple Silicon Mac with Xcode / Command Line Tools (x86_64 is cross-compiled with -arch x86_64).
# Same essentia commit and the same FFTW / libsamplerate versions as the essentia-tensorflow 2.1b6.dev1110
# wheel it replaces (that wheel bundles fftw-3.3.10 and libsamplerate 0.2.2), so Spectrum / Resample / HPCP
# give the same numbers. Nothing is installed system-wide: downloads, build trees and a scratch venv (for
# pkgconf) live under $OLDBUILD_DIR. Every download is pinned and checked:
#   essentia  git commit 77a6a954f9497278ac214467e8040d40cbecdc30 (= 2.1b6.dev1110: v2.1_beta5 + 1110 commits)
#   eigen     git tag 3.4.0 -> commit 3147391d946bb4b6c68edd901f2add6ac1f31f8c (headers only)
#   fftw      3.3.10 tarball; upstream md5 8ccbf6a5ea78a16dbc3e1306e234cc5c (fftw.org .md5sum),
#             sha256 56c93254...26467 (same value Homebrew's fftw 3.3.10 formula pins)
#   libsamplerate 0.2.2 tarball; upstream GPG signature (David Seifert, B8D5315DA00072C0A860889FCE36E117202E3842)
#             verified good once, sha256 3258da28...43893 pinned here (also Homebrew's value)
#   pkgconf   PyPI wheel 3.0.7.post0 (build tool only), sha256 pinned, installed with --require-hashes
set -euo pipefail

ARCH="${1:-}"
case "$ARCH" in
    arm64)  TARGET=11.0;  PLAT=macosx_11_0_arm64;    FFTW_SIMD="" ;;
    x86_64) TARGET=10.15; PLAT=macosx_10_15_x86_64;  FFTW_SIMD="--enable-sse2 --enable-avx --enable-avx2" ;;
    *) echo "usage: $0 arm64|x86_64" >&2; exit 2 ;;
esac
[ "$(uname -m)" = arm64 ] || { echo "build host must be Apple Silicon" >&2; exit 2; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
W="${OLDBUILD_DIR:-${TMPDIR:-/tmp}/beat_dl-oldbuild}"
mkdir -p "$W"
W="$(cd "$W" && pwd)"
JOBS="$(sysctl -n hw.ncpu)"
OUT="$REPO/vendor/macos-$ARCH/wheels-legacy"

ESSENTIA_COMMIT=77a6a954f9497278ac214467e8040d40cbecdc30
EIGEN_TAG=3.4.0;   EIGEN_COMMIT=3147391d946bb4b6c68edd901f2add6ac1f31f8c
FFTW_URL=https://fftw.org/pub/fftw/fftw-3.3.10.tar.gz
FFTW_SHA256=56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467
FFTW_MD5=8ccbf6a5ea78a16dbc3e1306e234cc5c
LSR_URL=https://github.com/libsndfile/libsamplerate/releases/download/0.2.2/libsamplerate-0.2.2.tar.xz
LSR_SHA256=3258da280511d24b49d6b08615bbe824d0cacc9842b0e4caf11c52cf2b043893
PKGCONF_REQ="pkgconf==3.0.7.post0 --hash=sha256:47cbf6889d84297b9a4e1741ae016daa4e198f3ec8bab7ce74554cc50b77cce4"
VERSION=2.1b6.dev1110

log() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------- downloads (each in its own empty dir)
fetch_file() {  # dir url sha256 [md5]
    local d="$W/$1" url="$2" sha="$3" md5="${4:-}" f
    f="$d/$(basename "$url")"
    if [ ! -f "$f" ] || [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" != "$sha" ]; then
        rm -rf "$d"; mkdir -p "$d"
        curl -fsSL -o "$f" "$url"
    fi
    [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$sha" ] || { echo "sha256 mismatch: $f" >&2; exit 1; }
    [ -z "$md5" ] || [ "$(md5 -q "$f")" = "$md5" ] || { echo "md5 mismatch: $f" >&2; exit 1; }
    echo "$f"
}

fetch_git() {  # dir url commit [branch-for-shallow-clone]
    local d="$W/$1" url="$2" commit="$3" branch="${4:-}"
    if [ ! -d "$d/src/.git" ] || [ "$(git -C "$d/src" rev-parse HEAD)" != "$commit" ]; then
        rm -rf "$d"; mkdir -p "$d"
        if [ -n "$branch" ]; then
            git clone -q --depth 1 --branch "$branch" "$url" "$d/src"
        else
            git clone -q --filter=blob:none --no-checkout "$url" "$d/src"
            git -C "$d/src" checkout -q "$commit"
        fi
    fi
    [ "$(git -C "$d/src" rev-parse HEAD)" = "$commit" ] || { echo "commit mismatch: $url" >&2; exit 1; }
    echo "$d/src"
}

log "sources"
ESSENTIA_SRC="$(fetch_git dl-essentia https://github.com/MTG/essentia.git "$ESSENTIA_COMMIT")"
EIGEN_SRC="$(fetch_git dl-eigen https://gitlab.com/libeigen/eigen.git "$EIGEN_COMMIT" "$EIGEN_TAG")"
FFTW_TGZ="$(fetch_file dl-fftw "$FFTW_URL" "$FFTW_SHA256" "$FFTW_MD5")"
LSR_TXZ="$(fetch_file dl-libsamplerate "$LSR_URL" "$LSR_SHA256")"

# ---------------------------------------------------------------- host tools: python 3.11 (waf) + pkgconf
HOSTPY="$W/host-python/python/bin/python3"
if [ ! -x "$HOSTPY" ]; then
    rm -rf "$W/host-python"; mkdir -p "$W/host-python"
    tar -xzf "$REPO/vendor/macos-arm64/python.tar.gz" -C "$W/host-python"
fi
if [ ! -x "$W/tools-venv/bin/pkgconf" ]; then
    rm -rf "$W/tools-venv"
    "$HOSTPY" -m venv "$W/tools-venv"
    echo "$PKGCONF_REQ" > "$W/pkgconf-req.txt"
    "$W/tools-venv/bin/pip" install -q --disable-pip-version-check --no-deps --require-hashes -r "$W/pkgconf-req.txt"
fi
export PKGCONFIG="$W/tools-venv/bin/pkgconf"

# ---------------------------------------------------------------- per-arch toolchain
SDK="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="$TARGET"
export CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)"
ARCHFLAGS="-arch $ARCH -mmacosx-version-min=$TARGET -isysroot $SDK"
HOST_TRIPLE="$ARCH-apple-darwin"; [ "$ARCH" = arm64 ] && HOST_TRIPLE=aarch64-apple-darwin
B="$W/build-$ARCH"
P="$B/prefix"
rm -rf "$B"; mkdir -p "$P/lib/pkgconfig" "$P/include"

log "eigen $EIGEN_TAG headers"
mkdir -p "$P/include/eigen3"
cp -R "$EIGEN_SRC/Eigen" "$EIGEN_SRC/unsupported" "$P/include/eigen3/"
cat > "$P/lib/pkgconfig/eigen3.pc" <<EOF
prefix=$P
Name: Eigen3
Description: A C++ template library for linear algebra
Version: $EIGEN_TAG
Cflags: -I\${prefix}/include/eigen3
EOF

log "fftw 3.3.10 single precision, static ($ARCH ${FFTW_SIMD:-no SIMD, as Homebrew on arm64})"
mkdir -p "$B/fftw" && tar -xzf "$FFTW_TGZ" -C "$B/fftw" --strip-components 1
( cd "$B/fftw" && \
  CC="$CC -arch $ARCH" CFLAGS="-O3 -fomit-frame-pointer -fstrict-aliasing $ARCHFLAGS" \
  ./configure -q --host="$HOST_TRIPLE" --prefix="$P" --enable-single --enable-static --disable-shared \
      --disable-fortran --disable-doc $FFTW_SIMD && \
  make -s -j"$JOBS" && make -s install ) > "$B/fftw.log" 2>&1 || { tail -30 "$B/fftw.log"; exit 1; }

log "libsamplerate 0.2.2 static"
mkdir -p "$B/lsr" && tar -xJf "$LSR_TXZ" -C "$B/lsr" --strip-components 1
( cd "$B/lsr" && \
  CC="$CC -arch $ARCH" CFLAGS="-O2 $ARCHFLAGS" \
  ./configure -q --host="$HOST_TRIPLE" --prefix="$P" --enable-static --disable-shared \
      --disable-sndfile --disable-alsa --disable-fftw && \
  make -s -j"$JOBS" && make -s install ) \
  > "$B/lsr.log" 2>&1 || { tail -30 "$B/lsr.log"; exit 1; }

log "essentia $VERSION ($ESSENTIA_COMMIT) static library, FFTW, no TF/ffmpeg/yaml/taglib/chromaprint"
mkdir -p "$B/essentia"
git -C "$ESSENTIA_SRC" archive "$ESSENTIA_COMMIT" | tar -x -C "$B/essentia"
( cd "$B/essentia" && \
  CXXFLAGS="$ARCHFLAGS" LINKFLAGS="$ARCHFLAGS" CFLAGS="$ARCHFLAGS" \
  "$HOSTPY" waf configure --build-static --mode=release --fft=FFTW --lightweight=libsamplerate,fftw \
      --pkg-config-path="$P/lib/pkgconfig" --prefix="$P" && \
  "$HOSTPY" waf build -j"$JOBS" ) > "$B/essentia.log" 2>&1 || { tail -40 "$B/essentia.log"; exit 1; }
grep -E "detected|ignored|Building" "$B/essentia.log" | sed 's/^/   /' || true

log "python 3.11 extension"
mkdir -p "$B/py-$ARCH" "$B/numpy-$ARCH"
tar -xzf "$REPO/vendor/macos-$ARCH/python.tar.gz" -C "$B/py-$ARCH" python/include
unzip -q -o "$REPO"/vendor/macos-"$ARCH"/wheels/numpy-1.26.4-*.whl 'numpy/core/include/*' -d "$B/numpy-$ARCH"
E="$B/essentia/src"
INC=(-I"$B/py-$ARCH/python/include/python3.11" -I"$B/numpy-$ARCH/numpy/core/include"
     -I"$E/python" -I"$E/python/pytypes" -I"$E" -I"$E/essentia" -I"$E/essentia/scheduler"
     -I"$E/essentia/streaming" -I"$E/essentia/streaming/algorithms" -I"$E/essentia/utils" -I"$E/3rdparty"
     -I"$P/include" -I"$P/include/eigen3")
DEFS=(-DGTEST_HAS_TR1_TUPLE=0 -DEIGEN_PERMANENTLY_DISABLE_STUPID_WARNINGS -DEIGEN_MPL2_ONLY -D__STDC_CONSTANT_MACROS)
mkdir -p "$B/pyobj"
OBJS=()
for src in "$E"/python/essentia.cpp "$E"/python/parsing.cpp "$E"/python/pytypes/*.cpp; do
    o="$B/pyobj/$(basename "${src%.cpp}").o"
    "$CXX" -std=c++11 -O2 -DNDEBUG -fPIC -w $ARCHFLAGS "${DEFS[@]}" "${INC[@]}" -c "$src" -o "$o"
    OBJS+=("$o")
done
LIBESSENTIA="$(find "$B/essentia/build" -name libessentia.a | head -1)"
SO="$B/wheel/essentia/_essentia.cpython-311-darwin.so"
mkdir -p "$B/wheel/essentia"
"$CXX" -bundle -undefined dynamic_lookup $ARCHFLAGS -Wl,-dead_strip -o "$SO" "${OBJS[@]}" \
    "$LIBESSENTIA" "$P/lib/libfftw3f.a" "$P/lib/libsamplerate.a"
strip -x "$SO"

log "wheel"
( cd "$E/python" && find essentia -name '*.py' | while read -r f; do mkdir -p "$B/wheel/$(dirname "$f")"; cp "$f" "$B/wheel/$f"; done )
mkdir -p "$OUT"
"$HOSTPY" - "$B/wheel" "$OUT" "$VERSION" "$PLAT" "$ESSENTIA_COMMIT" <<'PY'
import base64, hashlib, os, sys, zipfile
root, out, version, plat, commit = sys.argv[1:]
di = f"essentia-{version}.dist-info"
meta = {
    f"{di}/METADATA": (f"Metadata-Version: 2.1\nName: essentia\nVersion: {version}\n"
                       "Summary: Essentia audio analysis (beat_dl legacy build: no TensorFlow, no ffmpeg, static FFTW + libsamplerate)\n"
                       f"Home-page: http://essentia.upf.edu\nLicense: AGPLv3\n"
                       "Requires-Dist: numpy>=1.8.2\nRequires-Dist: six\nRequires-Dist: pyyaml\n\n"
                       f"Built from https://github.com/MTG/essentia commit {commit} by beat_dl tools/build-old-mac/essentia.sh\n"),
    f"{di}/WHEEL": f"Wheel-Version: 1.0\nGenerator: beat_dl-build-old-mac\nRoot-Is-Purelib: false\nTag: cp311-cp311-{plat}\n",
    f"{di}/top_level.txt": "essentia\n",
}
files = []
for d, _, fs in os.walk(root):
    for f in fs:
        p = os.path.join(d, f)
        files.append((os.path.relpath(p, root), open(p, 'rb').read()))
files.sort()
files += [(k, v.encode()) for k, v in meta.items()]
rec = []
for name, data in files:
    h = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()
    rec.append(f"{name},sha256={h},{len(data)}")
rec.append(f"{di}/RECORD,,")
files.append((f"{di}/RECORD", ("\n".join(rec) + "\n").encode()))
whl = os.path.join(out, f"essentia-{version}-cp311-cp311-{plat}.whl")
with zipfile.ZipFile(whl, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in files:
        zi = zipfile.ZipInfo(name, date_time=(2023, 10, 20, 0, 0, 0))
        zi.external_attr = (0o755 if name.endswith('.so') else 0o644) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(zi, data)
print(whl, os.path.getsize(whl))
PY

log "checks"
WHL="$OUT/essentia-$VERSION-cp311-cp311-$PLAT.whl"
"$REPO/tools/build-old-mac/check-macho.sh" "$WHL" "$TARGET"
