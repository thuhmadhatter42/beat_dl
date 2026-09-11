"""Raw-score study: essentia HPCP(36)+bgate correlations + CNN probs per track -> combos & confidence calibration."""
import json, numpy as np, sys
sys.argv=[sys.argv[0]]
from bench import essentia_hpcp_frames, hpcp_to_scores, _cnn, parse_key, mirex, fmt
from rescore import GSP
gt=json.load(open('ground_truth.json'))
out={}
for n in sorted(gt):
    p=f'audio/{n}.mp3'
    H=essentia_hpcp_frames(p,36); sc=hpcp_to_scores(H.mean(axis=0),'bgate',36)
    ranked=sorted(sc.items(),key=lambda kv:-kv[1]); r=[v for _,v in ranked]
    # segment agreement: fraction of 10 s windows whose winner == global winner
    fr=int(10*44100/4096); wins=[]
    for i in range(0,len(H)-fr+1,fr):
        s2=hpcp_to_scores(H[i:i+fr].mean(axis=0),'bgate',36); wins.append(max(s2,key=s2.get))
    agree=np.mean([w==ranked[0][0] for w in wins])
    cnn=_cnn(p)
    out[n]=dict(ess=fmt(*ranked[0][0]), ess2=fmt(*ranked[1][0]), ess3=fmt(*ranked[2][0]), r1=r[0], r2=r[1], r3=r[2],
                margin=(r[0]-r[1])/max(r[0],1e-6), agree=float(agree), cnn=fmt(*cnn[0][0]), cnn_p=cnn[0][1]/100, cnn2=fmt(*cnn[1][0]))
json.dump(out,open('combo_raw.json','w'),indent=1)
