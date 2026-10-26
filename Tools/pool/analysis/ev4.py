import sys,math,pickle; sys.path.insert(0,'.')
import eng5 as E, ev2, ev3
C=ev3.C
for fol in [0.15,0.2,0.22,0.25,0.28,0.3]:
    E.P.update(follow=fol, decelV=0.57)
    es=[]
    for s in C:
        o,c=ev2.pred(s); cs=c['pts'][-2:]; r=s['rest'][0]; es.append(math.hypot(cs[0]-r[0],cs[1]-r[1]))
    es.sort(); n=len(es)
    print(fol, 'q25 %.0f med %.0f q75 %.0f  <80: %d/%d'%(es[n//4],es[n//2],es[3*n//4],sum(e<80 for e in es),n))
