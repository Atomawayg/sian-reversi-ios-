import Foundation

/// Reads WePlay Crazy Alpaca. Works in "virtual" coordinates of a 1180-wide screen (iPhone 15/16 Pro size);
/// other screen sizes are scaled. Steps (each mirrors the Python reference it was tested with):
///  1. open tiles: cream/lavender face mask → ring score of a 112 px square → local maxima
///  2. tile type: 16×16 colour samples divided by the face colour → nearest of 16 trained centroids
///  3. covered tiles: darkened tile art at lattice positions, matched at quarter resolution,
///     greedily from the most visible, each match then hides what is under it
///  4. rack (7 slots) and held row (tiles pulled out with ⬆)
enum AlpacaReader {
    static let F = 112, inset = 14
    static let boardY0 = 600.0, boardY1 = 1840.0
    private static var lastKey: [Int] = []
    private static var lastCovered: [(x: Double, y: Double, type: Int)] = []

    /// Grass at the sides, wood rack below; dimmed grass = a game window is open over the board.
    static func screen(_ s: BoardReader.Sampler) -> Int {   // 0 not this game, 1 board, 2 dimmed
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var bright = 0, dim = 0
        for (x, y) in [(30.0, 640.0), (1150, 640), (30, 1500), (1150, 1500)] {
            let p = s.avg(x * sx, y * sy, 3 * sx)
            if p.1 > 220 && p.0 > 165 && p.0 < 215 && p.2 > 95 && p.2 < 145 { bright += 1 }
            else if p.1 > 54 && p.1 < 76 && p.0 > 42 && p.0 < 64 && p.2 < 45 && p.1 > p.0 + 6 { dim += 1 }
        }
        let rack = s.avg(590 * sx, 2110 * sy, 3 * sx)
        let rackOK = rack.0 > rack.2 + 60 && rack.0 > rack.1 + 30
        let rackDim = rack.0 > rack.2 + 15 && rack.0 < 70
        if bright >= 3 && rackOK { return 1 }
        if dim >= 3 && rackDim { return 2 }
        return 0
    }

