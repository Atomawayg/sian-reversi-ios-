import sys,re,math,pickle; sys.path.insert(0,__import__('os').path.dirname(__file__))
def T(s): h,m,x=s[:10].split(':'); return int(h)*3600+int(m)*60+float(x)
def load(f):
    rows=[]
    for ln in open(f,errors='ignore'):
        m=re.search(r'balls=([\d:, ]+)',ln)
        if not m or len(ln)<12: continue
        try: t=T(ln)
        except: continue
        rows.append((t,ln.split()[1]=='M',{int(a):(int(b),int(c)) for a,b,c in re.findall(r'(\d+):(\d+),(\d+)',m[1])},ln))
    return rows
def rest_after(rows,j):
    # from row j: first time all balls hold within 3 px for 0.7 s
    k=j
    while k<len(rows):
        t0,_,b0,_=rows[k]; ok=True; m=k+1
        while m<len(rows) and rows[m][0]-t0<0.7:
            b=rows[m][2]
            if set(b)!=set(b0) or any(abs(b[i][0]-b0[i][0])>3 or abs(b[i][1]-b0[i][1])>3 for i in b): ok=False; break
            m+=1
        if ok and m<len(rows) and rows[m][0]-t0>=0.7: return b0,t0
        k+=1
    return None,None
def shots(f):
    rows=load(f); out=[]; i=0
    while i<len(rows):
        if not rows[i][1]: i+=1; continue
        j=i
        while j<len(rows) and rows[j][1]: j+=1
        pser=[]; aimrow=None; seen=False
        for k in range(i-1,-1,-1):
            if rows[i][0]-rows[k][0]>6: break
            ln=rows[k][3]
            m=re.search(r' power=(\d+)',ln)
            if m: pser.append(int(m[1])); seen=True; continue
            if seen and ' aim=' in ln and ' turn=1' in ln: aimrow=rows[k]; break
        pser=pser[::-1]; q=len(pser)-1
        while q>0 and pser[q]<=8: q-=1
        while q>0 and pser[q-1]-pser[q]>=2: q-=1
        pk=pser[q] if pser else 0
        rest,tr=rest_after(rows,i)
        i=j
        if not aimrow or pk<5 or rest is None: continue
        bs=aimrow[2]
        if 0 not in bs: continue
        a=re.search(r' aim=(\d+),(\d+)',aimrow[3]); ax,ay=int(a[1]),int(a[2])
        d=re.search(r' dir=([\d.]+)',aimrow[3]); dd=float(d[1]) if d else None
        sp=re.search(r' spin=(-?[\d.]+),(-?[\d.]+)',aimrow[3])
        tg=[(b,x,y) for b,(x,y) in bs.items() if b and math.hypot(x-ax,y-ay)<2*23.5+8]
        tg=min(tg,key=lambda t:math.hypot(t[1]-ax,t[2]-ay)) if tg else None
        # first M rows: how the balls actually moved (track to detect collisions with third balls)
        mv=[r[2] for r in rows[i-0:i]]
        out.append(dict(f=f,t=aimrow[3][:10],cue=bs[0],aim=(ax,ay),dir=dd,pow=pk,tgt=tg,balls=[(b,x,y) for b,(x,y) in bs.items()],rest=rest,spin=(float(sp[1]),float(sp[2])) if sp else None,
            moved=sorted(b for b in bs if b in rest and (abs(rest[b][0]-bs[b][0])>4 or abs(rest[b][1]-bs[b][1])>4)), gone=sorted(b for b in bs if b not in rest)))
    return out
if __name__=='__main__':
    import glob
    S=[]
    for f in sys.argv[1:]: S+=shots(f)
    pickle.dump(S,open('evshots.pkl','wb'))
    print(len(S))
    for s in S[-10:]: print(s['t'],s['pow'],s['tgt'],s['moved'],s['gone'],s['spin'])
