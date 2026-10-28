#!/usr/bin/env python3
"""Generates the faceplate textures once; the PNGs are committed.

  noise.png    the chassis grain: the mockup's feTurbulence fractalNoise (baseFrequency .9,
               2 octaves) through its colour matrix: white, alpha = .05 * noise.
  brushed.png  the header rail: fractalNoise with baseFrequency .004 x .4 (long horizontal
               streaks), 4 octaves, alpha = .42 * mean(noise) - .21, clipped at 0.

Both tile seamlessly (the noise is band-limited in the frequency domain on a periodic grid),
so the brushed rail has no seam where the mockup's 400 px SVG tile repeats.

Usage: python3 app/tools/textures.py   (writes app/Sources/Orion/Resources/*.png)
Needs numpy only; the PNG is written by hand with zlib.
"""
import struct
import zlib
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "Sources" / "Orion" / "Resources"


def png_la(path, alpha):
    """Writes a white grey+alpha PNG (colour type 4, 8 bit)."""
    h, w = alpha.shape
    a = np.clip(np.round(alpha * 255), 0, 255).astype(np.uint8)
    px = np.empty((h, w, 2), np.uint8)
    px[..., 0] = 255
    px[..., 1] = a
    raw = b"".join(b"\x00" + px[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 4, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    path.write_bytes(data)
    return len(data)


def octave(rng, w, h, fx, fy):
    """Periodic noise in [0,1] whose energy sits around frequency (fx, fy) cycles/px."""
    white = rng.standard_normal((h, w))
    kx = np.fft.fftfreq(w)[None, :]
    ky = np.fft.fftfreq(h)[:, None]
    # Gaussian low-pass at the octave's base frequency (feTurbulence ~ smoothed lattice noise).
    g = np.exp(-0.5 * ((kx / max(fx, 1e-6)) ** 2 + (ky / max(fy, 1e-6)) ** 2))
    n = np.real(np.fft.ifft2(np.fft.fft2(white) * g))
    n /= (n.std() + 1e-12)
    return n


def fractal(rng, w, h, fx, fy, octaves):
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * octave(rng, w, h, fx * 2 ** o, fy * 2 ** o)
        norm += amp
        amp *= 0.5
    total /= norm
    # fractalNoise maps to colour as (n + 1) / 2 with n roughly in [-1, 1]
    return np.clip(0.5 + 0.25 * total, 0, 1)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)

    # chassis grain: 128 px tile, alpha = .05 * noise
    n = fractal(rng, 128, 128, 0.9 / 2.2, 0.9 / 2.2, 2)
    s1 = png_la(OUT / "noise.png", 0.05 * n)

    # rail brush: wide enough for the rail (496 pt) at 1x; drawn at 1 px per point
    w, h = 512, 128
    chans = [fractal(rng, w, h, 0.004 / 2.2, 0.4 / 2.2, 4) for _ in range(3)]
    mean = sum(chans) / 3
    # The mockup's matrix: alpha = .14 * (r + g + b) - .21. Our noise has a narrower spread than
    # the SVG filter's, so it is stretched to the same range before the matrix is applied.
    mean = np.clip(0.5 + (mean - 0.5) * 1.7, 0, 1)
    a = np.clip(0.42 * mean - 0.21, 0, 1)
    s2 = png_la(OUT / "brushed.png", a)
    print(f"noise.png {s1} B, brushed.png {s2} B -> {OUT}")


if __name__ == "__main__":
    main()
