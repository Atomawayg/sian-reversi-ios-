import sys,re,math; sys.path.insert(0,__import__('os').path.dirname(__file__))
import eng4 as E
def T(s): h,m,x=s[:10].split(':'); return int(h)*3600+int(m)*60+float(x)
def shots(files):
    out=[]
    for f in files:
        rows=[]
        for ln in open(f):
            m=re.search(r'balls=([\d:, ]+)',ln)
            if not m: continue
            rows.append((T(ln),ln.split()[1]=='M',{int(a):(int(b),int(c)) for a,b,c in re.findall(r'(\d+):(\d+),(\d+)',m[1])},ln))
        i=0
        while i<len(rows):
            if not rows[i][1]: i+=1; continue
            j=i
            while j<len(rows) and rows[j][1]: j+=1
            if j>=len(rows): break
            # pre: last P rows within 4 s before i with aim
            pk=0; aimrow=None; spin=(0,0); seenpow=False; pser=[]
            for k in range(i-1,-1,-1):
                if rows[i][0]-rows[k][0]>5: break
                ln=rows[k][3]
                m=re.search(r' power=(\d+)',ln)
                if m: pser.append(int(m[1]))
                if ' power=' in ln: aimrow=None; seenpow=True
                elif aimrow is None and ' aim=' in ln and seenpow: aimrow=rows[k]; break
                s=re.search(r' spin=(-?[\d.]+),(-?[\d.]+)',ln)
                if s and k==i-1: spin=(float(s[1]),float(s[2]))
            ms=re.search(r' spin=(-?[\d.]+),(-?[\d.]+)',rows[i][3])
            if ms: spin=(float(ms[1]),float(ms[2]))
            # release power: walking back from the shot, skip the bar sliding back (fast drops), take the value it left from
            pser=pser[::-1]   # oldest first
            q=len(pser)-1
            while q>0 and pser[q]<=8: q-=1
            while q>0 and pser[q-1]-pser[q]>=2: q-=1
            pk=pser[q] if pser else 0
            post=rows[j]; i=j
            if not aimrow or pk<5: continue
            bs=aimrow[2]
            if 0 not in bs or 0 not in post[2]: continue
            a=re.search(r' aim=(\d+),(\d+)',aimrow[3]); ax,ay=int(a[1]),int(a[2])
            d=re.search(r' dir=([\d.]+)',aimrow[3]); dd=float(d[1]) if d else None
            tg=[(b,x,y) for b,(x,y) in bs.items() if b and math.hypot(x-ax,y-ay)<2*23.5+8]
            tg=min(tg,key=lambda t:math.hypot(t[1]-ax,t[2]-ay)) if tg else None
            # cue moved at all? (post cue position differs)
            out.append(dict(t=aimrow[3][:10],cue=bs[0],aim=(ax,ay),dir=dd,pow=pk,spin=spin,tgt=tg,balls=[(b,x,y) for b,(x,y) in bs.items()],rest=post[2][0]))
    return out
if __name__=='__main__':
    S=shots(sys.argv[1:])
    for s in S:
        p,_=E.powerPaths(*s['cue'],*s['aim'],s['tgt'],s['balls'],s['dir'],s['pow'])
        err=math.dist(p,s['rest'])
        print(s['t'],'pow',s['pow'],'spin',s['spin'],'tgt',s['tgt'][0] if s['tgt'] else None,'pred',tuple(round(v) for v in p),'real',s['rest'],'err',round(err))
