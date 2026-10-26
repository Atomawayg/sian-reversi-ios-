import pickle,math,sys,numpy as np
xMin,xMax,yMin,yMax=231,943,607.5,2111.5
holes=[(195,570),(979,570),(170,1360),(1004,1360),(195,2149),(979,2149)]
def real(b):
    x,y,r,g,bb,w=b
    if r<70 and 120<bb<190 and 85<g<140: return False
    return xMin-8<=x<=xMax+8 and yMin-8<=y<=yMax+8
res=[]
for fn in sys.argv[1:]:
    out=pickle.load(open(fn,'rb'))
    frames=[(t,[b for b in bs if real(b)]) for t,bs in out if t is not None]
    # drop duplicated frames (same detections as previous)
    fr=[]; prev=None
    for t,bs in frames:
        key=tuple(sorted((round(b[0]),round(b[1])) for b in bs))
        if key==prev: continue
        prev=key; fr.append((t,bs))
    # link tracks
    tracks=[]; active=[]
    for t,bs in fr:
        used=set(); newactive=[]
        for tr in active:
            lt,lx,ly,lc=tr[-1]
            if t-lt>0.12: continue
            # predict
            if len(tr)>=2:
                pt,px,py,_=tr[-2]; dt=lt-pt
                vx,vy=((lx-px)/dt,(ly-py)/dt) if dt>0 else (0,0)
            else: vx=vy=0
            ex,ey=lx+vx*(t-lt),ly+vy*(t-lt)
            best=None
            for i,b in enumerate(bs):
                if i in used: continue
                d=math.hypot(b[0]-ex,b[1]-ey)+0.3*sum(abs(b[2+k]-lc[k]) for k in range(3))/3
                if d<70 and (best is None or d<best[0]): best=(d,i)
            if best:
                used.add(best[1]); b=bs[best[1]]; tr.append((t,b[0],b[1],b[2:5])); newactive.append(tr)
        for i,b in enumerate(bs):
            if i not in used:
                tr=[(t,b[0],b[1],b[2:5])]; tracks.append(tr); newactive.append(tr)
        active=newactive
    for tr in tracks:
        if len(tr)<12: continue
        T=np.array([p[0] for p in tr]); X=np.array([p[1] for p in tr]); Y=np.array([p[2] for p in tr])
        for k in range(4,len(tr)-4):
            x,y=X[k],Y[k]
            for side,val,coord in (('L',xMin,0),('R',xMax,0),('T',yMin,1),('B',yMax,1)):
                c=x if coord==0 else y
                if abs(c-val)>6: continue
                # local extreme of the normal coordinate
                C=X if coord==0 else Y
                if not ((side in 'LT' and C[k]<=C[k-1] and C[k]<=C[k+1]) or (side in 'RB' and C[k]>=C[k-1] and C[k]>=C[k+1])): continue
                if min(math.hypot(x-hx,y-hy) for hx,hy in holes)<110: continue
                # fit straight lines before/after (0.03..0.2 s away from contact)
                bi=[i for i in range(len(tr)) if 0.02<T[k]-T[i]<0.22]; ai=[i for i in range(len(tr)) if 0.02<T[i]-T[k]<0.22]
                if len(bi)<4 or len(ai)<4: continue
                vb=np.polyfit(T[bi],X[bi],1)[0],np.polyfit(T[bi],Y[bi],1)[0]
                va=np.polyfit(T[ai],X[ai],1)[0],np.polyfit(T[ai],Y[ai],1)[0]
                # straightness check
                n1=abs(vb[coord]); t1=abs(vb[1-coord]); n2=abs(va[coord]); t2=abs(va[1-coord])
                sb=math.hypot(*vb); sa=math.hypot(*va)
                if sb<150 or n1<40 or n2<10: continue
                if np.sign(vb[coord])==np.sign(va[coord]): continue
                col=np.mean([p[3] for p in tr[max(0,k-5):k+5]],0); white=bool(col.min()>170 and col.max()-col.min()<45)
                res.append(dict(f=fn,white=white,t=round(T[k],2),side=side,vin=round(sb),vout=round(sa),ain=round(math.degrees(math.atan2(t1,n1)),1),aout=round(math.degrees(math.atan2(t2,n2)),1),kn=round(n2/n1,3),kt=round(t2/max(t1,1e-6),3) if t1>30 else None))
seen=set()
for r in res:
    key=(r['f'],round(r['t'],1))
    if key in seen: continue
    seen.add(key); print(r)
pickle.dump(res,open('bounces.pkl','wb'))
