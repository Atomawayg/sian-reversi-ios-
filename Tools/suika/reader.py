"""Python port of Broadcast/SuikaReader.swift (readSuikaFull) for fast work on screenshots.
Usage: python3 -I reader.py shot.png [out.png]   -> prints fruits, draws them on out.png
"""
import sys, math
import numpy as np
from PIL import Image, ImageDraw

LEFT, RIGHT, FLOOR, DEAD, TOP = 108.0, 1070.0, 2323.0, 1002.0, 800.0
RADIUS = [35, 48, 63, 75, 92, 121, 138, 168, 200, 235, 280]
NAMES = ['cherry', 'straw', 'grape', 'dekopon', 'persim', 'apple', 'pear', 'peach', 'pine', 'melon', 'wmelon']
MASK = [1 << 1 | 1 << 2, 1 << 2 | 1 << 1, 1 << 3, 1 << 4, 1 << 5, 1 << 1 | 1 << 2, 1 << 4, 1 << 6 | 1 << 2 | 1 << 1 | 1 << 7 | 1 << 8, 1 << 4, 1 << 7 | 1 << 8, 1 << 8 | 1 << 1 | 1 << 2 | 1 << 6]
CORNER = 52.0
CLAIM = 0.95
LEAVES = True


def groups(img):
    """skGroup for every pixel of an RGB float array"""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    mx = img.max(-1); mn = img.min(-1)
    v = mx / 255; s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-9), 0)
    d = np.maximum(mx - mn, 1e-9)
    h = np.where(mx == r, 60 * ((g - b) / d), np.where(mx == g, 60 * ((b - r) / d + 2), 60 * ((r - g) / d + 4)))
    h = np.where(mx == mn, 0, h); h = np.where(h < 0, h + 360, h)
    out = np.zeros(img.shape[:2], np.uint8)
    done = v < 0.35
    def put(cond, val):
        nonlocal done
        c = cond & ~done
        out[c] = val if np.isscalar(val) else val[c]
        done = done | c
    put((s >= 0.52) & ((h >= 335) | (h <= 14)), np.where(b - g > 8, 2, 1).astype(np.uint8))
    put(((s >= 0.25) | ((s >= 0.12) & (v > 0.8))) & (h >= 235) & (h <= 305), 3)
    put((s >= 0.45) & (h >= 35) & (h <= 60), 4)
    put((s >= 0.58) & (h >= 17) & (h < 35), 5)
    put((s >= 0.3) & (h >= 100) & (h <= 170), 7)   # melon green
    put((s >= 0.3) & (h >= 62) & (h < 100), 8)     # yellow-green: the watermelon frog, leaves
    put((v > 0.78) & (s <= 0.55) & ((h >= 330) | (h < 12)), 6)
    put((v > 0.9) & (s < 0.12), 6)
    return out


def load(path):
    im = Image.open(path).convert('RGB')
    if im.size != (1179, 2556):
        im = im.resize((1179, 2556), Image.BILINEAR)
    return np.asarray(im).astype(float)


S = 4.0


def grid_of(img):
    gw = int((RIGHT - LEFT) / S); gh = int((FLOOR + 6 - TOP) / S)
    xs = (LEFT + np.arange(gw) * S + S / 2).astype(int)
    ys = (TOP + np.arange(gh) * S + S / 2).astype(int)
    return groups(img[np.ix_(ys, xs)]), gw, gh


