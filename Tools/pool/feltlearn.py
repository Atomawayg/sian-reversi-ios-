import sys;sys.path.insert(0,'.');import poolnp as P,numpy as np,math
from PIL import Image
PTS=[(x,y) for y in (700,1000,1300,1600,1900,2050) for x in (300,480,700,880)]
def learn(a):
    h,s,v=[],[],[]
    for x,y in PTS:
        p=a[y-3:y+4,x-3:x+4].reshape(-1,3).mean(0)[None]
        H,S,V=P.hsv(p); h.append(float(H[0]));s.append(float(S[0]));v.append(float(V[0]))
    # median hue (circular): choose the sample whose neighbourhood is largest
    def hd(a,b): return abs((a-b+180)%360-180)
    best=max(range(len(h)),key=lambda i:sum(1 for j in range(len(h)) if hd(h[i],h[j])<12 and s[j]>0.2 and v[j]>0.3))
    inl=[j for j in range(len(h)) if hd(h[best],h[j])<12 and s[j]>0.2 and v[j]>0.3]
    if len(inl)<len(PTS)*0.7: return None
    # circular mean of inliers
    ang=math.atan2(sum(math.sin(math.radians(h[j])) for j in inl),sum(math.cos(math.radians(h[j])) for j in inl))
    H0=math.degrees(ang)%360
    ss=[s[j] for j in inl]; vv=[v[j] for j in inl]
    return H0, max(0.15,min(ss)-0.15), min(0.92,max(ss)+0.12), max(0.25,min(vv)-0.17), min(0.99,max(vv)+0.08), len(inl)
def mk(par):
    H0,sl,sh,vl,vh,_=par
    def felt(a):
        h,s,v=P.hsv(a)
        return (abs((h-H0+180)%360-180)<16)&(s>sl)&(s<sh)&(v>vl)&(v<vh)
    return felt
if __name__=='__main__':
    for f in sys.argv[1:]:
        a=np.asarray(Image.open(f).convert('RGB'))
        par=learn(a); print(f,par)
        if par:
            P.felt=mk(par); bs=P.balls(a); print(len(bs),[(int(x),int(y)) for x,y in bs])
