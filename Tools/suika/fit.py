"""Replay logged drops (D lines) in the Python engine and score against the jar seen before the next drop.
Usage: python3 -I fit.py log1.txt [log2.txt ...]   (prints the score for a few physics settings)"""
import sys, re, math, os, itertools
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import engine as E


def jar(s):
    out = []
    for tok in s.split():
        m = re.match(r'(\d+):(\d+),(\d+)', tok)
        if m: out.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
    return out


def events(path):
    rows = open(path, errors='ignore').read().splitlines()
    last = None; pend = None; out = []
    for l in rows:
        m = re.match(r'\S+ S held=(-?\d+) next=(-?\d+) n=(\d+) jar=(.*)', l)
        if m:
            last = (int(m.group(1)), jar(m.group(4))); continue
        m = re.match(r'\S+ D t=(\d+) x=(\d+)', l)
        if m:
            if pend and last: out.append((pend[0], pend[1], pend[2], last[1]))   # before, held, x, after
            pend = (last[1], int(m.group(1)), float(m.group(2))) if last else None
    # one drop only, read right: merges keep the total 'mass' (2^kind), so before + held = after exactly
    return [e for e in out if sum(2 ** t for t, _, _ in e[0]) + 2 ** e[1] == sum(2 ** t for t, _, _ in e[3])]


def score(pred, real):
    """made-kinds right (biggest made), and mean distance of matched same-kind fruits"""
    from collections import Counter
    pc = Counter(f.t for f in pred); rc = Counter(t for t, x, y in real)
    kinds = sum(abs(pc[t] - rc[t]) for t in range(E.TYPES))
    d = []; used = set()
    for t, x, y in sorted(real, key=lambda a: -a[0]):
        best = None
        for i, f in enumerate(pred):
            if i in used or f.t != t: continue
            dd = math.hypot(f.x - x, f.y - y)
            if best is None or dd < best[0]: best = (dd, i)
        if best: used.add(best[1]); d.append(min(best[0], 300))
    return kinds, (sum(d) / len(d) if d else 0)


def run(evs, p):
    K = D = 0; exact = 0
    for before, held, x, after in evs:
        base = E.settle(before, p)
        b, made = E.drop(base, held, x, p)
        k, d = score(b, after)
        K += k; D += d; exact += k == 0
    n = len(evs)
    return K / n, D / n, exact / n


def events_any(path):
    """Also for logs without D lines: drop x = the app's suggestion (Atom follows it to ~9 px). A drop is a jar
    followed by one whose mass is exactly the jar's plus the held fruit's; the last such reading is the settled one."""
    rows = open(path, errors='ignore').read().splitlines()
    mass = lambda j: sum(2 ** t for t, _, _ in j)
    cur = None; sugg = None; dx = None; out = []
    pending = None   # (before, held, x, after)
    for l in rows:
        m = re.match(r'\S+ A x=(\d+)', l)
        if m: sugg = float(m.group(1)); continue
        m = re.match(r'\S+ D t=(\d+) x=(\d+)', l)
        if m: dx = float(m.group(2)); continue
        m = re.match(r'\S+ S held=(-?\d+) next=(-?\d+) n=(\d+) jar=(.*)', l)
        if not m: continue
        held = int(m.group(1)); j = jar(m.group(4))
        if pending and mass(j) == mass(pending[0]) + 2 ** pending[1]:
            pending = (pending[0], pending[1], pending[2], j); cur = (held, j); continue
        if pending and pending[3] is not None: out.append(pending)
        pending = None
        if cur and held >= 0 and cur[0] >= 0 and mass(j) == mass(cur[1]) + 2 ** cur[0] and (dx or sugg):
            pending = (cur[1], cur[0], dx or sugg, j)
        cur = (held, j); dx = None
    if pending and pending[3] is not None: out.append(pending)
    return out


if __name__ == '__main__':
    evs = [e for f in sys.argv[1:] for e in events_any(f)]
    # only drops whose after-jar is plausible (same fruit count give or take merges)
    print('events', len(evs))
    base = run(evs, E.P)
    print('swift now: kinds-off %.2f  pos %.1f px  exact %.0f%%' % (base[0], base[1], 100 * base[2]))
