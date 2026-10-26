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

P=dict(slideDecel=2040.0,slideTo=0.8,decel0=3.0,decelV=0.57,follow=0.15,keepAlong=0.8,keepInto=0.8/1.85,k=50.0,b=520.0,cueKeep=None)
def speedAt(p): return max(40,P['k']*p-P['b'])
def alongRail(x,y,ux,uy):
    c=math.cos(math.radians(12)); n=R+16
    if abs(uy)>=c and (x-x0<n or x1-x<n): return True
    if abs(ux)>=c and (y-y0<n or y1-y<n): return True
    return False
def rollDistance(v):
    if v<=0: return 0
    c,a,vr=P['decelV'],P['decel0'],P['slideTo']*v
    skid=(v*v-vr*vr)/(2*P['slideDecel'])
    return skid+vr/c-a/(c*c)*math.log(1+c*vr/a)
def speedFor(d):
    if d<=0: return 0
    lo,hi=0.0,30000.0
    for _ in range(40):
        m=(lo+hi)/2
        if rollDistance(m)<d: lo=m
        else: hi=m
    return hi
SIN12=math.sin(math.radians(12))
def run(X,Y,ux,uy,balls=(),skip=None,maxLen=3000,maxRails=2,gap=2*R,pad=0,speed=None,flat=1.0,keep=None):
    r=dict(pts=[X,Y],pocket=-1,ball=None,rails=0,jaws=0,rj=0,off=1.0)
    start=rollDistance(speed) if speed is not None else maxLen
    x,y=X,Y; left=start
    kA,kI=(keep or (P['keepAlong'],P['keepInto']))
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
        along=alongRail(x,y,ux,uy)
        x+=ux*best;y+=uy*best;left-=best;r['pts']+=[x,y]
        if kind==1: r['pocket']=which
        if kind==3: r['ball']=which
        if kind!=2: break
        vn=ux*nx+uy*ny; tx,ty=ux-vn*nx,uy-vn*ny
        if isJaw:
            if along and abs(y-midY)>300: r['rj']+=1
            else: r['jaws']+=1
        elif abs(vn)>=SIN12: r['rails']+=1
        if r['rails']>maxRails: break
        an=abs(vn); vt2=kA; vn2=an*kI/flat
        ux=tx*vt2+nx*vn2; uy=ty*vt2+ny*vn2; l=math.hypot(ux,uy); ux/=l; uy/=l
        if speed is not None and (isJaw or abs(vn)>=SIN12): left=rollDistance(l*speedFor(left))
        x+=nx*0.01;y+=ny*0.01
    r['left']=left; r['len']=start-left
    return r
def cueAfter(gx,gy,ix,iy,ox,oy,vHit,balls,skip,follow=None,keep=None):
    f=P['follow'] if follow is None else follow
    along=max(0,min(1,ix*ox+iy*oy)); sn=math.sqrt(1-along*along)
    side=ix*-oy+iy*ox>0
    tx,ty=(-oy,ox) if side else (oy,-ox)
    vx=tx*vHit*sn+ox*f*vHit*along; vy=ty*vHit*sn+oy*f*vHit*along
    sp=math.hypot(vx,vy)
    if sp<1: return dict(pts=[gx,gy],pocket=-1,ball=None,rails=0,jaws=0)
    return run(gx,gy,vx/sp,vy/sp,balls,skip=skip,maxRails=4,speed=sp,keep=keep)
def powerPaths(cx,cy,ax,ay,target,balls,dirdeg,power,keep=None,okeep=None):
    others=[b for b in balls if b[0]!=0]
    v0=speedAt(max(1,power))
    dx,dy=ax-cx,ay-cy; d1=math.hypot(dx,dy); dx/=max(d1,1e-6); dy/=max(d1,1e-6)
    if target is None:
        c=run(cx,cy,dx,dy,others,skip=0,maxRails=4,speed=v0,keep=keep); return None,c
    vHit=speedFor(max(0,rollDistance(v0)-d1))
    tid,bx,by=target
    ux,uy=bx-ax,by-ay; l=math.hypot(ux,uy); ux/=max(l,1e-6); uy/=max(l,1e-6)
    if dirdeg is not None: ux,uy=math.cos(math.radians(dirdeg)),math.sin(math.radians(dirdeg))
    along=max(0,min(1,dx*ux+dy*uy))
    o=run(bx,by,ux,uy,others,skip=tid,maxRails=4,speed=vHit*along,keep=okeep)
    c=cueAfter(ax,ay,dx,dy,ux,uy,vHit,others,tid,keep=keep)
    return o,c