    static func read(_ s: BoardReader.Sampler) -> BoardMessage {
        var cells = [Int](repeating: 0, count: AL.count)
        let scr = screen(s)
        if scr == 2 { cells[AL.flags] = 2; return BoardMessage(valid: true, game: .alpaca, cells: cells, me: 0, myTurn: false) }
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        let W = 1180, H = Int((Double(s.h) / sy).rounded())
        @inline(__always) func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int(Double(x) * sx))), min(s.h - 1, max(0, Int(Double(y) * sy))))
        }

        // 1) open tiles
        let y0 = 560, y1 = min(2200, H)
        let mh = y1 - y0
        var I = [Int32](repeating: 0, count: (mh + 1) * (W + 1))
        for y in 0..<mh {
            var row: Int32 = 0
            for x in 0..<W {
                let p = px(x, y + y0)
                let mx = max(p.0, p.1, p.2), mn = min(p.0, p.1, p.2)
                if mn > 175 && mx > 235 && mx - mn < 75 { row += 1 }
                I[(y + 1) * (W + 1) + x + 1] = I[y * (W + 1) + x + 1] + row
            }
        }
        @inline(__always) func rs(_ y: Int, _ x: Int, _ h: Int, _ w: Int) -> Int32 {
            I[(y + h) * (W + 1) + x + w] - I[y * (W + 1) + x + w] - I[(y + h) * (W + 1) + x] + I[y * (W + 1) + x]
        }
        let a = inset, k = F - 2 * inset
        let area = Double(F * F - k * k)
        var cand: [(Double, Int, Int)] = []
        var y = 0
        while y < mh - F {
            var x = 0
            while x < W - F {
                let o = rs(y, x, F, F)
                if Double(o) >= 0.86 * area {
                    let sc = Double(o - rs(y + a, x + a, k, k)) / area
                    if sc >= 0.86 { cand.append((sc, x, y + y0)) }
                }
                x += 2
            }
            y += 2
        }
        cand.sort { $0.0 > $1.0 }
        var picked: [(Int, Int)] = []
        for c in cand where !picked.contains(where: { abs($0.0 - c.1) < 78 && abs($0.1 - c.2) < 78 }) { picked.append((c.1, c.2)) }
        var tiles: [(x: Double, y: Double)] = []
        for (x, y) in picked {
            let cx = Double(x) + Double(F) / 2, cy = Double(y) + Double(F) / 2
            let c = avgRect(px, Int(cx) - 45, Int(cy) - 45, 10, 10)
            if !(c.0 > 200 && c.1 > 205 && min(c.0, c.1, c.2) < 246 && abs(c.1 - c.2) > 8) { continue }
            tiles.append((cx, cy))
        }

        // 2) types
        var open: [(x: Double, y: Double, type: Int)] = []
        var rack: [(Double, Int)] = [], held: [(Double, Int)] = []
        for t in tiles {
            let ty = classify(px, t.x, t.y)
            if t.y > boardY0 && t.y < boardY1 { open.append((t.x, t.y, ty)) }
            else if t.y > 1850 && t.y < 2000 { held.append((t.x, ty)) }
            else if t.y > 2030 && t.y < 2130 { rack.append((t.x, ty)) }
        }
        rack.sort { $0.0 < $1.0 }; held.sort { $0.0 < $1.0 }
        for (i, r) in rack.prefix(7).enumerated() { cells[AL.rack + i] = r.1 + 1 }
        for (i, h) in held.prefix(3).enumerated() { cells[AL.held + i] = h.1 + 1 }
        guard !open.isEmpty else {
            cells[AL.flags] = scr == 1 || !rack.isEmpty ? 1 : 0
            return BoardMessage(valid: cells[AL.flags] == 1, game: .alpaca, cells: cells, me: 0, myTurn: true)
        }
        cells[AL.flags] = 1

        // lattice origin from the open tiles (circular mean of the positions modulo the lattice step)
        var cxs = 0.0, sxs = 0.0, cys = 0.0, sys = 0.0
        for o in open {
            cxs += cos(2 * Double.pi * o.x / AL.dx); sxs += sin(2 * Double.pi * o.x / AL.dx)
            cys += cos(2 * Double.pi * o.y / AL.dy); sys += sin(2 * Double.pi * o.y / AL.dy)
        }
        var ox = atan2(sxs, cxs) / (2 * Double.pi) * AL.dx, oy = atan2(sys, cys) / (2 * Double.pi) * AL.dy
        if ox < 0 { ox += AL.dx }; if oy < 0 { oy += AL.dy }

        // 3) covered tiles (reuse the last answer while the open tiles haven't changed)
        let key = open.map { Int($0.x) / 8 * 10000 + Int($0.y) / 8 * 20 + $0.type }.sorted()
        var covered: [(x: Double, y: Double, type: Int)]
        if key == lastKey { covered = lastCovered }
        else {
            covered = findCovered(px, H: H, open: open, ox: ox, oy: oy)
            lastKey = key; lastCovered = covered
        }

        // 4) encode: open tiles first, then covered from the top layer down
        var n = 0
        func put(_ x: Double, _ y: Double, _ state: Int, _ type: Int) {
            guard n < AL.maxTiles else { return }
            let k = max(0, Int(((x - ox) / AL.dx).rounded())), j = Int(((y - oy) / AL.dy).rounded()) - AL.j0
            let at = AL.tiles + 5 * n
            cells[at] = min(17, k / 18); cells[at + 1] = k % 18; cells[at + 2] = max(0, min(17, j))
            cells[at + 3] = state; cells[at + 4] = max(0, type)
            n += 1
        }
        for o in open { put(o.x, o.y, AL.open, o.type) }
        for c in covered { put(c.x, c.y, c.type >= 0 ? AL.coveredKnown : AL.coveredUnknown, c.type) }
        return BoardMessage(valid: true, game: .alpaca, cells: cells, me: 0, myTurn: true)
    }

    @inline(__always) static func avgRect(_ px: (Int, Int) -> (Double, Double, Double), _ x0: Int, _ y0: Int, _ w: Int, _ h: Int) -> (Double, Double, Double) {
        var r = 0.0, g = 0.0, b = 0.0
        for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { let p = px(x, y); r += p.0; g += p.1; b += p.2 } }
        let n = Double(w * h)
        return (r / n, g / n, b / n)
    }

    /// Nearest trained centroid of a 16×16 colour feature (3×3 box samples on a 100 px crop).
    static func classify(_ px: (Int, Int) -> (Double, Double, Double), _ cx: Double, _ cy: Double) -> Int {
        let x0 = cx - 50, y0 = cy - 50
        let face = avgRect(px, Int(x0 + 5), Int(y0 + 5), 15, 15)
        let fr = max(face.0 / 255, 0.2), fg = max(face.1 / 255, 0.2), fb = max(face.2 / 255, 0.2)
        var f = [Float](repeating: 0, count: 768)
        for v in 0..<16 { for u in 0..<16 {
            let sx = Int((x0 + (4 + 2 * Double(u) + 0.5) * 2.5).rounded()), sy = Int((y0 + (4 + 2 * Double(v) + 0.5) * 2.5).rounded())
            let p = avgRect(px, sx - 1, sy - 1, 3, 3)
            let i = (v * 16 + u) * 3
            f[i] = Float(p.0 / 255 / fr); f[i + 1] = Float(p.1 / 255 / fg); f[i + 2] = Float(p.2 / 255 / fb)
        } }
        var best = 0, bd = Float.greatestFiniteMagnitude
        let C = AlpacaData.centroids
        for t in 0..<16 {
            var d: Float = 0
            let base = t * 768
            for i in 0..<768 { let e = f[i] - C[base + i]; d += e * e }
            if d < bd { bd = d; best = t }
        }
        return best
    }

    /// Greedy covered-tile search on a quarter-resolution image (see the Python reference).
    static func findCovered(_ px: (Int, Int) -> (Double, Double, Double), H: Int, open: [(x: Double, y: Double, type: Int)],
                            ox: Double, oy: Double) -> [(x: Double, y: Double, type: Int)] {
        let qw = 1180 / 4, qy0 = 560 / 4, qy1 = min(H, 1940) / 4
        let qh = qy1 - qy0
        var q = [Float](repeating: 0, count: qh * qw * 3)
        for yy in 0..<qh { for xx in 0..<qw {
            var r = 0.0, g = 0.0, b = 0.0
            for dy in 0..<4 { for dx in 0..<4 { let p = px(xx * 4 + dx, (yy + qy0) * 4 + dy); r += p.0; g += p.1; b += p.2 } }
            let i = (yy * qw + xx) * 3
            q[i] = Float(r / 16); q[i + 1] = Float(g / 16); q[i + 2] = Float(b / 16)
        } }
        let TH = 36, TW = 32
        let M = AlpacaData.mask, IC = AlpacaData.icon, TM = AlpacaData.templates
        let msum = M.filter { $0 }.count, isum = IC.filter { $0 }.count
        var occ = [Bool](repeating: false, count: qh * qw)
        func box(_ x: Double, _ y: Double) -> (Int, Int) { (Int((y / 4).rounded()) - 16 - qy0, Int((x / 4).rounded()) - 16) }
        func cover(_ y0: Int, _ x0: Int) {
            for r in 0..<TH { for c in 0..<TW where M[r * TW + c] {
                let yy = y0 + r, xx = x0 + c
                if yy >= 0 && yy < qh && xx >= 0 && xx < qw { occ[yy * qw + xx] = true }
            } }
        }
        for o in open { let b = box(o.x, o.y); cover(b.0, b.1) }
        var cands: [(Double, Double)] = []
        let j0 = Int(((boardY0 - oy) / AL.dy).rounded(.up)), j1 = Int((boardY1 - 60 - oy) / AL.dy)
        if j1 >= j0 {
            for j in j0...j1 {
                let k0 = Int(((60 - ox) / AL.dx).rounded(.up)), k1 = Int((1120 - ox) / AL.dx)
                for k in k0...k1 { cands.append((ox + Double(k) * AL.dx, oy + Double(j) * AL.dy)) }
            }
        }
        typealias R = (e: Float, x: Double, y: Double, type: Int, iv: Double, margin: Float)
        var cache: [Int: R?] = [:]
        var last: (Int, Int)? = nil
        var found: [(x: Double, y: Double, type: Int)] = []
        var gI = [Float](repeating: 0, count: 16), sTT = [Float](repeating: 0, count: 16), err = [Float](repeating: 0, count: 16)
        for _ in 0..<60 {
            var best: R? = nil
            for (ci, c) in cands.enumerated() {
                let (by, bx) = box(c.0, c.1)
                if by < 0 || bx < 0 || by + TH > qh || bx + TW > qw { continue }
                if let l = last, let r = cache[ci], by + TH <= l.0 || by >= l.0 + TH || bx + TW <= l.1 || bx >= l.1 + TW {
                    if let r, best == nil || r.e < best!.e { best = r }
                    continue
                }
                cache[ci] = .some(nil)
                var n = 0, ni = 0
                for t in 0..<16 { gI[t] = 0; sTT[t] = 0; err[t] = 0 }
                for r in 0..<TH { for cc in 0..<TW {
                    let mi = r * TW + cc
                    guard M[mi], !occ[(by + r) * qw + bx + cc] else { continue }
                    n += 1; if IC[mi] { ni += 1 }
                    let qi = ((by + r) * qw + bx + cc) * 3
                    for t in 0..<16 {
                        let ti = ((t * TH + r) * TW + cc) * 3
                        gI[t] += q[qi] * TM[ti] + q[qi + 1] * TM[ti + 1] + q[qi + 2] * TM[ti + 2]
                        sTT[t] += TM[ti] * TM[ti] + TM[ti + 1] * TM[ti + 1] + TM[ti + 2] * TM[ti + 2]
                    }
                } }
                if Double(n) < 0.22 * Double(msum) || (Double(ni) < 0.05 * Double(isum) && Double(n) < 0.5 * Double(msum)) { continue }
                var g = [Float](repeating: 0, count: 16)
                for t in 0..<16 { g[t] = min(0.55, max(0.33, gI[t] / max(sTT[t], 1))) }
                for r in 0..<TH { for cc in 0..<TW {
                    let mi = r * TW + cc
                    guard M[mi], !occ[(by + r) * qw + bx + cc] else { continue }
                    let qi = ((by + r) * qw + bx + cc) * 3
                    for t in 0..<16 {
                        let ti = ((t * TH + r) * TW + cc) * 3
                        err[t] += abs(q[qi] - g[t] * TM[ti]) + abs(q[qi + 1] - g[t] * TM[ti + 1]) + abs(q[qi + 2] - g[t] * TM[ti + 2])
                    }
                } }
                var bt = 0, e1 = Float.greatestFiniteMagnitude, e2 = Float.greatestFiniteMagnitude
                for t in 0..<16 {
                    let e = err[t] / Float(n * 3)
                    if e < e1 { e2 = e1; e1 = e; bt = t } else if e < e2 { e2 = e }
                }
                let r: R = (e1, c.0, c.1, bt, Double(ni) / Double(isum), e2 / max(e1, 1e-6))
                cache[ci] = .some(r)
                if best == nil || r.e < best!.e { best = r }
            }
            guard let b = best, b.e <= 24 else { break }
            let known = b.iv > 0.3 && b.margin > 1.35 && b.e <= 16
            found.append((b.x, b.y, known ? b.type : -1))
            let bb = box(b.x, b.y); cover(bb.0, bb.1)
            last = bb
            // drop this position and everything practically on top of it
            var keep: [(Double, Double)] = [], newCache: [Int: R?] = [:]
            for (ci, c) in cands.enumerated() where !(abs(c.0 - b.x) < 20 && abs(c.1 - b.y) < 20) {
                if let v = cache[ci] { newCache[keep.count] = v }
                keep.append(c)
            }
            cands = keep; cache = newCache
        }
        return found
    }
}
