"""Re-score saved results/*.json against original GiantSteps labels AND the revised GiantSteps+ labels
(Faraldo 2017, Zenodo 1095691). GS+ 'other' tracks are skipped; when GS+ lists two keys ('A | B') the first is used."""
import json,glob,sys
from bench import parse_key,mirex,fmt
orig=json.load(open('ground_truth.json')); gsp=json.load(open('ground_truth_gsplus.json'))
def gsp_key(v):
    first=v.split('|')[0].strip().split()
    if len(first)<2 or first[1] not in('major','minor'): return None
    return parse_key(' '.join(first[:2]))
GSP={n:gsp_key(v) for n,v in gsp.items()}; GSP={n:k for n,k in GSP.items() if k}
def score(rows,gt):
    rs=[r for r in rows if r['track'] in gt]
    cats=[mirex(parse_key(r['pred']),gt[r['track']]) for r in rs]
    n=len(rs)
    return dict(n=n,weighted=100*sum(w for _,w in cats)/n, exact=100*sum(c=='correct' for c,_ in cats)/n,
        fifth=100*sum(c=='fifth' for c,_ in cats)/n, relative=100*sum(c=='relative' for c,_ in cats)/n,
        parallel=100*sum(c=='parallel' for c,_ in cats)/n, other=100*sum(c=='other' for c,_ in cats)/n,
        top3=100*sum(fmt(*gt[r['track']]) in [k for k,_ in r['top3']] for r in rs)/n)
ORIG={n:parse_key(v) for n,v in orig.items()}
print(f"{'method':22} | {'orig: wtd exact':>16} | {'GS+: wtd exact fifth rel par other top3':>40}")
out={}
for f in sorted(glob.glob('results/*.json')):
    d=json.load(open(f))
    if 'summary' not in d: continue
    m=d['summary']['method']; rows=d['rows']
    a=score(rows,ORIG); b=score(rows,GSP); out[m]=dict(orig=a,gsplus=b,secs=d['summary']['secs_per_track'])
    print(f"{m:22} | {a['weighted']:6.1f} {a['exact']:6.1f}    | {b['weighted']:6.1f} {b['exact']:6.1f} {b['fifth']:5.1f} {b['relative']:5.1f} {b['parallel']:5.1f} {b['other']:5.1f} {b['top3']:5.1f}   n={b['n']}")
json.dump(out,open('results_rescored.json','w'),indent=1)
