import sys,re,math; sys.path.insert(0,'.')
from ev import load,T
rows=load(sys.argv[1]); i=0
while i<len(rows):
    if not rows[i][1]: i+=1; continue
    j=i
    while j<len(rows) and rows[j][1]: j+=1
    # last P row with path and power before i
    pr=None
    for k in range(i-1,max(0,i-400),-1):
        ln=rows[k][3]
        if ' path=' in ln and ' turn=1' in ln and ' aim=' in ln:
            m=re.search(r' power=(\d+)',ln)
            if m and int(m[1])<15: continue
            pr=rows[k]; break
        if not rows[k][1] and ' turn=0' in rows[k][3]: break
    if pr:
        ln=pr[3]
        path=list(map(int,re.search(r' path=([\d,]+)',ln)[1].split(',')))
        a=re.search(r' aim=(\d+),(\d+)',ln); ax,ay=int(a[1]),int(a[2])
        bs=pr[2]
        tg=min((b for b in bs if b), key=lambda b: math.hypot(bs[b][0]-ax,bs[b][1]-ay))
        says=re.search(r'says=([^|]*)',ln)[1]; pw=re.search(r' power=(\d+)',ln); pw=pw[1] if pw else '-'
        tr=[r[2][tg] for r in rows[i-1:j+1] if tg in r[2]]
        gone=tg not in rows[min(j+5,len(rows)-1)][2]
        if len(path)>=6:
            print(f"{ln[:10]} ball {tg} p{pw} says {says} predicted {path}")
            # actual trajectory compressed
            pts=[tr[0]]
            for p in tr[1:]:
                if math.hypot(p[0]-pts[-1][0],p[1]-pts[-1][1])>25: pts.append(p)
            print('   actual',pts[:14],'gone' if gone else 'stayed', tr[-1])
    i=j
