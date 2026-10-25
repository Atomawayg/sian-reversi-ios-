import re,math,sys
L=open(sys.argv[1]).read().splitlines()
P=[(195,570),(979,570),(170,1360),(1004,1360),(195,2149),(979,2149)]
N=['TL','TR','ML','MR','BL','BR']
def tsec(t):h,m,s=t.split(':');return int(h)*3600+int(m)*60+float(s)
rows=[]
for l in L:
    m=re.search(r'balls=(.*?)(?= [a-z]+=)',l)
    if not m: continue
    bs={int(k):(int(x),int(y)) for k,x,y in re.findall(r'(\d+):(\d+),(\d+)',m.group(1))}
    g=lambda k: re.search(k+r'=([^ ]+)',l)
    rows.append(dict(t=tsec(l.split()[0]),bs=bs,aim=g('aim') and tuple(map(int,g('aim').group(1).split(','))),dir=g('dir') and float(g('dir').group(1)),power=g('power') and int(g('power').group(1)),path=g('path') and list(map(int,g('path').group(1).split(','))),says=re.search(r'says=([^|]*)',l).group(1) if 'says=' in l else '',turn=g('turn').group(1),raw=l))
i=0
while i<len(rows):
    r=rows[i]
    # a shot: power was pulled, then the cue ball moves
    if r['power'] and i+1<len(rows):
        j=i
        while j+1<len(rows) and rows[j+1]['power'] is not None: j+=1
        # last aimed row
        k=j
        while k>=0 and not rows[k]['aim']: k-=1
        A=rows[k]; c0=A['bs'].get(0)
        # find movement
        m=j+1
        while m<len(rows) and m<j+6 and rows[m]['bs'].get(0)==c0: m+=1
        if m<len(rows) and rows[m]['bs'].get(0)!=c0 and c0:
            a=A['aim']; bs=A['bs']
            tgt=min((q for q in bs if q),key=lambda q:math.hypot(bs[q][0]-a[0],bs[q][1]-a[1]))
            traj=[]; gone=False
            for r2 in rows[m:m+150]:
                if tgt in r2['bs']: traj.append(r2['bs'][tgt])
                else: gone=True;break
            mv=[p for p in traj if math.hypot(p[0]-bs[tgt][0],p[1]-bs[tgt][1])>60]
            ad=None
            if len(mv)>=1:
                p=mv[min(2,len(mv)-1)]; ad=round(math.degrees(math.atan2(p[1]-bs[tgt][1],p[0]-bs[tgt][0]))%360,1)
            dist=round(math.hypot(a[0]-bs[tgt][0],a[1]-bs[tgt][1]))
            end=traj[-1] if traj else None
            res=('POT '+N[min(range(6),key=lambda q:math.hypot(P[q][0]-end[0],P[q][1]-end[1]))]) if gone and end else 'stay'
            print(f"{A['raw'].split()[0]} tgt={tgt}@{bs[tgt]} aimd={dist} dir={A['dir']} act={ad} power={rows[j]['power']} says={A['says']} path_end={A['path'][-2:] if A['path'] else None} -> {res} last={end} n={len(traj)}")
        i=j+1; continue
    i+=1
