# Key baseline: pt-ground-truth.sqlite3

60 files scored, 0 failed (none).

## bgate (shipping: bpm.keys_from_hpcp), beat bounces, by key_source

| group | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all | 30 | 24 (80%) | 28 (93%) | 0 | 2 | 0 | 4 | 0.833 |
| autotune | 22 | 20 (91%) | 22 (100%) | 0 | 1 | 0 | 1 | 0.932 |
| comment | 3 | 1 (33%) | 2 (67%) | 0 | 1 | 0 | 1 | 0.500 |
| comment+autotune | 5 | 3 (60%) | 4 (80%) | 0 | 0 | 0 | 2 | 0.600 |

## bgate (shipping: bpm.keys_from_hpcp), mix bounces, by key_source

| group | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all | 30 | 23 (77%) | 29 (97%) | 0 | 3 | 0 | 4 | 0.817 |
| autotune | 22 | 19 (86%) | 22 (100%) | 0 | 2 | 0 | 1 | 0.909 |
| comment | 3 | 1 (33%) | 2 (67%) | 0 | 1 | 0 | 1 | 0.500 |
| comment+autotune | 5 | 3 (60%) | 5 (100%) | 0 | 0 | 0 | 2 | 0.600 |

## edma (same HPCP, edma profile), beat bounces, by key_source

| group | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all | 30 | 22 (73%) | 27 (90%) | 0 | 2 | 2 | 4 | 0.780 |
| autotune | 22 | 20 (91%) | 22 (100%) | 0 | 1 | 1 | 0 | 0.941 |
| comment | 3 | 0 (0%) | 2 (67%) | 0 | 1 | 0 | 2 | 0.167 |
| comment+autotune | 5 | 2 (40%) | 3 (60%) | 0 | 0 | 1 | 2 | 0.440 |

## edma (same HPCP, edma profile), mix bounces, by key_source

| group | n | top-1 exact | in top-3 | relative | fifth | parallel | other | MIREX |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all | 30 | 23 (77%) | 27 (90%) | 0 | 2 | 2 | 3 | 0.813 |
| autotune | 22 | 19 (86%) | 22 (100%) | 0 | 1 | 2 | 0 | 0.905 |
| comment | 3 | 0 (0%) | 1 (33%) | 0 | 1 | 0 | 2 | 0.167 |
| comment+autotune | 5 | 4 (80%) | 4 (80%) | 0 | 0 | 0 | 1 | 0.800 |

Truth modes (beat rows): {'minor': 27, 'major': 3}

## 11 kHz round-trip parity (full-rate vs 44.1k->11025->44.1k, shipping detector)

40 files: top-1 unchanged 40/40, top-3 set unchanged 40/40.
