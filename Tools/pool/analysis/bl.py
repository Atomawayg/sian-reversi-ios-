import sys,math,re; sys.path.insert(0,'.')
from ev import load
R=23.5; X0,X1,Y0,Y1=207.5+R,966.5-R,584+R,2135-R
out=[]
for f in sys.argv[1:]:
    rows=load(f); i=0
    while i<len(rows):
        if not rows[i][1]: i+=1; continue
        j=i
        while j<len(rows) and rows[j][1]: j+=1
        blk=rows[max(0,i-1):j+1]
        ids=set().union(*[set(r[2]) for r in blk])
        for b in ids:
            tr=[(r[0],)+r[2][b] for r in blk if b in r[2]]
            # dedupe consecutive same positions
            pts=[tr[0]] if tr else []
            for p in tr[1:]:
                if (p[1],p[2])!=(pts[-1][1],pts[-1][2]): pts.append(p)
            if len(pts)<7: continue
            for k in range(2,len(pts)-2):
                x,y=pts[k][1],pts[k][2]
                wall=None
                if x<X0+6: wall=('x',X0)
                elif x>X1-6: wall=('x',X1)
                elif y<Y0+6: wall=('y',Y0)
                elif y>Y1-6: wall=('y',Y1)
                if not wall: continue
                # near a pocket? skip
                if wall[0]=='x' and (abs(y-1359.5)<90 or y<584+90 or y>2135-90): continue
                if wall[0]=='y' and (x<207.5+90 or x>966.5-90): continue
                bef=[p for p in pts[max(0,k-4):k]]; aft=[p for p in pts[k+1:k+5]]
                if len(bef)<2 or len(aft)<2: continue
                def dirv(seq):
                    dx=seq[-1][1]-seq[0][1]; dy=seq[-1][2]-seq[0][2]; l=math.hypot(dx,dy); return dx/max(l,1e-6),dy/max(l,1e-6),l,(seq[-1][0]-seq[0][0])
                ib=dirv(bef+[pts[k]]); ia=dirv([pts[k]]+aft)
                if ib[2]<50 or ia[2]<50: continue
                if wall[0]=='x': nin,tin=abs(ib[0]),abs(ib[1]); nout,tout=abs(ia[0]),abs(ia[1])
                else: nin,tin=abs(ib[1]),abs(ib[0]); nout,tout=abs(ia[1]),abs(ia[0])
                # direction along rail must keep sign
                ain=math.degrees(math.atan2(tin,nin)); aout=math.degrees(math.atan2(tout,nout))
                if ain<8 or ain>75: continue
                vin=ib[2]/max(ib[3],1e-3); vout=ia[2]/max(ia[3],1e-3)
                # distance travelled since motion start
                d0=sum(math.hypot(pts[q+1][1]-pts[q][1],pts[q+1][2]-pts[q][2]) for q in range(k))
                out.append((b,ain,aout,math.tan(math.radians(aout))/math.tan(math.radians(ain)),vin,vout,d0,f[-20:],pts[k][0]))
                break
        i=j
import statistics as st
ob=[o for o in out if o[0]!=0]; cb=[o for o in out if o[0]==0]
for name,L in (('obj',ob),('cue',cb)):
    rs=sorted(o[3] for o in L)
    if rs: print(name,len(L),'ratio median %.2f q25 %.2f q75 %.2f'%(rs[len(rs)//2],rs[len(rs)//4],rs[3*len(rs)//4]))
for o in sorted(ob,key=lambda o:o[4]): print('%2d in %4.1f out %4.1f r %.2f vin %5.0f vout %5.0f d0 %5.0f'%o[:7])
import numpy as np
D=[o for o in ob if 0.85<o[3]<3.2]
ti=np.array([math.tan(math.radians(o[1])) for o in D]); ao=np.array([o[2] for o in D])
def err(pred): return np.degrees(np.arctan(pred))-ao
for k in [1.3,1.4,1.5,1.6,1.7,1.85]:
    e=err(k*ti); print('ratio',k,'median abs %.1f rms %.1f bias %.1f'%(np.median(abs(e)),np.sqrt((e**2).mean()),np.median(e)))
A=np.vstack([ti,np.ones_like(ti)]).T
to=np.tan(np.radians(ao)); a,b=np.linalg.lstsq(A,to,rcond=None)[0]; e=err(a*ti+b)
print('lin a %.2f b %.2f median abs %.1f rms %.1f'%(a,b,np.median(abs(e)),np.sqrt((e**2).mean())))
# by in-angle bins
for lo,hi in [(8,25),(25,40),(40,55),(55,75)]:
    s=[o[3] for o in D if lo<=o[1]<hi]; print(lo,hi,len(s),'median r %.2f'%(np.median(s) if s else 0))
