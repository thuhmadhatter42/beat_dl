"""Listening checks without ears (beat finder, plan §6 v2). Is a bounce a BEAT (drums, wide band)
or a vocal stem / silence? Pure numpy on a short mono 22050 Hz decode via ffmpeg.

features(path, tempo=None, start=None, dur=None) -> dict:
  mean_db      overall level (silence < -50)
  sub          energy share 25-120 Hz (kick/808/bass; a vocal stem is high-passed: ~0)
  low          energy share 25-250 Hz
  voice        energy share 250-3500 Hz (where a dry vocal lives)
  air          energy share 5-11 kHz (hats, cymbals)
  flat         median spectral flatness (noise-like drums high, tonal voice low)
  onset_rate   spectral-flux peaks per second (percussive hits)
  pulse        onset autocorrelation at the session's beat period (best of x1/2, x1, x2), 0..1
  pulse_any    best onset autocorrelation for any period 0.25-1.5 s (tempo-free regularity)
  lowpulse     same as pulse, on the 25-250 Hz band only (kick/808 on the grid)
verdict(f) -> (label, score, why): 'beat' | 'vocal' | 'silent' | 'unclear'
usage: audiocheck.py <wav> [tempo]  (prints the dict + verdict; no names)"""
from __future__ import annotations
import json, os, shutil, subprocess, sys

SR = 22050
HOP = 512
NFFT = 2048


