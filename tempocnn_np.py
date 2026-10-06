"""
TempoCNN (deeptemp-k16-3) in plain numpy: same result as essentia's TensorFlow TempoCNN, no TensorFlow.

Mirrors essentia 2.1b6.dev1110 (commit 77a6a954), read from its source:
  rhythm/tempocnn.cpp                     argmax per patch + 30 BPM, 'majority' vote (first-seen wins ties)
  machinelearning/tensorflowpredicttempocnn.cpp
                                          FrameCutter(1024, 512) -> TensorflowInputTempoCNN -> patches of
                                          256 frames, hop 128, last partial patch discarded,
                                          TensorNormalize('standard', axis 0) = per-patch z-score,
                                          transpose to (batch, 40 mels, 256 frames, 1)
  spectral/tensorflowinputtempocnn.cpp    hann (not normalised) -> |FFT| -> 40 slaney mel bands
                                          20-5000 Hz, unit_tri, linear magnitude, at 11025 Hz
The mel front end runs through essentia's own FrameCutter + TensorflowInputTempoCNN (both are built
without TensorFlow), so only the network itself is reimplemented here. Weights: models/deeptemp-k16-3.npz,
extracted from models/deeptemp-k16-3.pb by tools/build-old-mac/extract-tempocnn-weights.py.

Network (proved against the GraphDef by the extractor): 12 x [conv 1xk over time (SAME) + bias -> ReLU
-> BatchNorm], 2x2 max-pool after conv 1/3/5/7/9, 1x2 (time) max-pool after conv 11, 1x1 conv to 256
+ ReLU, mean over (mels, time), softmax. Class i = (30 + i) BPM.
"""

from pathlib import Path

import numpy as np

WEIGHTS = Path(__file__).resolve().parent / "models" / "deeptemp-k16-3.npz"
FRAME_SIZE, HOP_SIZE, PATCH, PATCH_HOP, N_MELS = 1024, 512, 256, 128, 40
BPM_OFFSET = 30
_POOL_AFTER = {1: (2, 2), 3: (2, 2), 5: (2, 2), 7: (2, 2), 9: (2, 2), 11: (1, 2)}  # (mels, time)
_W = None


def _weights():
    global _W
    if _W is None:
        with np.load(WEIGHTS) as z:
            _W = {k: z[k] for k in z.files}
    return _W


def mel_bands(audio_11k):
    """(n_frames, 40) TempoCNN input bands, computed by essentia exactly as the TF wrapper does
    (streaming FrameCutter defaults, including its -100 dB noise on silent frames)."""
    import essentia.streaming as ess
    from essentia import Pool, run
    vec = ess.VectorInput(np.asarray(audio_11k, dtype=np.float32))
    fc = ess.FrameCutter(frameSize=FRAME_SIZE, hopSize=HOP_SIZE)
    tin = ess.TensorflowInputTempoCNN()
    pool = Pool()
    vec.data >> fc.signal
    fc.frame >> tin.frame
    tin.bands >> (pool, 'bands')
    run(vec)
    if 'bands' not in pool.descriptorNames():
        return np.zeros((0, N_MELS), np.float32)
    return np.asarray(pool['bands'], dtype=np.float32).reshape(-1, N_MELS)


def patches(bands):
    """VectorRealToTensor(lastPatchMode='discard', patchHopSize=128) + TensorNormalize('standard', 0).
    Returns (n, 40, 256, 1) float32 (batch, mels, time, channel)."""
    b = np.asarray(bands, dtype=np.float32)
    n = (len(b) - PATCH) // PATCH_HOP + 1 if len(b) >= PATCH else 0
    if n == 0:                                          # < 256 frames (~11.9 s): no patch at all
        return np.zeros((0, N_MELS, PATCH, 1), np.float32)
    P = np.stack([b[i * PATCH_HOP:i * PATCH_HOP + PATCH] for i in range(n)])
    flat = P.reshape(n, -1)
    mean = flat.mean(axis=1, dtype=np.float32)
    std = np.sqrt(((flat - mean[:, None]) ** 2).sum(axis=1, dtype=np.float32) / np.float32(flat.shape[1]))
    std[std == 0] = 1                                   # skipConstantSlices
    P = (P - mean[:, None, None]) / std[:, None, None]
    return np.ascontiguousarray(np.transpose(P, (0, 2, 1))[..., None], dtype=np.float32)


def _conv_time(x, w, b):
    """x (n, mels, time, cin); w (cout, cin, k) over the time axis, TF 'SAME' padding, stride 1."""
    k = w.shape[2]
    pad = k - 1
    xp = np.pad(x, ((0, 0), (0, 0), (pad // 2, pad - pad // 2), (0, 0)))
    T = x.shape[2]
    out = np.zeros(x.shape[:3] + (w.shape[0],), np.float32)
    for j in range(k):
        out += xp[:, :, j:j + T, :] @ np.ascontiguousarray(w[:, :, j].T)
    return out + b


def _maxpool(x, ph, pt):
    n, H, T, C = x.shape
    H2, T2 = H // ph, T // pt
    x = x[:, :H2 * ph, :T2 * pt, :].reshape(n, H2, ph, T2, pt, C)
    return x.max(axis=(2, 4))


def predict(P):
    """(n, 40, 256, 1) patches -> (n, 256) softmax tempo-class probabilities."""
    W = _weights()
    x = np.asarray(P, dtype=np.float32)
    for i in range(12):
        x = np.maximum(_conv_time(x, W[f'conv{i}_w'], W[f'conv{i}_b']), 0)
        mul = (np.float32(1) / np.sqrt(W[f'bn{i}_var'] + W[f'bn{i}_eps'])) * W[f'bn{i}_gamma']
        x = x * mul + (W[f'bn{i}_beta'] - W[f'bn{i}_mean'] * mul)
        if i in _POOL_AFTER:
            x = _maxpool(x, *_POOL_AFTER[i])
    x = np.maximum(x @ np.ascontiguousarray(W['head_w'].T) + W['head_b'], 0)
    logits = x.mean(axis=(1, 2), dtype=np.float32)
    e = np.exp(logits - logits.max(axis=1, keepdims=True))
    return (e / e.sum(axis=1, keepdims=True)).astype(np.float32)


def aggregate(pred):
    """essentia TempoCNN 'majority': per-patch argmax (first max) + 30; the most-voted BPM wins,
    ties go to the candidate seen first. No patches (clip under ~12 s) -> 0.0, which is what
    essentia-tensorflow returns there too (measured on a 5 s mp3)."""
    if len(pred) == 0:
        return 0.0, np.zeros(0, np.float32), np.zeros(0, np.float32)
    idx = pred.argmax(axis=1)
    local = (idx + BPM_OFFSET).astype(np.float32)
    probs = pred[np.arange(len(pred)), idx]
    best, best_votes = int(local[0]), 0
    seen = []
    for c in local.astype(int):
        if c in seen:
            continue
        votes = int((local.astype(int) == c).sum())
        if votes > best_votes:
            best, best_votes = c, votes
        seen.append(c)
    return float(best), local, probs


def tempo(audio_11k):
    """Drop-in for essentia.standard.TempoCNN(graphFilename=deeptemp-k16-3.pb)(audio_11k):
    returns (globalTempo, localTempo, localTempoProbabilities)."""
    P = patches(mel_bands(audio_11k))
    return aggregate(predict(P) if len(P) else np.zeros((0, 256), np.float32))
