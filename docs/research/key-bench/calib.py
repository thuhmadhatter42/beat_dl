"""Confidence calibration check: for a results/<method>.json, bin top-1 confidence and report hit-rate per bin
(against GS+ labels), plus Spearman-ish sanity: mean conf of correct vs incorrect predictions."""
import json,sys
import numpy as np
from rescore import GSP
from bench import parse_key,mirex
for m in sys.argv[1:]:
    rows=[r for r in json.load(open(f'results/{m}.json'))['rows'] if r['track'] in GSP]
    conf=np.array([r['conf'] for r in rows]); ok=np.array([mirex(parse_key(r['pred']),GSP[r['track']])[0]=='correct' for r in rows])
    print(f'== {m}: mean conf correct={conf[ok].mean():.1f}  incorrect={conf[~ok].mean():.1f}')
    for lo,hi in [(0,40),(40,55),(55,70),(70,85),(85,101)]:
        sel=(conf>=lo)&(conf<hi)
        if sel.sum(): print(f'   conf {lo:3d}-{hi:3d}: n={sel.sum():2d} exact={100*ok[sel].mean():5.1f}%')
