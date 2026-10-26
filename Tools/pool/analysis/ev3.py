import sys,math,pickle; sys.path.insert(0,'.')
import eng5 as E, ev2
C=[]; seen=set()
for s in ev2.C:
    k=(s['f'],s['t'])
    if k in seen: continue
    seen.add(k); C.append(s)
print(len(C))
def score(**kw):
    E.P.update(kw); es=[]
    for s in C:
        o,c=ev2.pred(s); cs=c['pts'][-2:]; r=s['rest'][0]
        es.append(math.hypot(cs[0]-r[0],cs[1]-r[1]))
    es.sort(); return es[len(es)//2], sum(es)/len(es)
base=dict(E.P)
for fol in [0.15,0.25,0.35,0.5]:
    for dv in [0.57,0.45,0.35]:
        E.P.update(base)
        print(fol,dv,score(follow=fol,decelV=dv))
