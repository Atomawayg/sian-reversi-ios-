import re,sys,math
def T(s): h,m,x=s[:10].split(':'); return int(h)*3600+int(m)*60+float(x)
def load(f):
    rows=[]
    for ln in open(f):
        m=re.search(r'balls=((?:\d+:\d+,\d+ ?)+)',ln)
        if not m: continue
        rows.append((T(ln),ln.split()[1]=='M',{int(a):(int(b),int(c)) for a,b,c in re.findall(r'(\d+):(\d+),(\d+)',m.group(1))},ln))
    return rows
if __name__=='__main__':
    rows=load(sys.argv[1])
    # print each roll: the last non-M row before (aim/power), then cue track
    i=0
    while i<len(rows):
        if rows[i][1]:
            j=i
            while j<len(rows) and rows[j][1]: j+=1
            pre=rows[i-1][3] if i>0 else ''
            aim=re.search(r' aim=(\d+),(\d+)',pre); pw=re.search(r' power=(\d+)',pre); d=re.search(r' dir=([\d.]+)',pre)
            tr=[(round(rows[k][0]-rows[i][0],1),rows[k][2].get(0)) for k in range(i,j)]
            print('ROLL',rows[i][3][:10],'n',j-i,'aim',aim and aim.groups(),'pow',pw and pw[1],'dir',d and d[1],'cue0',rows[i-1][2].get(0) if i>0 else None)
            print('   ',' '.join(f"{t}:{p[0]},{p[1]}" if p else f"{t}:-" for t,p in tr[:40]))
            i=j
        else: i+=1
