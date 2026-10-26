import sys,math,pickle; sys.path.insert(0,'.')
import eng5 as E
S=pickle.load(open('evshots.pkl','rb'))
def clean(s):
    if not s['tgt'] or s['pow']<8 or s['pow']>95: return False
    tid=s['tgt'][0]
    if 0 not in s['rest']: return False
    return set(s['moved'])<= {0,tid} and set(s['gone'])<= {tid}
C=[s for s in S if clean(s)]
def pred(s):
    o,c=E.powerPaths(*s['cue'],*s['aim'],s['tgt'],s['balls'],s['dir'],s['pow'])
    return o,c
if __name__=='__main__':
    errs=[]
    for s in C:
        o,c=pred(s)
        cs=c['pts'][-2:]; r=s['rest'][0]
        e=math.hypot(cs[0]-r[0],cs[1]-r[1])
        # how far the cue ball moved after the hit, really vs predicted
        ax,ay=s['aim']
        dr=math.hypot(r[0]-ax,r[1]-ay); dp=math.hypot(cs[0]-ax,cs[1]-ay)
        tid=s['tgt'][0]; oe=None
        if tid in s['rest'] and o:
            orr=s['rest'][tid]; op=o['pts'][-2:]; oe=math.hypot(op[0]-orr[0],op[1]-orr[1])
        errs.append(e)
        print(f"{s['t']} p{s['pow']:3d} cueErr {e:5.0f} real {dr:5.0f} pred {dp:5.0f} rails {c['rails']} obj {'drop' if tid not in s['rest'] else f'{oe:.0f}' if oe is not None else '-'} spin {s['spin']}")
    errs.sort(); print(len(errs),'median',errs[len(errs)//2])
