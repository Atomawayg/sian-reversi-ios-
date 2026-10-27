"""Python port of App/SuikaEngine.swift simulate/drop, with the physics constants as parameters, for fitting against
Atom's logs. Kept close to the Swift so a fitted value can be copied straight back."""
import math

LEFT, RIGHT, FLOOR, DEAD, DROPY = 108.0, 1070.0, 2323.0, 1002.0, 905.0
CORNER = 52.0
HIT = [36, 45.7, 67, 72, 92.5, 121.8, 140.3, 171.4, 195.2, 231.6, 266.2]
TYPES = 11


class P:  # physics constants (Swift values)
    g = 3490.0
    dt = 1.0 / 120
    iters = 10
    mu = 0.1
    air = 0.995
    floor_drag = 1.0
    cap = 1500.0
    hit_scale = 1.0       # extra scale on HIT
    jitter = 0.0          # sideways nudge given to the dropped fruit (px), breaks a dead-centre balance
    woke = 1e9            # a fruit read off the screen that has moved this far (px) can merge too


class Body:
    __slots__ = ('t', 'x', 'y', 'px', 'py', 'vx', 'vy', 'r', 'im', 'tag', 'fresh', 'alive', 'ox', 'oy')

    def __init__(self, t, x, y, tag=0, p=P):
        self.t = t; self.x = x; self.y = y; self.ox = x; self.oy = y; self.px = x; self.py = y; self.vx = 0.0; self.vy = 0.0
        self.r = HIT[t] * p.hit_scale; self.im = 1 / (self.r * self.r); self.tag = tag; self.fresh = False; self.alive = True


MAXR = max(HIT) * 1.2


def simulate(b, created, merge=True, max_t=3.0, damp=1.0, p=P):
    t = 0.0; quiet = 0; tag_x = 0.0
    dt = p.dt
    while t < max_t:
        for f in b:
            f.px = f.x; f.py = f.y
            f.vy += p.g * dt
            f.x += f.vx * dt; f.y += f.vy * dt
        pairs = []
        for _ in range(p.iters):
            order = sorted(range(len(b)), key=lambda i: b[i].x)
            for a in range(len(order)):
                i = order[a]; bi = b[i]
                if not bi.alive: continue
                for c in range(a + 1, len(order)):
                    j = order[c]; bj = b[j]
                    if bj.x - bi.x > bi.r + MAXR: break
                    if not bj.alive: continue
                    dx = bj.x - bi.x; dy = bj.y - bi.y
                    rs = bi.r + bj.r
                    if merge and not bi.fresh and abs(bi.x - bi.ox) + abs(bi.y - bi.oy) > p.woke: bi.fresh = True
                    if merge and not bj.fresh and abs(bj.x - bj.ox) + abs(bj.y - bj.oy) > p.woke: bj.fresh = True
                    same = bi.t == bj.t and (bi.fresh or bj.fresh or not merge)
                    if same and not merge: rs += 1
                    d2 = dx * dx + dy * dy
                    if d2 >= rs * rs: continue
                    if same and merge:
                        if not any(q[0] in (i, j) or q[1] in (i, j) for q in pairs): pairs.append((i, j))
                        continue
                    d = math.sqrt(d2)
                    if d > 1e-6: nx, ny = dx / d, dy / d
                    else: nx, ny, d = 0.0, 1.0, 0.0
                    pen = rs - d; w = bi.im + bj.im; wi = bi.im / w; wj = bj.im / w
                    bi.x -= nx * pen * wi; bi.y -= ny * pen * wi
                    bj.x += nx * pen * wj; bj.y += ny * pen * wj
                    tx, ty = -ny, nx
                    slide = ((bj.x - bj.px) - (bi.x - bi.px)) * tx + ((bj.y - bj.py) - (bi.y - bi.py)) * ty
                    cap = p.mu * pen
                    f = slide if abs(slide) <= cap else (cap if slide > 0 else -cap)
                    bi.x += tx * f * wi; bi.y += ty * f * wi
                    bj.x -= tx * f * wj; bj.y -= ty * f * wj
                r = bi.r
                if bi.x < LEFT + r or bi.x > RIGHT - r:
                    wx = LEFT + r if bi.x < LEFT + r else RIGHT - r
                    pen = abs(bi.x - wx); bi.x = wx
                    slide = bi.y - bi.py; cap = p.mu * pen
                    bi.y -= slide if abs(slide) <= cap else (cap if slide > 0 else -cap)
                if r < CORNER and bi.y > FLOOR - CORNER:
                    cx = LEFT + CORNER if bi.x < LEFT + CORNER else (RIGHT - CORNER if bi.x > RIGHT - CORNER else bi.x)
                    cy = FLOOR - CORNER
                    if cx != bi.x:
                        dx, dy = bi.x - cx, bi.y - cy; d = math.hypot(dx, dy); lim = CORNER - r
                        if d > lim and d > 1e-6: bi.x = cx + dx / d * lim; bi.y = cy + dy / d * lim
                if bi.y > FLOOR - r:
                    pen = bi.y - (FLOOR - r); bi.y = FLOOR - r
                    slide = bi.x - bi.px; cap = p.mu * pen
                    bi.x -= slide if abs(slide) <= cap else (cap if slide > 0 else -cap)
        fastest = 0.0
        for f in b:
            vx = (f.x - f.px) / dt; vy = (f.y - f.py) / dt
            sp = math.hypot(vx, vy)
            if sp > p.cap: vx *= p.cap / sp; vy *= p.cap / sp
            on_floor = f.y >= FLOOR - f.r - 0.5
            vx *= (p.floor_drag if on_floor else p.air) * damp; vy *= p.air * damp
            f.vx = vx; f.vy = vy
            fastest = max(fastest, vx * vx + vy * vy)
        if pairs:
            new = []
            for i, j in pairs:
                bi, bj = b[i], b[j]
                if not (bi.alive and bj.alive): continue
                bi.alive = bj.alive = False
                k = bi.t + 1; created.append(k)
                if k < TYPES:
                    n = Body(k, (bi.x + bj.x) / 2, (bi.y + bj.y) / 2, p=p)
                    n.vx = (bi.vx + bj.vx) / 2; n.vy = (bi.vy + bj.vy) / 2; n.fresh = True
                    new.append(n)
            b[:] = [f for f in b if f.alive] + new
            quiet = 0
        t += dt
        if fastest < 25 * 25:
            quiet += 1
            if quiet >= 12 and t > 0.25: break
        else: quiet = 0
    return b


def settle(jar, p=P):
    b = [Body(t, x, y, p=p) for t, x, y in jar]
    simulate(b, [], merge=False, max_t=1.5, damp=0.6, p=p)
    for f in b: f.vx = f.vy = 0.0
    return b


def drop(base, t, x, p=P):
    b = [Body(f.t, f.x, f.y, p=p) for f in base]   # (origins = the settled jar)
    for f, o in zip(b, base): f.fresh = o.fresh
    me = Body(t, x + p.jitter, DROPY, tag=1, p=p); me.fresh = True
    b.append(me)
    created = []
    simulate(b, created, p=p)
    return b, created
