import pickle,numpy as np,math
res=pickle.load(open('bounces.pkl','rb'))
seen=set(); R=[]
for r in res:
    k=(r['f'],round(r['t'],1))
    if k in seen: continue
    seen.add(k); R.append(r)
print('bounces',len(R))
for r in R: print('CUE' if r['white'] else 'obj',r['f'][:9],r['t'],r['side'],'v',r['vin'],'->',r['vout'],'ang',r['ain'],'->',r['aout'],'kn',r['kn'],'kt',r['kt'])
kn=[r['kn'] for r in R if r['vin']>250 and not r['white']]; kt=[r['kt'] for r in R if r['kt'] and r['vin']>250 and r['ain']>15 and not r['white']]
print('kn median %.3f n=%d'%(np.median(kn),len(kn)),'kt median %.3f n=%d'%(np.median(kt),len(kt)))
def pred(a,r): return math.degrees(math.atan(math.tan(math.radians(a))*r))
D=[(r['ain'],r['aout'],r['vin']) for r in R if r['vin']>250 and 5<r['ain']<80 and not r['white']]
print('object-ball bounces',len(D))
for ratio in (1.5,1.6,1.7,1.76,1.85,2.0):
    e=[pred(a,ratio)-b for a,b,v in D]
    print('ratio',ratio,'rms %.1f'%np.sqrt(np.mean(np.square(e))),'median %.1f'%np.median(e))
e=[math.degrees(math.atan(1.14*math.tan(math.radians(a))+0.4*math.sin(2*math.radians(a))))-b for a,b,v in D]
print('app law rms %.1f median %.1f'%(np.sqrt(np.mean(np.square(e))),np.median(e)))
