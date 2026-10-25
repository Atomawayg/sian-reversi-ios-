import sys, glob, math, numpy as np
from PIL import Image
sys.path.insert(0,'.'); import poolnp as P
R=P.R
def W(img):
    h,s,v=P.hsv(img); return (s<0.22)&(v>0.85)
def cue_of(img, bs):
    best=None;bw=0
    for x,y in bs:
        yy,xx=np.mgrid[int(y-R+3):int(y+R-2),int(x-R+3):int(x+R-2)]
        ins=(xx-x)**2+(yy-y)**2<=(R-3)**2
        w=W(img[yy[ins],xx[ins]]).mean()
        if w>bw: bw=w;best=(x,y)
    return best if bw>0.8 else None
def line_support(Wfull, cue, c):
    dx,dy=c[0]-cue[0],c[1]-cue[1]; L=math.hypot(dx,dy)
    if L<3*R: return 0
    ux,uy=dx/L,dy/L; nx,ny=-uy,ux
    hit=n=0
    t=R+6
    while t<L-R-6:
        n+=1
        px,py=cue[0]+ux*t,cue[1]+uy*t
        if any(Wfull[int(round(py+ny*o)),int(round(px+nx*o))] for o in (-2,-1,0,1,2)): hit+=1
        t+=6
    return hit/n if n else 0
def new_aim(img, bs, cue):
    g=2
    xs=np.arange(P.X0,P.X1+0.01,g).round().astype(int); ys=np.arange(P.Y0,P.Y1+0.01,g).round().astype(int)
    Wg=W(img[ys][:,xs]); ny,nx=Wg.shape
    ring=[(int(round((R-1.5)*math.cos(a)/g)),int(round((R-1.5)*math.sin(a)/g))) for a in np.arange(40)*math.pi/20]
    core=[(di,dj) for dj in range(-8,9,2) for di in range(-8,9,2) if di*di+dj*dj<=64]
    m=int(R/g)+2
    rc=np.zeros((ny,nx));cc=np.zeros((ny,nx))
    for di,dj in ring: rc[m:ny-m,m:nx-m]+=Wg[m+dj:ny-m+dj,m+di:nx-m+di]
    for di,dj in core: cc[m:ny-m,m:nx-m]+=Wg[m+dj:ny-m+dj,m+di:nx-m+di]
    scr=np.where(rc>=16,rc/len(ring)-cc/len(core),0)
    J,I=np.nonzero(scr>0.32)
    cands=sorted(zip(scr[J,I],I,J),reverse=True)
    Wf=W(img)
    out=[];best=None;bs_=-1
    for s,i,j in cands:
        x,y=P.X0+i*g,P.Y0+j*g
        if any(math.hypot(x-bx,y-by)<R+8 for bx,by in bs): continue
        if any(math.hypot(x-o[0],y-o[1])<20 for o in out): continue
        out.append((x,y))
        ls=line_support(Wf,cue,(x,y)) if cue else 0
        tot=s+ls
        if tot>bs_: bs_=tot;best=(x,y,s,ls)
        if len(out)>=8: break
    return best
for f in sorted(glob.glob('aimfr/*.png')):
    img=np.asarray(Image.open(f).convert('RGB'))
    if img.shape[1]!=1180: continue
    if not P.looks_like_pool(img)[0]: continue
    bs=P.balls(img); cue=cue_of(img,bs)
    o=P.aim_circle(img); n=new_aim(img,bs,cue)
    onb=lambda p: p and min((math.hypot(p[0]-x,p[1]-y) for x,y in bs),default=999)
    print(f.split('/')[-1], 'cue',cue and (int(cue[0]),int(cue[1])),'old',o and (int(o[0]),int(o[1])), 'd%.0f'%(onb(o) or -1), 'new', n and (int(n[0]),int(n[1]),round(n[2],2),round(n[3],2)), 'd%.0f'%(onb(n) or -1))
