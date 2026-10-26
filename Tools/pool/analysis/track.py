import numpy as np, subprocess, sys, pickle
from scipy import ndimage as ndi
W,H=442,958
sx,sy=1180/W,2556/H
# play area (cushion noses) in video px, ball centre limits
X0,X1,Y0,Y1=207.5/sx,966.5/sx,584/sy,2135/sy
R=23.5/sx
p=subprocess.Popen(['ffmpeg','-v','error','-i',sys.argv[3],'-vsync','passthrough','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
ts=[float(l) for l in open(sys.argv[1])]
out=[]
i0,i1,j0,j1=int(X0)-2,int(X1)+3,int(Y0)-2,int(Y1)+3
yy,xx=np.mgrid[j0:j1,i0:i1]
felt=None
k=0
while True:
    buf=p.stdout.read(W*H*3)
    if len(buf)<W*H*3: break
    f=np.frombuffer(buf,np.uint8).reshape(H,W,3)[j0:j1,i0:i1].astype(np.int16)
    c=np.median(f[(j1-j0)//2-60:(j1-j0)//2+60,(i1-i0)//2-60:(i1-i0)//2+60].reshape(-1,3),0)
    sat=(c.max()-c.min())/max(c.max(),1)
    if (felt is None or np.abs(c-felt).sum()>40) and sat>0.35 and c.max()>120: felt=c
    if felt is None: out.append((ts[k] if k<len(ts) else None,[])); k+=1; continue
    # felt by hue-ish: blue table: b high, r low; use distance in normalised chroma
    s=f.sum(2)+1
    d=np.abs(f[:,:,0]/s-felt[0]/felt.sum())+np.abs(f[:,:,1]/s-felt[1]/felt.sum())+np.abs(f[:,:,2]/s-felt[2]/felt.sum())
    nonfelt=(d>0.12)|(f.max(2)<70)|(f.min(2)>170)
    dt=ndi.distance_transform_edt(nonfelt)
    # peaks of the distance transform ~ ball centres
    mx=ndi.maximum_filter(dt,size=11)
    pk=(dt==mx)&(dt>=R*0.75)
    lab,n=ndi.label(pk)
    cs=ndi.center_of_mass(pk,lab,range(1,n+1))
    balls=[]
    for (cy,cx) in cs:
        # refine: centroid of nonfelt in disk
        m=((yy-j0-cy)**2+(xx-i0-cx)**2<=(R-0.5)**2)&nonfelt
        if m.sum()<0.6*np.pi*R*R: continue
        ry=(yy[m]).mean(); rx=(xx[m]).mean()
        col=f[m].mean(0); white=f[m].min(1).mean()
        balls.append((rx*sx,ry*sy,int(col[0]),int(col[1]),int(col[2]),int(white)))
    out.append((ts[k] if k<len(ts) else None,balls))
    k+=1
    if k%1000==0: print(k,len(balls),file=sys.stderr)
pickle.dump(out,open(sys.argv[2],'wb'))
print('frames',k,'felt',felt)
