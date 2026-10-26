# faithful port of PoolEngine.run (Swift) with the rail-roll change
import math
R=23.5; midX=587.0; midY=1359.5
def mx(x): return 2*midX-x
def my(y): return 2*midY-y
x0,x1,y0,y1=207.5,966.5,584.0,2135.0
segs=[]
segs.append((261,y0,mx(261),y0,False)); segs.append((261,y1,mx(261),y1,False))
for x in (x0,x1):
    segs.append((x,641,x,1319.5,False)); segs.append((x,1399.5,x,my(641),False))
for a,b in [((261.0,y0),(231.0,y0-30)),((x0,641.0),(x0-30,611.0))]:
    for fx in (False,True):
        for fy in (False,True):
            segs.append((mx(a[0]) if fx else a[0], my(a[1]) if fy else a[1], mx(b[0]) if fx else b[0], my(b[1]) if fy else b[1], True))
for fx in (False,True):
    for a,b in [((x0,1319.5),(190.0,1321.0)),((x0,1399.5),(190.0,1398.0))]:
        segs.append((mx(a[0]) if fx else a[0],a[1],mx(b[0]) if fx else b[0],b[1],True))
holes=[(195,570,40),(979,570,40),(170,1360,37),(1004,1360,37),(195,2149,40),(979,2149,40)]
def rayCircle(px,py,ux,uy,cx,cy,r):
    fx,fy=px-cx,py-cy; b=fx*ux+fy*uy; c=fx*fx+fy*fy-r*r
    if b>=0: return None
    if c<0: return 0
    d=b*b-c
    if d<0: return None
    t=-b-math.sqrt(d); return t if t>1e-6 else None
def rayCapsule(px,py,ux,uy,s,face,end):
    X1,Y1,X2,Y2,_=s; dx,dy=X2-X1,Y2-Y1; l=math.hypot(dx,dy); tx,ty=dx/l,dy/l; nx,ny=-ty,tx
    best=None
    for sg in (1,-1):
        den=ux*nx*sg+uy*ny*sg
        if den>=0: continue
        ox,oy=X1+nx*face*sg,Y1+ny*face*sg
        t=((ox-px)*nx*sg+(oy-py)*ny*sg)/den
        if t<=1e-6: continue
        hx,hy=px+ux*t,py+uy*t; a=(hx-X1)*tx+(hy-Y1)*ty
        if 0<=a<=l and (best is None or t<best[0]): best=(t,nx*sg,ny*sg)
    for ex,ey in ((X1,Y1),(X2,Y2)):
        t=rayCircle(px,py,ux,uy,ex,ey,end)
        if t is not None and t>1e-6 and (best is None or t<best[0]):
            hx,hy=px+ux*t,py+uy*t; best=(t,(hx-ex)/end,(hy-ey)/end)
    return best
RAILROLL=True
FL=[1.28]
def alongRail(x,y,ux,uy):
    c=math.cos(math.radians(12)); n=R+16
    if abs(uy)>=c and (x-x0<n or x1-x<n): return True
    if abs(ux)>=c and (y-y0<n or y1-y<n): return True
    return False
PH=dict(A=30.0,C=1.3,K=4150.0)
def rollDistance(v):
    c,a=PH['C'],PH['A']; return v/c - a/(c*c)*math.log(1+c*v/a) if v>0 else 0
def speedFor(d):
    if d<=0: return 0
    lo,hi=0.0,60000.0
    for _ in range(50):
        m=(lo+hi)/2
        if rollDistance(m)<d: lo=m
        else: hi=m
    return hi
def run(X,Y,ux,uy,balls=(),skip=None,maxLen=3000,maxRails=2,gap=2*R,pad=0,speed=None):
    r=dict(pts=[X,Y],pocket=-1,ball=None,rails=0,jaws=0,rj=0,off=1.0)
    start=rollDistance(speed) if speed is not None else maxLen
    x,y=X,Y; left=start
    for _ in range(10):
        best=left; kind=0; which=-1; nx=ny=0; isJaw=False
        for k,h in enumerate(holes):
            t=rayCircle(x,y,ux,uy,*h)
            if t is not None and t<best: best=t;kind=1;which=k
        for s in segs:
            c=rayCapsule(x,y,ux,uy,s,R+pad if s[4] else R,R+pad)
            if c and c[0]<best: best=c[0];kind=2;nx,ny=c[1],c[2];isJaw=s[4]
        for (bid,bx,by) in balls:
            if bid==skip: continue
            t=rayCircle(x,y,ux,uy,bx,by,gap)
            if t is not None and t>1e-6 and t<best: best=t;kind=3;which=bid
        along=RAILROLL and alongRail(x,y,ux,uy)
        x+=ux*best;y+=uy*best;left-=best;r['pts']+=[x,y]
        if kind==1:
            r['pocket']=which; h=holes[which]; perp=abs((h[0]-x)*uy-(h[1]-y)*ux)
            r['off']=0.85 if r['jaws']>0 else (0.5 if r['rj']>0 else min(1,perp/(16.5 if which in(2,3) else 20)))
        if kind==3: r['ball']=which
        if kind!=2: break
        vn=ux*nx+uy*ny
        if isJaw:
            if along and abs(y-midY)>300: r['rj']+=1
            else: r['jaws']+=1
        elif RAILROLL and abs(vn)<math.sin(math.radians(12)): pass
        else: r['rails']+=1
        if r['rails']>maxRails: break
        tx,ty=ux-vn*nx,uy-vn*ny
        tm=math.hypot(tx,ty); an=abs(vn)
        tin=tm/max(an,1e-6); th=math.atan(tin)
        tout=FL[0]*(1.14*tin+0.40*math.sin(2*th))
        vt2=0.85*tm; vn2=(vt2/tout) if tout>1e-4 else 0.5*an
        ux=(tx/tm if tm>1e-9 else 0)*vt2+nx*vn2; uy=(ty/tm if tm>1e-9 else 0)*vt2+ny*vn2; l=math.hypot(ux,uy); ux/=l;uy/=l
        if speed is not None and (isJaw or abs(vn)>=math.sin(math.radians(12))): left=rollDistance(l*speedFor(left))
        x+=nx*0.01;y+=ny*0.01
    r['left']=left
    return r

def powerPaths(cx,cy,ax,ay,target,balls,dirdeg,power):
    others=[b for b in balls if b[0]!=0]
    v0=max(1,power)/100*PH['K']
    dx,dy=ax-cx,ay-cy; d1=math.hypot(dx,dy); dx/=d1; dy/=d1
    if target is None:
        c=run(cx,cy,dx,dy,others,skip=0,maxRails=4,speed=v0); return c['pts'][-2:],c
    vHit=speedFor(max(0,rollDistance(v0)-d1))
    tid,bx,by=target
    if dirdeg is not None: ux,uy=math.cos(math.radians(dirdeg)),math.sin(math.radians(dirdeg))
    else:
        ux,uy=bx-ax,by-ay; l=math.hypot(ux,uy); ux/=l; uy/=l
    along=max(0,min(1,dx*ux+dy*uy))
    if along>0.995: return (ax,ay),None
    side=dx*-uy+dy*ux>0
    tx,ty=(-uy,ux) if side else (uy,-ux)
    c=run(ax,ay,tx,ty,others,skip=tid,maxRails=4,speed=vHit*math.sqrt(1-along*along))
    return c['pts'][-2:],c
