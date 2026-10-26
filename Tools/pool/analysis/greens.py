import sys,re,math; sys.path.insert(0,'.')
import stops
from rolls import load
for f in sys.argv[1:]:
    S=stops.shots([f]); rows=load(f)
    for s in S:
        if not s['tgt']: continue
        t0=stops.T(s['t']+' ')
        # verdict in the aim row/pull rows: find says around
        says=[r[3] for r in rows if t0-0.05<=r[0]<=t0+6 and ' power=' in r[3]]
        green=any('says=✓' in l for l in says[-3:]) if says else False
        risky=any('เสี่ยง' in l for l in says[-3:]) if says else False
        ms=[k for k,r in enumerate(rows) if r[0]>t0 and r[1]]
        post=[]
        if ms:
            k=ms[0]
            while k<len(rows) and rows[k][1]: k+=1
            post=rows[k:k+1]
        tid=s['tgt'][0]
        potted = bool(post) and tid not in post[0][2]
        print(s['t'],'pow',s['pow'],'ball',tid,'green' if green else ('risky' if risky else 'other'),'-> POTTED' if potted else '-> missed')
