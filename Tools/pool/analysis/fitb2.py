import sys,math,pickle,re,subprocess
import numpy as np
sys.argv=['bl.py']+sys.argv[1:]
import io,contextlib
buf=io.StringIO()
with contextlib.redirect_stdout(buf): exec(open('bl.py').read())
L=[(o[1],o[2]) for o in ob if 0.85<o[3]<3.2]
clip=[(16.6,None)]
for fn in ['clip/bounces.pkl']:
    for d in pickle.load(open(fn,'rb')):
        if d['white'] or d['vin']<150: continue
        r=math.tan(math.radians(d['aout']))/max(1e-6,math.tan(math.radians(d['ain'])))
        if 0.85<r<3.2 and d['ain']>5: L.append((d['ain'],d['aout']))
print(len(L))
ai=np.array([a for a,b in L]); ao=np.array([b for a,b in L])
def test(name,f):
    p=np.degrees(np.arctan(f(np.tan(np.radians(ai)),ai))); e=p-ao
    print(name,'median|e| %.1f rms %.1f bias %.1f'%(np.median(abs(e)),np.sqrt((e**2).mean()),np.median(e)))
for k in [1.4,1.5,1.6,1.7]: test('ratio %.1f'%k, lambda t,a,k=k: k*t)
tab=[(0,1.4),(12,1.5),(22,1.75),(32,1.85),(45,1.65),(55,1.45),(70,1.3),(90,1.2)]
xs=[a for a,_ in tab]; ys=[r for _,r in tab]
test('table', lambda t,a: t*np.interp(a,xs,ys))
for lo,hi in [(0,15),(15,25),(25,35),(35,45),(45,55),(55,90)]:
    m=(ai>=lo)&(ai<hi)
    if m.sum(): print(lo,hi,m.sum(),'median ratio %.2f'%np.median(np.tan(np.radians(ao[m]))/np.tan(np.radians(ai[m]))))
tab=[(0,1.4),(12,1.45),(20,1.65),(30,1.62),(40,1.45),(50,1.38),(90,1.3)]
xs=[a for a,_ in tab]; ys=[r for _,r in tab]
test('table2', lambda t,a: t*np.interp(a,xs,ys))
D=[o for o in ob if 0.85<o[3]<3.2]
res=[(o[2]-math.degrees(math.atan(math.tan(math.radians(o[1]))*np.interp(o[1],xs,ys))),o[4],o[6],o[1]) for o in D]
res.sort(key=lambda r:r[1])
print('by vin'); 
for k in range(0,len(res),6): s=res[k:k+6]; print(' vin %5.0f-%5.0f mean resid %.1f'%(s[0][1],s[-1][1],np.mean([r[0] for r in s])))
res.sort(key=lambda r:r[2])
print('by dist since start')
for k in range(0,len(res),6): s=res[k:k+6]; print(' d0 %5.0f-%5.0f mean resid %.1f'%(s[0][2],s[-1][2],np.mean([r[0] for r in s])))
for near,far,cut in [(1,1,140),(0.9,1.04,140),(0.88,1.05,130),(0.92,1.03,160)]:
    e=[]
    for o in D:
        m=near if o[6]<cut else far
        p=math.degrees(math.atan(math.tan(math.radians(o[1]))*np.interp(o[1],xs,ys)*m)); e.append(p-o[2])
    e=np.array(e); print(near,far,cut,'median|e| %.1f rms %.1f'%(np.median(abs(e)),np.sqrt((e**2).mean())))