def read(img, classify=None):
    grid, gw, gh = grid_of(img)
    claimed = np.zeros((gh, gw), bool)
    unit = [(0.0, 0.0)]
    for fr, k in [(0.3, 8), (0.55, 12), (0.8, 18)]:
        for a in range(k):
            t = 2 * math.pi * a / k; unit.append((fr * math.cos(t), fr * math.sin(t)))
    def on(x, y, m):
        if x < 0 or x >= gw or y < 0 or y >= gh: return False
        g = grid[y, x]
        return (not claimed[y, x]) and g != 0 and (m >> int(g)) & 1
    def score(ci, cj, rr, m):
        # leaves and stems are drawn over the fruits next to them: for a fruit that isn't green, a green point says nothing
        hit = rim = tot = trim = 0
        green_ok = not (m >> 7) & 1 and not (m >> 8) & 1
        for k, (ux, uy) in enumerate(unit):
            x, y = int(round(ci + ux * rr)), int(round(cj + uy * rr))
            if green_ok and LEAVES and 0 <= x < gw and 0 <= y < gh and grid[y, x] in (7, 8): continue
            tot += 1; trim += k >= 21
            if on(x, y, m):
                hit += 1
                if k >= 21: rim += 1
        return hit / max(1, tot), rim / max(1, trim)
    def edge(ci, cj, rr, m):
        return sum(1 for a in range(36) if on(int(round(ci + 0.88 * rr * math.cos(2 * math.pi * a / 36))), int(round(cj + 0.88 * rr * math.sin(2 * math.pi * a / 36))), m))
    def lookalike(t, ci, cj, rr, m):
        h = tot = 0
        for a in range(32):
            x = int(round(ci + 0.93 * rr * math.cos(2 * math.pi * a / 32))); y = int(round(cj + 0.93 * rr * math.sin(2 * math.pi * a / 32)))
            if x < 0 or x >= gw or y < 0 or y >= gh: continue   # past the wall: says nothing
            tot += 1; h += on(x, y, m)
        if tot == 0 or h / tot < (0.6 if t == 10 else 0.35): return False
        if t < 7: return True
        n = pale = red = band = bown = yg = gr = 0
        R = int(rr) + 1
        for y in range(max(0, int(cj) - R), min(gh - 1, int(cj) + R) + 1):
            for x in range(max(0, int(ci) - R), min(gw - 1, int(ci) + R) + 1):
                d = math.hypot(x - ci, y - cj); g = grid[y, x]
                if d <= 0.85 * rr:
                    n += 1; pale += g == 6; red += g in (1, 2); yg += g == 8; gr += g == 7
                if 0.6 * rr < d < 0.95 * rr:
                    band += 1; bown += on(x, y, m)
        f = max(1, n)
        if t == 7: return pale / f >= 0.2
        if t == 8: return bown / max(1, band) >= 0.8
        if t == 9: return gr / f >= 0.35 and gr > 2 * yg and red / f < 0.25   # melon green (3.43: 'no red' failed when a red fruit lay across it)
        if t == 10: return red / f >= 0.06 and yg / f >= 0.3   # the frog is mostly yellow-green
        return True
    def near_corner(ci, cj):
        px, py = LEFT + ci * S, TOP + cj * S
        return py > FLOOR - 110 and (px < LEFT + 110 or px > RIGHT - 110)
    found = []
    for t in [10, 9, 8, 5, 7, 6, 4, 3, 2, 1, 0]:
        rr = RADIUS[t] / S; m = MASK[t]
        iLo, iHi, jHi = int(rr * 0.9), gw - int(rr * 0.9), gh - int(rr * 0.85)
        if iLo >= iHi or jHi <= 0: continue
        cands = []
        for j in range(2, jHi, 2):
            for i in range(iLo, iHi, 2):
                g = grid[j, i]
                if not claimed[j, i] and g != 0 and (m >> int(g)) & 1 and (t != 10 or g == 8):   # a watermelon starts from its green
                    a, r = score(i, j, rr, m)
                    nc = t <= 2 and near_corner(i, j)
                    if a >= (0.5 if nc else 0.62) and r >= (0.3 if nc else 0.5): cands.append((a, i, j))
        cands.sort(key=lambda c: -c[0])
        for _, i, j in cands:
            if claimed[j, i]: continue
            R = int(rr * 1.05) + 1
            sxs = sys_ = cnt = 0.0
            for y in range(max(0, j - R), min(gh - 1, j + R) + 1):
                for x in range(max(0, i - R), min(gw - 1, i + R) + 1):
                    if (x - i) ** 2 + (y - j) ** 2 > rr * rr * 1.1: continue
                    if on(x, y, m): sxs += x; sys_ += y; cnt += 1
            if cnt == 0: continue
            ci, cj = sxs / cnt, sys_ / cnt
            bx, by, bh = ci, cj, edge(ci, cj, rr, m)
            # coarse (1 cell) then fine (half a cell) around the best: 90 tries instead of 289
            for step, span, ox, oy in ((1.0, 4, ci, cj), (0.5, 1, None, None)):
                cx0, cy0 = (ox, oy) if ox is not None else (bx, by)
                for dy in range(-span, span + 1):
                    for dx in range(-span, span + 1):
                        x, y = cx0 + dx * step, cy0 + dy * step
                        h = edge(x, y, rr, m)
                        if h > bh or (h == bh and (x - ci) ** 2 + (y - cj) ** 2 < (bx - ci) ** 2 + (by - cj) ** 2): bx, by, bh = x, y, h
            ci, cj = bx, by
            a, r = score(ci, cj, rr, m)
            ncc = t <= 2 and near_corner(ci, cj)
            if a < (0.48 if ncc else 0.6) or r < (0.28 if ncc else 0.45): continue
            if not lookalike(t, ci, cj, rr, m): continue
            tt, rr2 = t, rr
            if t <= 1:
                n = red = pink = yel = 0.0
                R = int(rr * 0.85) + 1
                for y in range(max(0, int(cj) - R), min(gh - 1, int(cj) + R) + 1):
                    for x in range(max(0, int(ci) - R), min(gw - 1, int(ci) + R) + 1):
                        if (x - ci) ** 2 + (y - cj) ** 2 > rr * rr * 0.72: continue
                        g = grid[y, x]; n += 1
                        red += g == 1; pink += g == 2; yel += g == 4
                straw = n > 0 and red / n < 0.22 and yel / n < 0.05 and pink / n > 0.55
                cherry = n > 0 and yel / n >= 0.03 and red / n >= 0.2
                if not straw and not cherry: continue
                tt = 1 if straw else 0
                rr2 = RADIUS[tt] / S
            px, py = LEFT + ci * S + S / 2, TOP + cj * S + S / 2
            px = min(max(px, LEFT + RADIUS[tt]), RIGHT - RADIUS[tt]); py = min(py, FLOOR - RADIUS[tt])
            if any(math.hypot(f[1] - px, f[2] - py) < 0.7 * (RADIUS[f[0]] + RADIUS[tt]) for f in found): continue
            found.append((tt, px, py))
            C = int(rr2 + 2)
            for y in range(max(0, int(cj) - C), min(gh - 1, int(cj) + C) + 1):
                for x in range(max(0, int(ci) - C), min(gw - 1, int(ci) + C) + 1):
                    if (x - ci) ** 2 + (y - cj) ** 2 <= (rr2 * CLAIM) ** 2: claimed[y, x] = True
    return found


def draw(path, found, out, truth=None):
    im = Image.open(path).convert('RGB').resize((1179, 2556))
    d = ImageDraw.Draw(im)
    for t, x, y in found:
        r = RADIUS[t]
        d.ellipse([x - r, y - r, x + r, y + r], outline=(0, 0, 0), width=5)
        d.text((x - 20, y - 10), f'{t}', fill=(0, 0, 0))
    for t, x, y in truth or []:
        d.text((x - 20, y + 10), f'T{t}', fill=(255, 0, 255))
    im.resize((590, 1278)).save(out)


if __name__ == '__main__':
    f = read(load(sys.argv[1]))
    for t, x, y in sorted(f, key=lambda a: (a[2], a[1])): print(t, NAMES[t], int(x), int(y))
    if len(sys.argv) > 2: draw(sys.argv[1], f, sys.argv[2])
