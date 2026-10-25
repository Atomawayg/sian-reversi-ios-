import re,math,sys
src=open('shots3.py').read().split('i=0\nwhile')[0]
exec(src)
def d(a,b): return math.hypot(a[0]-b[0],a[1]-b[1])
i=1;seen=set()
while i<len(rows):
    q,r=rows[i-1],rows[i]
    if 0 in q['bs'] and 0 in r['bs'] and d(q['bs'][0],r['bs'][0])>15:
        k=i-1
        while k>=0 and not rows[k]['aim'] and r['t']-rows[k]['t']<3: k-=1
        if k>=0 and rows[k]['aim'] and r['t']-rows[k]['t']<3 and k not in seen:
            seen.add(k)
            A=rows[k]; a=A['aim']; bs=A['bs']
            tgt=min((x for x in bs if x),key=lambda x:d(bs[x],a))
            if d(bs[tgt],a)<2*23.5+12:
                traj=[];gone=False
                for r2 in rows[i:i+300]:
                    if r2['t']-r['t']>6: break
                    if tgt in r2['bs']: traj.append(r2['bs'][tgt])
                    else: gone=True;break
                end=traj[-1] if traj else bs[tgt]
                res=('POT '+N[min(range(6),key=lambda x:d(P[x],end))]) if gone else 'stay'
                says=A['raw'].split('says=')[1].split('|')
                print(f"{A['raw'].split()[0]} t{tgt}@{bs[tgt]} aim={a} dir={A['dir']} says={says[0]} / {says[1][:25]} pathEnd={A['path'][-2:] if A['path'] else None} -> {res} end={end}")
    i+=1
