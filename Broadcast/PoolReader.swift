import Foundation

/// Reads WePlay Pool (8-ball). Calibrated on a 1180×2556 screen recording of the game:
/// playing surface x 207.5…966.5, y 584…2135 (cushion noses), ball radius 23.5 px.
/// Measured: felt hue 190–210°, saturation 0.55–0.84, brightness 0.59–0.85; balls are far more saturated
/// or white/black; a striped ball always shows white near its rim (≥ 0.33 of the rim) and a solid doesn't (≤ 0.12).
enum PoolReader {
    static let R = 23.5
    static let X0 = 207.5, X1 = 966.5, Y0 = 584.0, Y1 = 2135.0

    @inline(__always) static func hsv(_ p: (Double, Double, Double)) -> (h: Double, s: Double, v: Double) {
        let r = p.0 / 255, g = p.1 / 255, b = p.2 / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let s = mx > 1e-6 ? d / mx : 0
        var h = 0.0
        if d > 1e-6 {
            if mx == b { h = 240 + 60 * (r - g) / d } else if mx == g { h = 120 + 60 * (b - r) / d } else { h = (60 * (g - b) / d).truncatingRemainder(dividingBy: 360); if h < 0 { h += 360 } }
        }
        return (h, s, mx)
    }
    @inline(__always) static func isFelt(_ c: (h: Double, s: Double, v: Double)) -> Bool {
        c.h > 183 && c.h < 213 && c.s > 0.42 && c.s < 0.9 && c.v > 0.45 && c.v < 0.92
    }

    /// Quick check that the screen shows the pool table (felt in the middle, wood rails, dark pockets).
    static func looksLikePool(_ s: BoardReader.Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        func px(_ x: Double, _ y: Double) -> (Double, Double, Double) { s.avg(x * sx, y * sy, 3 * sx) }
        var felt = 0
        for (x, y) in [(400.0, 700.0), (780, 700), (400, 2000), (780, 2000), (300, 1360), (880, 1360)] where isFelt(hsv(px(x, y))) { felt += 1 }
        let pocket = px(203, 581), pocket2 = px(976, 2139)
        let dark = (pocket.0 + pocket.1 + pocket.2) / 3 < 45 && (pocket2.0 + pocket2.1 + pocket2.2) / 3 < 45
        let wood = px(590, 540)
        let woody = wood.0 > wood.2 + 40 && wood.0 > 120
        return felt >= 5 && dark && woody
    }

    struct Ball { var x: Double; var y: Double; var id: Int; var rimWhite: Double }

