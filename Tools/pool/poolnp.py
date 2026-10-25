"""numpy copy of the app's old PoolReader (Broadcast/PoolReader.swift) for analysing recordings."""
import numpy as np, math

R = 23.5
X0, X1, Y0, Y1 = 207.5, 966.5, 584.0, 2135.0


def hsv(a):
    a = a.astype(np.float32) / 255
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1); mn = a.min(-1); d = mx - mn
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == b, 240 + 60 * (r - g) / dd, np.where(mx == g, 120 + 60 * (b - r) / dd, np.mod(60 * (g - b) / dd, 360)))
    h = np.where(d > 1e-6, h, 0)
    return h, s, mx


def felt(a):
    h, s, v = hsv(a)
    return (h > 183) & (h < 213) & (s > 0.42) & (s < 0.9) & (v > 0.45) & (v < 0.92)


def looks_like_pool(img):
    def px(x, y):
        return img[int(y) - 3:int(y) + 4, int(x) - 3:int(x) + 4].reshape(-1, 3).mean(0)
    f = sum(bool(felt(px(x, y)[None])[0]) for x, y in [(400, 700), (780, 700), (400, 2000), (780, 2000), (300, 1360), (880, 1360)])
    p1, p2 = px(203, 581), px(976, 2139)
    dark = p1.mean() < 45 and p2.mean() < 45
    w = px(590, 540)
    return f >= 5 and dark and w[0] > w[2] + 40 and w[0] > 120, (f, p1.mean(), p2.mean(), w)


def balls(img):
    """ball centres (x, y) via the same felt-grid + square test as the app, refined by centroid"""
    g = 3
    xs = np.arange(X0, X1 + 0.01, g).round().astype(int); ys = np.arange(Y0, Y1 + 0.01, g).round().astype(int)
    fg = ~felt(img[ys][:, xs])
    half = int(((R - 2) / math.sqrt(2)) / g)
    I = np.pad(fg.astype(np.int32).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    ny, nx = fg.shape
    k = 2 * half + 1
    box = I[k:, k:] - I[:-k, k:] - I[k:, :-k] + I[:-k, :-k]          # box sum with top-left at (j,i)
    sc = np.zeros(fg.shape); sc[half:half + box.shape[0], half:half + box.shape[1]] = box / (k * k)
    m = int((R - 2) / g)
    sc[:m] = 0; sc[-m:] = 0; sc[:, :m] = 0; sc[:, -m:] = 0
    cj, ci = np.nonzero((sc >= 0.95) & fg)
    order = np.argsort(-sc[cj, ci], kind='stable')
    picked = []
    sup = 40 / g
    for o in order:
        i, j = ci[o], cj[o]
        if len(picked) >= 40: break
        if any((p[0] - i) ** 2 + (p[1] - j) ** 2 < sup * sup for p in picked): continue
        picked.append((i, j))
    out = []
    for i, j in picked:
        cx, cy = X0 + i * g, Y0 + j * g
        for _ in range(3):
            yy, xx = np.mgrid[int(cy - R + 1):int(cy + R), int(cx - R + 1):int(cx + R)]
            ins = (xx - cx) ** 2 + (yy - cy) ** 2 <= (R - 1) ** 2
            nf = ~felt(img[yy[ins], xx[ins]])
            if nf.sum() > 10: cx, cy = xx[ins][nf].mean(), yy[ins][nf].mean()
        out.append((cx, cy))
    return out


def aim_circle(img):
    """hollow white ring of ball size (the game's ghost ball)"""
    g = 2
    xs = np.arange(X0, X1 + 0.01, g).round().astype(int); ys = np.arange(Y0, Y1 + 0.01, g).round().astype(int)
    h, s, v = hsv(img[ys][:, xs])
    W = (s < 0.22) & (v > 0.85)
    ny, nx = W.shape
    ring = [(int(round((R - 1.5) * math.cos(a) / g)), int(round((R - 1.5) * math.sin(a) / g))) for a in np.arange(40) * math.pi / 20]
    core = [(di, dj) for dj in range(-8, 9, 2) for di in range(-8, 9, 2) if di * di + dj * dj <= 64]
    m = int(R / g) + 2
    rc = np.zeros((ny, nx)); cc = np.zeros((ny, nx))
    for di, dj in ring: rc[m:ny - m, m:nx - m] += W[m + dj:ny - m + dj, m + di:nx - m + di]
    for di, dj in core: cc[m:ny - m, m:nx - m] += W[m + dj:ny - m + dj, m + di:nx - m + di]
    scr = np.where(rc >= 16, rc / len(ring) - cc / len(core), 0)
    j, i = np.unravel_index(np.argmax(scr), scr.shape)
    if scr[j, i] <= 0.32: return None
    return X0 + i * g, Y0 + j * g
