import math
R=23.5; MX=587.0; MY=1359.5
def mx(x): return 2*MX-x
def my(y): return 2*MY-y
X0,X1,Y0,Y1=207.5,966.5,584.0,2135.0
segs=[]  # (x1,y1,x2,y2,kind) kind 0 rail 1 jaw
def add(a,b,k): segs.append((a[0],a[1],b[0],b[1],k))
# rails
add((270,Y0),(mx(270),Y0),0); add((270,Y1),(mx(270),Y1),0)
for x in (X0,X1):
    add((x,650),(x,1319.5),0); add((x,1399.5),(x,my(650)),0)
# corner jaws (TL then mirrored)
tl=[((270,Y0),(240,Y0-30)),((X0,650),(X0-30,620))]
for a,b in tl:
    for fx in (False,True):
        for fy in (False,True):
            A=(mx(a[0]) if fx else a[0], my(a[1]) if fy else a[1]); B=(mx(b[0]) if fx else b[0], my(b[1]) if fy else b[1])
            add(A,B,1)
# side jaws
for fx in (False,True):
    for (a,b) in [((X0,1319.5),(190,1321)),((X0,1399.5),(190,1398))]:
        A=(mx(a[0]) if fx else a[0],a[1]); B=(mx(b[0]) if fx else b[0],b[1]); add(A,B,1)
HOLES=[(195,570,40),(mx(195),570,40),(170,1360,37),(mx(170),1360,37),(195,my(570),40),(mx(195),my(570),40)]
# pocket index order as app: TL,TR,ML,MR,BL,BR
ORDER=[0,1,2,3,4,5]
FLAT=1.28
def ray_circle(px,py,ux,uy,cx,cy,r):
    fx,fy=px-cx,py-cy; b=fx*ux+fy*uy; c=fx*fx+fy*fy-r*r
    if c<0: return 0.0  # inside already
    d=b*b-c
    if d<0: return None
    t=-b-math.sqrt(d)
    return t if t>1e-6 else None
def ray_capsule(px,py,ux,uy,s):
    x1,y1,x2,y2,_=s
    best=None;nrm=None
    dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); tx,ty=dx/L,dy/L; nx,ny=-ty,tx
    for sgn in (1,-1):
        ox,oy=x1+nx*R*sgn,y1+ny*R*sgn
        den=ux*nx+uy*ny
        if abs(den)<1e-9: continue
        t=((ox-px)*nx+(oy-py)*ny)/den
        if t<=1e-6: continue
        # moving towards the segment from this side
        if (den*sgn)>=0: continue
        hx,hy=px+ux*t,py+uy*t
        a=(hx-x1)*tx+(hy-y1)*ty
        if 0<=a<=L and (best is None or t<best): best=t; nrm=(nx*sgn,ny*sgn)
    for ex,ey in ((x1,y1),(x2,y2)):
        fx,fy=px-ex,py-ey; b=fx*ux+fy*uy; c=fx*fx+fy*fy-R*R
        if c<=0 or b>=0: continue
        d=b*b-c
        if d<0: continue
        t=-b-math.sqrt(d)
        if t>1e-6 and (best is None or t<best):
            hx,hy=px+ux*t,py+uy*t; best=t; nrm=((hx-ex)/R,(hy-ey)/R)
    return best,nrm
def sim(px,py,ux,uy,balls=(),skip=None,maxlen=3000,maxhits=5):
    pts=[px,py]; rails=0; jaws=0; left=maxlen
    for _ in range(maxhits+1):
        best=left; ev=('end',None)
        for k,(cx,cy,r) in enumerate(HOLES):
            t=ray_circle(px,py,ux,uy,cx,cy,r)
            if t is not None and t<best: best=t; ev=('pocket',k)
        for s in segs:
            t,n=ray_capsule(px,py,ux,uy,s)
            if t is not None and t<best: best=t; ev=('wall',(s,n))
        for b in balls:
            if b[0]==skip: continue
            t=ray_circle(px,py,ux,uy,b[1],b[2],2*R)
            if t is not None and t>1e-6 and t<best: best=t; ev=('ball',b[0])
        px+=ux*best; py+=uy*best; left-=best; pts+=[px,py]
        if ev[0]!='wall': return dict(pts=pts,pocket=ev[1] if ev[0]=='pocket' else -1,ball=ev[1] if ev[0]=='ball' else None,rails=rails,jaws=jaws,len=maxlen-left)
        s,n=ev[1]
        if s[4]==0: rails+=1
        else: jaws+=1
        vn=ux*n[0]+uy*n[1]; tx,ty=ux-vn*n[0],uy-vn*n[1]
        ux,uy=tx*FLAT-vn*n[0],ty*FLAT-vn*n[1]; l=math.hypot(ux,uy); ux/=l;uy/=l
        px+=n[0]*0.01; py+=n[1]*0.01
    return dict(pts=pts,pocket=-1,ball=None,rails=rails,jaws=jaws,len=maxlen-left)
NAMES=['TL','TR','ML','MR','BL','BR']
if __name__=='__main__':
    for (x,y,d) in [(441,1587,339.1),(848,1428,331.1),(574,1184,304.0),(442,1587,334)]:
        r=sim(x,y,math.cos(math.radians(d)),math.sin(math.radians(d)))
        print(x,y,d,NAMES[r['pocket']] if r['pocket']>=0 else 'none',r['rails'],r['jaws'],[round(v) for v in r['pts']])
