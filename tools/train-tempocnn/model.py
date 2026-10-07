"""PyTorch replica of deeptemp-k16-3, layer for layer the same as tempocnn_np.predict:

  12 x [conv 1xk over time (SAME, odd k) + bias -> ReLU -> BatchNorm (inference form)]
  2x2 max-pool after conv 1/3/5/7/9, 1x2 (time) max-pool after conv 11,
  1x1 conv to 256 + bias -> ReLU -> mean over (mels, time) = logits -> softmax. Class i = 30 + i BPM.

BatchNorm is computed exactly as the TF graph (and tempocnn_np) folds it:
  mul = rsqrt(var + eps) * gamma;  y = x * mul + (beta - mean * mul)
mean/var/eps are frozen buffers (a fine-tune on ~150 beats must not re-estimate them); gamma/beta train.

Tensor layout: (batch, 1, 40 mels, 256 frames). tempocnn_np.patches gives (batch, 40, 256, 1).
"""
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

POOL_AFTER = {1: (2, 2), 3: (2, 2), 5: (2, 2), 7: (2, 2), 9: (2, 2), 11: (1, 2)}  # (mels, time)
N_LAYERS = 12


class FrozenBN(nn.Module):
    def __init__(self, c):
        super().__init__()
        self.gamma = nn.Parameter(torch.ones(c))
        self.beta = nn.Parameter(torch.zeros(c))
        self.register_buffer("mean", torch.zeros(c))
        self.register_buffer("var", torch.ones(c))
        self.register_buffer("eps", torch.tensor(1e-3))

    def forward(self, x):
        mul = torch.rsqrt(self.var + self.eps) * self.gamma
        return x * mul[None, :, None, None] + (self.beta - self.mean * mul)[None, :, None, None]


class TempoCNN(nn.Module):
    def __init__(self, shapes):
        """shapes: {i: (cout, cin, k)} from the npz."""
        super().__init__()
        self.convs = nn.ModuleList()
        self.bns = nn.ModuleList()
        for i in range(N_LAYERS):
            cout, cin, k = shapes[i]
            assert k % 2 == 1, "TF SAME == symmetric padding only for odd kernels"
            self.convs.append(nn.Conv2d(cin, cout, (1, k), padding=(0, k // 2)))
            self.bns.append(FrozenBN(cout))
        self.head = nn.Conv2d(shapes[N_LAYERS - 1][0], 256, 1)

    def forward(self, x):
        """x (n, 1, 40, 256) z-scored patches -> (n, 256) logits (pre-softmax)."""
        for i in range(N_LAYERS):
            x = self.bns[i](F.relu(self.convs[i](x)))
            if i in POOL_AFTER:
                x = F.max_pool2d(x, POOL_AFTER[i])
        x = F.relu(self.head(x))
        return x.mean(dim=(2, 3))


def load_npz(path):
    with np.load(path) as z:
        W = {k: z[k] for k in z.files}
    m = TempoCNN({i: W[f"conv{i}_w"].shape for i in range(N_LAYERS)})
    with torch.no_grad():
        for i in range(N_LAYERS):
            m.convs[i].weight.copy_(torch.from_numpy(W[f"conv{i}_w"][:, :, None, :]))
            m.convs[i].bias.copy_(torch.from_numpy(W[f"conv{i}_b"]))
            bn = m.bns[i]
            bn.gamma.copy_(torch.from_numpy(W[f"bn{i}_gamma"]))
            bn.beta.copy_(torch.from_numpy(W[f"bn{i}_beta"]))
            bn.mean.copy_(torch.from_numpy(W[f"bn{i}_mean"]))
            bn.var.copy_(torch.from_numpy(W[f"bn{i}_var"]))
            bn.eps.copy_(torch.from_numpy(np.asarray(W[f"bn{i}_eps"])))
        m.head.weight.copy_(torch.from_numpy(W["head_w"][:, :, None, None]))
        m.head.bias.copy_(torch.from_numpy(W["head_b"]))
    return m


def to_arrays(m):
    """Model -> dict with exactly the original npz keys, shapes and dtypes (float32)."""
    f = lambda t: t.detach().cpu().numpy().astype(np.float32)   # noqa: E731
    W = {}
    for i in range(N_LAYERS):
        W[f"conv{i}_w"] = f(m.convs[i].weight)[:, :, 0, :].copy()
        W[f"conv{i}_b"] = f(m.convs[i].bias)
        bn = m.bns[i]
        W[f"bn{i}_gamma"], W[f"bn{i}_beta"] = f(bn.gamma), f(bn.beta)
        W[f"bn{i}_mean"], W[f"bn{i}_var"] = f(bn.mean), f(bn.var)
        W[f"bn{i}_eps"] = np.float32(f(bn.eps))
    W["head_w"] = f(m.head.weight)[:, :, 0, 0].copy()
    W["head_b"] = f(m.head.bias)
    return W


def save_npz(m, path, like):
    """Write with savez_compressed (as the extractor does), keys in the original's order; refuses to
    write if any key, shape or dtype differs from `like` (the original npz)."""
    W = to_arrays(m)
    with np.load(like) as z:
        ref = {k: (z[k].shape, z[k].dtype) for k in z.files}
        order = list(z.files)
    got = {k: (v.shape, v.dtype) for k, v in W.items()}
    assert got == ref, "exported arrays differ in keys/shapes/dtypes from the original"
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **{k: W[k] for k in order})


def to_torch(P):
    """tempocnn_np.patches output (n, 40, 256, 1) -> (n, 1, 40, 256)."""
    return torch.from_numpy(np.ascontiguousarray(np.transpose(P, (0, 3, 1, 2))))


def device():
    return torch.device("mps" if torch.backends.mps.is_available() else "cpu")