def load(path, start=None, dur=None):
    import numpy as np
    ff = "/usr/local/bin/ffmpeg" if os.path.exists("/usr/local/bin/ffmpeg") else (shutil.which("ffmpeg") or "ffmpeg")
    cmd = [ff, "-v", "error"]
    if start is not None:
        cmd += ["-ss", f"{start:.3f}"]
    if dur is not None:
        cmd += ["-t", f"{dur:.3f}"]
    cmd += ["-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype("float64")


def _ac_at(env, lags):
    import numpy as np
    e = env - env.mean()
    den = float((e * e).sum()) or 1.0
    best = 0.0
    for lag in lags:
        lag = int(round(lag))
        if 1 <= lag < len(e) - 4:
            # tolerate +-1 frame of jitter
            v = max(float((e[:-L] * e[L:]).sum()) / den for L in (lag - 1, lag, lag + 1) if L >= 1)
            best = max(best, v)
    return best


def features(path, tempo=None, start=None, dur=None) -> dict:
    return features_x(load(path, start, dur), tempo)


def features_x(x, tempo=None) -> dict:
    """features() on a mono float array at SR."""
    import numpy as np
    out = {"n_s": round(len(x) / SR, 2)}
    if len(x) < SR:
        out["mean_db"] = None
        return out
    rms = float(np.sqrt(np.mean(x * x)))
    out["mean_db"] = round(20 * np.log10(rms + 1e-12), 1)
    win = np.hanning(NFFT)
    nfr = 1 + (len(x) - NFFT) // HOP
    fr = np.lib.stride_tricks.as_strided(x, shape=(nfr, NFFT), strides=(x.strides[0] * HOP, x.strides[0]))
    S = np.abs(np.fft.rfft(fr * win, axis=1)) ** 2            # power, frames x bins
    f = np.fft.rfftfreq(NFFT, 1 / SR)
    tot = S[:, (f >= 25) & (f <= 11000)].sum() + 1e-20

    def share(a, b):
        return round(float(S[:, (f >= a) & (f < b)].sum() / tot), 4)
    out.update(sub=share(25, 120), low=share(25, 250), voice=share(250, 3500), air=share(5000, 11000))
    band = S[:, (f >= 60) & (f <= 8000)] + 1e-20
    flat = np.exp(np.mean(np.log(band), axis=1)) / np.mean(band, axis=1)
    loud = S.sum(axis=1) > (S.sum(axis=1).max() * 1e-3)
    out["flat"] = round(float(np.median(flat[loud])) if loud.any() else 0.0, 4)
    L = np.log1p(S / (S.mean() + 1e-20))
    flux = np.maximum(L[1:] - L[:-1], 0).sum(axis=1)
    lowL = np.log1p(S[:, (f >= 25) & (f < 250)] / (S.mean() + 1e-20))
    lflux = np.maximum(lowL[1:] - lowL[:-1], 0).sum(axis=1)
    fps = SR / HOP
    thr = np.median(flux) + 1.5 * flux.std()
    peaks = (flux[1:-1] > thr) & (flux[1:-1] >= flux[:-2]) & (flux[1:-1] >= flux[2:])
    out["onset_rate"] = round(float(peaks.sum()) / (len(x) / SR), 2)
    lags_any = range(int(0.25 * fps), int(1.5 * fps) + 1)
    out["pulse_any"] = round(max(_ac_at(flux, [l]) for l in lags_any), 3)
    if tempo:
        p = 60.0 / tempo * fps
        lags = [p / 2, p, p * 2]
        out["pulse"] = round(_ac_at(flux, lags), 3)
        out["lowpulse"] = round(_ac_at(lflux, lags), 3)
        # loop: beats repeat bar after bar (same samples), a vocal does not. Mean cosine similarity of
        # log-band frames one bar / two beats apart, minus the similarity at an off-grid lag.
        nb = 40
        edges = np.geomspace(60, 10000, nb + 1)
        idx = np.digitize(f, edges) - 1
        B = np.stack([S[:, idx == k].sum(axis=1) for k in range(nb)], axis=1)
        B = np.log1p(B / (B.mean() + 1e-20))
        B = B - B.mean(axis=1, keepdims=True)
        nrm = np.linalg.norm(B, axis=1) + 1e-9

        def sim(lag):
            lag = int(round(lag))
            if lag < 1 or lag >= len(B) - 8:
                return None
            v = (B[:-lag] * B[lag:]).sum(axis=1) / (nrm[:-lag] * nrm[lag:])
            return float(np.mean(v))
        on = [s for s in (sim(p * 4), sim(p * 2), sim(p * 8)) if s is not None]
        off = [s for s in (sim(p * 1.37), sim(p * 2.61)) if s is not None]
        if on and off:
            out["loop"] = round(max(on) - float(np.mean(off)), 3)
            out["loop_on"] = round(max(on), 3)
    return out


def verdict(fe: dict):
    """Rules calibrated on harvested beat bounces vs vocal-stem probes (see beatfind.py header)."""
    db = fe.get("mean_db")
    if db is None or db <= -50:
        return "silent", 0.0, f"mean {db} dB"
    s = 0.0; why = []
    if fe["sub"] >= 0.08:
        s += 1.5; why.append("sub")
    elif fe["sub"] < 0.02:
        s -= 1.5; why.append("no-sub")
    if fe["low"] >= 0.25:
        s += 0.5
    if fe["air"] >= 0.01:
        s += 0.5; why.append("air")
    pulse = fe.get("pulse", fe["pulse_any"])
    if pulse >= 0.30:
        s += 1.5; why.append("pulse")
    elif pulse < 0.12:
        s -= 1.0; why.append("no-pulse")
    if fe.get("lowpulse", 0) >= 0.30:
        s += 0.5; why.append("lowpulse")
    if fe["voice"] >= 0.80 and fe["sub"] < 0.03:
        s -= 1.5; why.append("voice-band")
    label = "beat" if s >= 2.0 else ("vocal" if s <= -1.0 else "unclear")
    return label, round(s, 2), ",".join(why)


if __name__ == "__main__":
    t = float(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] != "-" else None
    st = float(sys.argv[3]) if len(sys.argv) > 3 else None
    du = float(sys.argv[4]) if len(sys.argv) > 4 else None
    fe = features(sys.argv[1], t, st, du)
    print(json.dumps(fe), verdict(fe) if fe.get("mean_db") is not None else "short")
