#!/usr/bin/env python3
"""Load an .npz through tempocnn_np.py exactly as shipped (its file is not touched: only the module's
WEIGHTS path is pointed elsewhere, the same thing `models/deeptemp-k16-3.npz` being replaced would do)
and print, as JSON, the global BPM tempocnn_np gives for each cached track id.

Runs under the analyzer Python. Also checks keys/shapes/dtypes against the original npz.
Usage: bin/python/bin/python3 tools/train-tempocnn/check_npz.py MODEL.npz id1 id2 ...
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

tn = common.tempocnn_np


def main():
    npz, ids = Path(sys.argv[1]).resolve(), sys.argv[2:]
    with np.load(common.ORIG_NPZ) as a, np.load(npz) as b:
        same = list(a.files) == list(b.files) and all(
            a[k].shape == b[k].shape and a[k].dtype == b[k].dtype for k in a.files)
        changed = sum(not np.array_equal(a[k], b[k]) for k in a.files)
    tn.WEIGHTS, tn._W = npz, None
    out = {}
    for tid in ids:
        P = tn.patches(common.load_bands(tid))
        out[tid] = tn.aggregate(tn.predict(P) if len(P) else np.zeros((0, 256), np.float32))[0]
    print(json.dumps(dict(same_layout=same, arrays_changed=changed, n_arrays=len(tn._weights()),
                          global_bpm=out)))


if __name__ == "__main__":
    main()