    static func read(_ s: BoardReader.Sampler) -> BoardMessage {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        @inline(__always) func at(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int((x * sx).rounded()))), min(s.h - 1, max(0, Int((y * sy).rounded()))))
        }
        var cells = [Int](repeating: 0, count: PoolCodec.count)

        // turn: green ring around your avatar (top-left)
        var green = 0
        for k in 0..<36 {
            let a = Double(k) * Double.pi / 18
            let p = at(98 + 64 * cos(a), 365 + 64 * sin(a))
            if p.1 > 153 && p.1 - p.0 > 76 && p.1 - p.2 > 25 { green += 1 }
        }
        let myTurn = green >= 8

        // group: the bars show the balls each player still has to pot
        let mine = barIcons(s, xs: (0..<7).map { 206 + 46.8 * Double($0) }, y: 398)
        let opp = barIcons(s, xs: (0..<7).map { 697 + 47 * Double($0) }, y: 397)
        var group = 0
        func avg(_ a: [Double]) -> Double { a.reduce(0, +) / Double(max(1, a.count)) }
        if !mine.isEmpty && !opp.isEmpty { group = avg(mine) < avg(opp) ? 2 : 1 }   // the bar with white caps is stripes
        else if !mine.isEmpty { group = avg(mine) < 0.63 ? 2 : 1 }
        else if !opp.isEmpty { group = 3 }   // opponent still has balls, you have none left: play the 8
        cells[PoolCodec.myLeft] = min(13, mine.count); cells[PoolCodec.oppLeft] = min(13, opp.count)

        // 1) coarse felt grid → candidate ball centres
        let g = 3.0
        let nx = Int((X1 - X0) / g) + 1, ny = Int((Y1 - Y0) / g) + 1
        var fg = [UInt8](repeating: 0, count: nx * ny)
        for j in 0..<ny { for i in 0..<nx {
            if !isFelt(hsv(at(X0 + Double(i) * g, Y0 + Double(j) * g))) { fg[j * nx + i] = 1 }
        } }
        var integral = [Int32](repeating: 0, count: (nx + 1) * (ny + 1))
        for j in 0..<ny {
            var row: Int32 = 0
            for i in 0..<nx { row += Int32(fg[j * nx + i]); integral[(j + 1) * (nx + 1) + i + 1] = integral[j * (nx + 1) + i + 1] + row }
        }
        func boxSum(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) -> Int32 {   // inclusive cell range
            let a = max(0, i0), b = max(0, j0), c = min(nx - 1, i1), d = min(ny - 1, j1)
            if c < a || d < b { return 0 }
            return integral[(d + 1) * (nx + 1) + c + 1] - integral[b * (nx + 1) + c + 1] - integral[(d + 1) * (nx + 1) + a] + integral[b * (nx + 1) + a]
        }
        let half = Int(((R - 2) / 2.0.squareRoot()) / g)   // square inside the ball
        let area = Double((2 * half + 1) * (2 * half + 1))
        var cands: [(score: Double, i: Int, j: Int)] = []
        let mi = Int((R - 2) / g), mj = Int((R - 2) / g)
        for j in mj..<(ny - mj) { for i in mi..<(nx - mi) where fg[j * nx + i] == 1 {
            let sc = Double(boxSum(i - half, j - half, i + half, j + half)) / area
            if sc >= 0.95 { cands.append((sc, i, j)) }
        } }
        cands.sort { $0.score > $1.score }
        var picked: [(Double, Double)] = []
        let sup = 40.0 / g
        for c in cands {
            if picked.count >= 40 { break }
            if picked.contains(where: { ($0.0 - Double(c.i)) * ($0.0 - Double(c.i)) + ($0.1 - Double(c.j)) * ($0.1 - Double(c.j)) < sup * sup }) { continue }
            picked.append((Double(c.i), Double(c.j)))
        }

        // 2) refine each centre at full resolution and identify the ball
        var balls: [Ball] = []
        for p in picked {
            var cx = X0 + p.0 * g, cy = Y0 + p.1 * g
            for _ in 0..<3 {
                var sxp = 0.0, syp = 0.0, n = 0.0
                var y = cy - R + 1
                while y <= cy + R - 1 {
                    var x = cx - R + 1
                    while x <= cx + R - 1 {
                        let dx = x - cx, dy = y - cy
                        if dx * dx + dy * dy <= (R - 1) * (R - 1) && !isFelt(hsv(at(x, y))) { sxp += x; syp += y; n += 1 }
                        x += 2
                    }
                    y += 2
                }
                if n > 10 { cx = sxp / n; cy = syp / n }
            }
            guard let id = classify(cx, cy, at) else { continue }
            // round: clear edge against its surroundings most of the way around (rejects overlays, the cue stick, text)
            var edge = 0
            for k in 0..<24 {
                let a = Double(k) * Double.pi / 12
                let pi = at(cx + (R - 5) * cos(a), cy + (R - 5) * sin(a)), po = at(cx + (R + 5) * cos(a), cy + (R + 5) * sin(a))
                if abs(pi.0 - po.0) + abs(pi.1 - po.1) + abs(pi.2 - po.2) > 64 { edge += 1 }
            }
            if edge < 14 { continue }
            balls.append(Ball(x: cx, y: cy, id: id.id, rimWhite: id.rim))
        }

        // 3) consistency: one cue ball (the whitest), every number at most once, at most 16 balls
        var clean = balls.count <= 16
        if !balls.contains(where: { $0.id == 0 }), let k = balls.indices.filter({ balls[$0].id >= 9 || balls[$0].id == 0 }).max(by: { balls[$0].rimWhite < balls[$1].rimWhite }),
           balls[k].rimWhite > 0.85 {
            balls[k].id = 0
        }
        var seen = Set<Int>()
        for b in balls { if !seen.insert(b.id).inserted { clean = false } }

        // 4) the game's aim circle (hollow white ring of ball size) while you aim
        var aim: (Double, Double)? = nil
        if myTurn { aim = findAimCircle(at) }

        if clean { for b in balls where b.id >= 0 && b.id <= 15 { cells[PoolCodec.balls + 7 * b.id] = 1; PoolCodec.put(&cells, PoolCodec.balls + 7 * b.id + 1, b.x, b.y) } }
        if let a = aim { PoolCodec.put(&cells, PoolCodec.aim, a.0, a.1) }
        cells[PoolCodec.flags] = (clean ? 1 : 0) | (aim != nil ? 2 : 0)
        return BoardMessage(valid: true, game: .pool, cells: cells, me: group, myTurn: myTurn)
    }

    /// Ball number from colour; 0 = cue, 8 = eight; nil = not a ball.
    static func classify(_ cx: Double, _ cy: Double, _ at: (Double, Double) -> (Double, Double, Double)) -> (id: Int, rim: Double)? {
        var white = 0, col = 0, dark = 0, inner = 0, rimWhite = 0, rim = 0, coreFelt = 0, core = 0
        var hues: [Double] = [], vals: [Double] = [], sats: [Double] = []
        var y = -R
        while y <= R {
            var x = -R
            while x <= R {
                let d = (x * x + y * y).squareRoot()
                if d <= 0.85 * R {
                    let c = hsv(at(cx + x, cy + y))
                    let isW = c.s < 0.25 && c.v > 0.75, isC = c.s > 0.5 && c.v > 0.3
                    if d <= 0.8 * R {
                        inner += 1
                        if isW { white += 1 }
                        if isC { col += 1; hues.append(c.h); vals.append(c.v); sats.append(c.s) }
                        if c.v < 0.25 { dark += 1 }
                    }
                    if d > 0.55 * R { rim += 1; if isW { rimWhite += 1 } }
                    if d <= 0.5 * R { core += 1; if isFelt(c) { coreFelt += 1 } }
                }
                x += 1.5
            }
            y += 1.5
        }
        let n = Double(max(1, inner))
        let wf = Double(white) / n, cf = Double(col) / n, df = Double(dark) / n
        let rw = Double(rimWhite) / Double(max(1, rim))
        if cf < 0.05 && wf > 0.85 { return (0, wf) }
        if df > 0.4 { return (8, rw) }
        if cf < 0.1 || Double(coreFelt) / Double(max(1, core)) > 0.2 { return nil }
        func median(_ a: [Double]) -> Double { let s = a.sorted(); return s[s.count / 2] }
        if median(sats) < 0.72 { return nil }   // cue-stick wood, translucent overlays
        let m = median(hues), mv = median(vals)
        var base: Int
        if m < 12 || m > 340 { base = mv < 0.72 ? 7 : 3 }
        else if m < 38 { base = 5 }
        else if m < 75 { base = 1 }
        else if m < 170 { base = 6 }
        else if m < 250 { base = 2 }
        else { base = 4 }
        return (rw > 0.22 ? base + 8 : base, rw)
    }

    /// Cap/band saturation ratio per icon (stripes ≈ 0.42–0.56: white caps; solids ≈ 0.70–0.84); empty slots left out.
    static func barIcons(_ s: BoardReader.Sampler, xs: [Double], y: Double) -> [Double] {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var out: [Double] = []
        let r = 19.0
        for cx in xs {
            var sumS = 0.0, sumV = 0.0, sumV2 = 0.0, n = 0.0, capS = 0.0, capN = 0.0, bandS = 0.0, bandN = 0.0
            var dy = -r
            while dy <= r {
                var dx = -r
                while dx <= r {
                    if (dx * dx + dy * dy).squareRoot() <= 0.85 * r {
                        let c = hsv(s.get(Int((cx + dx) * sx), Int((y + dy) * sy)))
                        sumS += c.s; sumV += c.v; sumV2 += c.v * c.v; n += 1
                        if abs(dy) >= 0.6 * r { capS += c.s; capN += 1 }
                        if abs(dy) <= 0.3 * r && abs(dx) >= 0.45 * r { bandS += c.s; bandN += 1 }
                    }
                    dx += 1
                }
                dy += 1
            }
            let meanS = sumS / n, meanV = sumV / n, sdV = max(0, sumV2 / n - meanV * meanV).squareRoot()
            if meanS < 0.2 && sdV < 0.06 { continue }   // empty grey slot
            let ratio = (capS / max(1, capN)) / max(0.01, bandS / max(1, bandN))
            out.append(ratio)
        }
        return out
    }

    /// Centre of the hollow white ball-sized ring the game draws where the cue ball will hit.
    static func findAimCircle(_ at: (Double, Double) -> (Double, Double, Double)) -> (Double, Double)? {
        let g = 2.0
        let nx = Int((X1 - X0) / g) + 1, ny = Int((Y1 - Y0) / g) + 1
        var white = [UInt8](repeating: 0, count: nx * ny)
        for j in 0..<ny { for i in 0..<nx {
            let c = hsv(at(X0 + Double(i) * g, Y0 + Double(j) * g))
            if c.s < 0.22 && c.v > 0.85 { white[j * nx + i] = 1 }
        } }
        var ring: [(Int, Int)] = [], core: [(Int, Int)] = []
        for k in 0..<40 { let a = Double(k) * Double.pi / 20; ring.append((Int(((R - 1.5) * cos(a) / g).rounded()), Int(((R - 1.5) * sin(a) / g).rounded()))) }
        for dj in stride(from: -8, through: 8, by: 2) { for di in stride(from: -8, through: 8, by: 2) where di * di + dj * dj <= 64 { core.append((di, dj)) } }   // inside, ≤ 16 px (grid units of 2 px)
        let m = Int(R / g) + 2   // ring reach; the core (≤ 8) is inside it
        var best = 0.0, bi = 0, bj = 0
        for j in m..<(ny - m) { for i in m..<(nx - m) {
            var rc = 0
            for o in ring where white[(j + o.1) * nx + i + o.0] == 1 { rc += 1 }
            if rc < 16 { continue }
            var cc = 0
            for o in core where white[(j + o.1) * nx + i + o.0] == 1 { cc += 1 }
            let sc = Double(rc) / Double(ring.count) - Double(cc) / Double(core.count)
            if sc > best { best = sc; bi = i; bj = j }
        } }
        guard best > 0.32 else { return nil }
        // refine to a pixel
        var bx = X0 + Double(bi) * g, by = Y0 + Double(bj) * g, bs = -1.0
        for dy in stride(from: -2.0, through: 2.0, by: 1) { for dx in stride(from: -2.0, through: 2.0, by: 1) {
            var rc = 0
            for k in 0..<64 {
                let a = Double(k) * Double.pi / 32
                let c = hsv(at(X0 + Double(bi) * g + dx + (R - 1.5) * cos(a), Y0 + Double(bj) * g + dy + (R - 1.5) * sin(a)))
                if c.s < 0.22 && c.v > 0.85 { rc += 1 }
            }
            if Double(rc) > bs { bs = Double(rc); bx = X0 + Double(bi) * g + dx; by = Y0 + Double(bj) * g + dy }
        } }
        return (bx, by)
    }
}
