import math, sim as S
PAD=[0]
def ray_capsule(px,py,ux,uy,s):
    x1,y1,x2,y2,kind=s
    face=S.R+(PAD[0] if kind==1 else 0); end=S.R+PAD[0]
    best=None;nrm=None
    dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); tx,ty=dx/L,dy/L; nx,ny=-ty,tx
    for sgn in (1,-1):
        den=ux*nx*sgn+uy*ny*sgn
        if den>=0: continue
        ox,oy=x1+nx*face*sgn,y1+ny*face*sgn
        t=((ox-px)*nx*sgn+(oy-py)*ny*sgn)/den
        if t<=1e-6: continue
        hx,hy=px+ux*t,py+uy*t; a=(hx-x1)*tx+(hy-y1)*ty
        if 0<=a<=L and (best is None or t<best): best=t; nrm=(nx*sgn,ny*sgn)
    for ex,ey in ((x1,y1),(x2,y2)):
        fx,fy=px-ex,py-ey; b=fx*ux+fy*uy; c=fx*fx+fy*fy-end*end
        if c<=0 or b>=0: continue
        d=b*b-c
        if d<0: continue
        t=-b-math.sqrt(d)
        if t>1e-6 and (best is None or t<best):
            hx,hy=px+ux*t,py+uy*t; best=t; nrm=((hx-ex)/end,(hy-ey)/end)
    return best,nrm
S.ray_capsule=ray_capsule
