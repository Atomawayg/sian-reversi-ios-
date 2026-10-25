import math, importlib
import sim as S
def build(e, rc, jl=30):
    S.segs.clear()
    X0,X1,Y0,Y1=207.5,966.5,584.0,2135.0; mx=lambda x:2*587-x; my=lambda y:2*1359.5-y
    add=lambda a,b,k:S.segs.append((a[0],a[1],b[0],b[1],k))
    tx=270-e; ty=650-e
    add((tx,Y0),(mx(tx),Y0),0); add((tx,Y1),(mx(tx),Y1),0)
    for x in (X0,X1):
        add((x,ty),(x,1319.5),0); add((x,1399.5),(x,my(ty)),0)
    for a,b in [((tx,Y0),(tx-jl,Y0-jl)),((X0,ty),(X0-jl,ty-jl))]:
        for fx in (0,1):
            for fy in (0,1):
                A=(mx(a[0]) if fx else a[0], my(a[1]) if fy else a[1]); B=(mx(b[0]) if fx else b[0], my(b[1]) if fy else b[1]); add(A,B,1)
    for fx in (0,1):
        for a,b in [((X0,1319.5),(190,1321)),((X0,1399.5),(190,1398))]:
            add(((mx(a[0]) if fx else a[0]),a[1]),((mx(b[0]) if fx else b[0]),b[1]),1)
    S.HOLES[:]=[(195,570,rc),(979,570,rc),(170,1360,37),(1004,1360,37),(195,2149,rc),(979,2149,rc)]
def d(a): return math.cos(math.radians(a)),math.sin(math.radians(a))
cases=[('A 11 bounce',(793,1134),283.55,False,1),('B rail roll',(845,608),0.0,False,1),('C 8 pot',(821,822),305.1,True,1),
       ('D 5 pot',(916,619),-24.1,True,1),('E 8 pot',(574,1184),304.0,True,1),('F left rail roll',(236,893),270.0,True,0),
       ('G pot 2 MR',(441,1587),337.6,True,3),('H pot 1 MR',(848,1428),331.1,True,3)]
def score(e,rc,verbose=False):
    build(e,rc); ok=0
    for name,p,a,truth,hole in cases:
        r=S.sim(p[0],p[1],*d(a),maxhits=4)
        pred= r['pocket']==hole
        ok+= pred==truth
        if verbose: print(' ',name,truth,pred,r['pocket'],r['rails'],r['jaws'],[round(v) for v in r['pts']])
    return ok
best=[]
for e in range(0,31,3):
    for rc in range(28,46,2):
        best.append((score(e,rc),e,rc))
best.sort(reverse=True); print(best[:12])
for s,e,rc in best[:3]:
    print('e',e,'rc',rc,s); score(e,rc,True)
print('current'); print(score(0,40,True))
