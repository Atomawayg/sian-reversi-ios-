import Foundation

/// Reads WePlay Pool (8-ball). Calibrated on 1180×2556 screen recordings of the game (Oct 23 and Oct 25):
/// playing surface x 207.5…966.5, y 584…2135 (cushion noses), ball radius 23.5 px.
/// The felt colour depends on the theme and is learnt from the table (blue: hue ~200°, pink: ~338°); balls are far more saturated
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
    /// The felt changes colour with the table theme (blue, pink, purple…): its colour is learnt from the table
    /// itself every frame (see looksLikePool). Defaults: the blue table.
    static var feltH = 201.0, feltSLo = 0.42, feltSHi = 0.9, feltVLo = 0.45, feltVHi = 0.92
    @inline(__always) static func hueGap(_ a: Double, _ b: Double) -> Double { var d = abs(a - b).truncatingRemainder(dividingBy: 360); if d > 180 { d = 360 - d }; return d }
    @inline(__always) static func isFelt(_ c: (h: Double, s: Double, v: Double)) -> Bool {
        hueGap(c.h, feltH) < 16 && c.s > feltSLo && c.s < feltSHi && c.v > feltVLo && c.v < feltVHi
    }

    /// Quick check that the screen shows the pool table: six dark pockets where they belong and one even
    /// colour over most of the playing surface (whatever the theme). Learns that colour as the felt.
    static func looksLikePool(_ s: BoardReader.Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        func px(_ x: Double, _ y: Double) -> (Double, Double, Double) { s.avg(x * sx, y * sy, 3 * sx) }
        for (x, y) in [(203.0, 581.0), (975, 581), (203, 2140), (976, 2139), (178, 1360), (1000, 1360)] {
            let p = px(x, y)
            if (p.0 + p.1 + p.2) / 3 > 50 { return false }
        }
        var cs: [(h: Double, s: Double, v: Double)] = []
        for y in [700.0, 1000, 1300, 1600, 1900, 2050] { for x in [300.0, 480, 700, 880] { cs.append(hsv(px(x, y))) } }
        // the colour most samples agree on (balls, the cue stick and banners cover only a few)
        func agree(_ c: (h: Double, s: Double, v: Double)) -> [Int] { cs.indices.filter { hueGap(cs[$0].h, c.h) < 12 && cs[$0].s > 0.2 && cs[$0].v > 0.3 } }
        guard let k = cs.indices.max(by: { agree(cs[$0]).count < agree(cs[$1]).count }) else { return false }
        let inl = agree(cs[k])
        if Double(inl.count) < Double(cs.count) * 0.7 { return false }
        var sn = 0.0, cn = 0.0
        for i in inl { sn += sin(cs[i].h * Double.pi / 180); cn += cos(cs[i].h * Double.pi / 180) }
        var h0 = atan2(sn, cn) * 180 / Double.pi; if h0 < 0 { h0 += 360 }
        let ss = inl.map { cs[$0].s }, vv = inl.map { cs[$0].v }
        let lo = max(0.25, vv.min()! - 0.17), hi = min(0.99, vv.max()! + 0.08)
        let sLo = max(0.15, ss.min()! - 0.15), sHi = min(0.92, ss.max()! + 0.12)
        // the side rails are not felt (a board game filling the screen with one colour is)
        var rail = 0
        for (x, y) in [(150.0, 1000.0), (1030, 1000), (150, 1700), (1030, 1700)] {
            let c = hsv(px(x, y))
            if !(hueGap(c.h, h0) < 16 && c.s > sLo && c.s < sHi && c.v > lo && c.v < hi) { rail += 1 }
        }
        if rail < 2 { return false }
        feltH = h0; feltSLo = sLo; feltSHi = sHi; feltVLo = lo; feltVHi = hi
        return true
    }

    struct Ball { var x: Double; var y: Double; var id: Int; var rimWhite: Double }
    /// the last full reading (balls and a colour sample at each centre), and where the aim circle was
    static var cache: (balls: [Ball], clean: Bool, spots: [(x: Double, y: Double, r: Double, g: Double, b: Double)], at: Double)? = nil
    static var lastAim: (Double, Double)? = nil
    static var barCache: (group: Int, mine: Int, opp: Int, at: Double)? = nil
    static var lastTurnSeen = 0.0
    static var lastReuse = false   // the last frame's table matched the one before (nothing moving)
    static var lastDir: (ball: Int, angle: Double)? = nil

    static func read(_ s: BoardReader.Sampler) -> BoardMessage {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        @inline(__always) func at(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int((x * sx).rounded()))), min(s.h - 1, max(0, Int((y * sy).rounded()))))
        }
        var cells = [Int](repeating: 0, count: PoolCodec.count)

        // turn: the timer ring around your avatar (top-left). It runs down as your time goes and may change colour,
        // so any bit of coloured ring counts (on the other player's turn it is a plain white border); a short hold
        // bridges the last moment before it is empty
        var ring = 0
        for k in 0..<72 {
            let a = Double(k) * Double.pi / 36
            for r in [64.0, 66] {
                let c = hsv(at(98 + r * cos(a), 365 + r * sin(a)))
                if c.s > 0.45 && c.v > 0.5 && !(c.h > 180 && c.h < 260) { ring += 1; break }
            }
        }
        let tNow = Date().timeIntervalSince1970
        if ring >= 2 { lastTurnSeen = tNow }
        let myTurn = ring >= 2 || tNow - lastTurnSeen < 0.6

        // group: the bars show the balls each player still has to pot (they only change after a shot, so while
        // the table stands still the last reading of them is reused)
        let now = Date().timeIntervalSince1970
        var group = 0
        if let b = barCache, now - b.at < 0.5, lastReuse {
            group = b.group; cells[PoolCodec.myLeft] = b.mine; cells[PoolCodec.oppLeft] = b.opp
        } else {
            let mine = barIcons(s, xs: (0..<7).map { 206 + 46.8 * Double($0) }, y: 398)
            let opp = barIcons(s, xs: (0..<7).map { 697 + 47 * Double($0) }, y: 397)
            // the 8 appears in a bar near the end (with a player's last ball, or alone): it says nothing about
            // solids or stripes, so leave it out; a bar holding only the 8 means that player is on the 8
            func avg(_ a: [Double]) -> Double { a.reduce(0, +) / Double(max(1, a.count)) }
            let mineC = mine.filter { !$0.black }.map { $0.ratio }, oppC = opp.filter { !$0.black }.map { $0.ratio }
            // your own bar decides (the opponent's bar is usually under the floating window): stripes show white caps
            if !mine.isEmpty && mineC.isEmpty { group = 3 }
            else if !mineC.isEmpty { group = avg(mineC) < 0.63 ? 2 : 1 }
            cells[PoolCodec.myLeft] = min(13, mineC.count); cells[PoolCodec.oppLeft] = min(13, oppC.count)
            barCache = (group, cells[PoolCodec.myLeft], cells[PoolCodec.oppLeft], now)
        }

        // fast path while you aim: nothing on the table moves, so only check every ball is still where it was
        var balls: [Ball] = []
        var clean = false
        var reuse = false
        if let c = cache, now - c.at < 1.0, !c.spots.isEmpty {
            reuse = c.spots.allSatisfy { sp in
                let p = s.avg(sp.x * sx, sp.y * sy, 4 * sx)
                return !isFelt(hsv(p)) && abs(p.0 - sp.r) + abs(p.1 - sp.g) + abs(p.2 - sp.b) < 90
            }
            if reuse { balls = c.balls; clean = c.clean }
        }
        lastReuse = reuse
        if !reuse {
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
            if picked.count >= 80 { break }   // banners ("Your turn") also leave non-felt blobs; the roundness test drops them
            if picked.contains(where: { ($0.0 - Double(c.i)) * ($0.0 - Double(c.i)) + ($0.1 - Double(c.j)) * ($0.1 - Double(c.j)) < sup * sup }) { continue }
            picked.append((Double(c.i), Double(c.j)))
        }

        // 2) refine each centre at full resolution and identify the ball
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
        clean = balls.count <= 16
        if !balls.contains(where: { $0.id == 0 }), let k = balls.indices.filter({ balls[$0].id >= 9 || balls[$0].id == 0 }).max(by: { balls[$0].rimWhite < balls[$1].rimWhite }),
           balls[k].rimWhite > 0.85 {
            balls[k].id = 0
        }
        var seen = Set<Int>()
        for b in balls { if !seen.insert(b.id).inserted { clean = false } }
        cache = (balls, clean, balls.map { b in let p = s.avg(b.x * sx, b.y * sy, 4 * sx); return (b.x, b.y, p.0, p.1, p.2) }, now)
        }

        // power bar (right edge): a coloured fill runs down from y 878 as you pull; full at y 1689
        var fillBottom = -1.0
        var yy = 875.0
        while yy <= 1692 {
            let p = at(1080, yy)
            if max(p.0, p.1) - p.2 > 80 && max(p.0, p.1, p.2) > 150 { fillBottom = yy }
            yy += 3
        }
        var pulling = false
        if fillBottom > 890 {
            let pct = max(0, min(100, Int(((fillBottom - 878) / (1689 - 878) * 100).rounded())))
            cells[PoolCodec.power] = pct / 14; cells[PoolCodec.power + 1] = pct % 14
            pulling = true
        }
        // 4) the game's aim circle (hollow white ring of ball size) while you aim: near where it was first.
        // While the power bar is pulled the cue can't turn and the game dims its lines: keep the last aim.
        var aim: (Double, Double)? = nil
        var held = false
        if myTurn && pulling, let l = lastAim { aim = l; held = true }
        else if myTurn {
            let centres = balls.map { ($0.x, $0.y) }
            let cue = balls.first(where: { $0.id == 0 }).map { ($0.x, $0.y) }
            if let l = lastAim { aim = findAimCircle(at, around: l, balls: centres, cue: cue) }
            if aim == nil { aim = findAimCircle(at, balls: centres, cue: cue) }
        }
        lastAim = aim

        // 5) the game's own line for where the hit ball goes (more exact than working it out from positions)
        var objDir: Double? = nil
        if held, let ld = lastDir {
            objDir = ld.angle
        } else if let a = aim, let t = balls.filter({ $0.id != 0 }).min(by: { hypot($0.x - a.0, $0.y - a.1) < hypot($1.x - a.0, $1.y - a.1) }),
           hypot(t.x - a.0, t.y - a.1) < 2 * R + 12 {
            let u0 = atan2(t.y - a.1, t.x - a.0)
            // count white along each direction from the ball; near the last direction first (it moves little per frame)
            func scan(_ c0: Double, _ steps: Int) -> Double? {
                var counts: [(Int, Double)] = []
                var best = 0
                for k in -steps...steps {
                    let th = c0 + Double(k) * 0.25 * Double.pi / 180
                    var c = 0
                    var r = R + 4
                    while r <= R + 150 {
                        let q = hsv(at(t.x + r * cos(th), t.y + r * sin(th)))
                        if q.s < 0.25 && q.v > 0.85 { c += 1 }
                        r += 2
                    }
                    counts.append((c, th)); best = max(best, c)
                }
                // the peak must not sit on the edge of a narrow window (the line may be just outside it)
                guard best >= 8 else { return nil }
                let top = counts.filter { $0.0 >= best - 1 }.map { $0.1 }
                if steps < 120, let f = top.first, let l = top.last, abs(f - (c0 - Double(steps) * 0.25 * Double.pi / 180)) < 1e-9 || abs(l - (c0 + Double(steps) * 0.25 * Double.pi / 180)) < 1e-9 { return nil }
                return top.reduce(0, +) / Double(top.count)
            }
            if let ld = lastDir, ld.ball == t.id { objDir = scan(ld.angle, 32) }
            if objDir == nil { objDir = scan(u0, 120) }
            if let d = objDir { lastDir = (ball: t.id, angle: d) } else { lastDir = nil }
        } else {
            lastDir = nil
        }
        if let d = objDir {
            var deg = d * 180 / Double.pi; while deg < 0 { deg += 360 }; while deg >= 360 { deg -= 360 }
            let q = min(2519, Int((deg * 7).rounded()))
            cells[PoolCodec.objDir] = q / 196; cells[PoolCodec.objDir + 1] = (q / 14) % 14; cells[PoolCodec.objDir + 2] = q % 14
        }

        if clean { for b in balls where b.id >= 0 && b.id <= 15 { cells[PoolCodec.balls + 7 * b.id] = 1; PoolCodec.put(&cells, PoolCodec.balls + 7 * b.id + 1, b.x, b.y) } }
        if let a = aim { PoolCodec.put(&cells, PoolCodec.aim, a.0, a.1) }
        cells[PoolCodec.flags] = (clean ? 1 : 0) | (aim != nil ? 2 : 0) | (pulling ? 4 : 0) | (objDir != nil ? 8 : 0)
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
    static func barIcons(_ s: BoardReader.Sampler, xs: [Double], y: Double) -> [(ratio: Double, black: Bool)] {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var out: [(ratio: Double, black: Bool)] = []
        let r = 19.0
        for cx in xs {
            var sumS = 0.0, sumV = 0.0, sumV2 = 0.0, n = 0.0, capS = 0.0, capN = 0.0, bandS = 0.0, bandN = 0.0
            var ringS: [Double] = [], ringV: [Double] = []
            var dy = -r
            while dy <= r {
                var dx = -r
                while dx <= r {
                    let dd = (dx * dx + dy * dy).squareRoot()
                    if dd <= 0.85 * r {
                        let c = hsv(s.get(Int((cx + dx) * sx), Int((y + dy) * sy)))
                        if dd > 0.55 * r { ringS.append(c.s); ringV.append(c.v) }   // the ball's colour, around its number
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
            ringS.sort(); ringV.sort()
            let mS = ringS.isEmpty ? 1 : ringS[ringS.count / 2], mV = ringV.isEmpty ? 1 : ringV[ringV.count / 2]
            // the 8 is black: dark AND colourless around its number (a dimmed maroon 7 is dark but saturated: 0.62)
            out.append((ratio, mV < 0.3 && mS < 0.35))
        }
        return out
    }

    /// Share of points on the straight path cue ball → ring that are white (the game's aim line); 1 when they're too close for a line.
    static func lineSupport(_ at: (Double, Double) -> (Double, Double, Double), from c: (Double, Double), to p: (Double, Double)) -> Double {
        let dx = p.0 - c.0, dy = p.1 - c.1, l = hypot(dx, dy)
        if l < 3 * R + 12 { return 1 }
        let ux = dx / l, uy = dy / l
        var hit = 0, n = 0
        var t = R + 6
        while t < l - R - 6 {
            n += 1
            let px = c.0 + ux * t, py = c.1 + uy * t
            for o in [-2.0, -1, 0, 1, 2] {
                let q = hsv(at(px - uy * o, py + ux * o))
                if q.s < 0.22 && q.v > 0.85 { hit += 1; break }
            }
            t += 6
        }
        return n == 0 ? 1 : Double(hit) / Double(n)
    }

    /// Centre of the hollow white ball-sized ring the game draws where the cue ball will hit.
    static func findAimCircle(_ at: (Double, Double) -> (Double, Double, Double), around: (Double, Double)? = nil,
                               balls: [(Double, Double)] = [], cue: (Double, Double)? = nil) -> (Double, Double)? {
        let g = 2.0
        let nx = Int((X1 - X0) / g) + 1, ny = Int((Y1 - Y0) / g) + 1
        // search the whole table, or only a window around the last spot (fast while you turn the cue)
        var wi0 = 0, wi1 = nx - 1, wj0 = 0, wj1 = ny - 1
        if let c = around {
            let w = 140.0 / g
            wi0 = max(0, Int((c.0 - X0) / g - w)); wi1 = min(nx - 1, Int((c.0 - X0) / g + w))
            wj0 = max(0, Int((c.1 - Y0) / g - w)); wj1 = min(ny - 1, Int((c.1 - Y0) / g + w))
        }
        var white = [UInt8](repeating: 0, count: nx * ny)
        for j in wj0...wj1 { for i in wi0...wi1 {
            let c = hsv(at(X0 + Double(i) * g, Y0 + Double(j) * g))
            if c.s < 0.22 && c.v > 0.85 { white[j * nx + i] = 1 }
        } }
        var ring: [(Int, Int)] = [], core: [(Int, Int)] = []
        for k in 0..<40 { let a = Double(k) * Double.pi / 20; ring.append((Int(((R - 1.5) * cos(a) / g).rounded()), Int(((R - 1.5) * sin(a) / g).rounded()))) }
        for dj in stride(from: -8, through: 8, by: 2) { for di in stride(from: -8, through: 8, by: 2) where di * di + dj * dj <= 64 { core.append((di, dj)) } }   // inside, ≤ 16 px (grid units of 2 px)
        let m = Int(R / g) + 2   // ring reach; the core (≤ 8) is inside it
        var cands: [(Double, Int, Int)] = []
        let si0 = max(m, wi0 + m), si1 = min(nx - m - 1, wi1 - m), sj0 = max(m, wj0 + m), sj1 = min(ny - m - 1, wj1 - m)
        if si0 > si1 || sj0 > sj1 { return nil }
        for j in sj0...sj1 { for i in si0...si1 {
            var rc = 0
            for o in ring where white[(j + o.1) * nx + i + o.0] == 1 { rc += 1 }
            if rc < 16 { continue }
            var cc = 0
            for o in core where white[(j + o.1) * nx + i + o.0] == 1 { cc += 1 }
            let sc = Double(rc) / Double(ring.count) - Double(cc) / Double(core.count)
            if sc > 0.32 { cands.append((sc, i, j)) }
        } }
        // The white of a striped ball, the glow round a ball you may hit, or the cue ball itself can look like the ring.
        // The real ring is never on a ball, and the game draws a white line to it from the cue ball.
        cands.sort { $0.0 > $1.0 }
        var tried: [(Double, Double)] = []
        var best = 0.0, bi = 0, bj = 0
        for c in cands {
            let x = X0 + Double(c.1) * g, y = Y0 + Double(c.2) * g
            if balls.contains(where: { hypot($0.0 - x, $0.1 - y) < R + 8 }) { continue }
            if tried.contains(where: { hypot($0.0 - x, $0.1 - y) < 20 }) { continue }
            tried.append((x, y))
            var line = 1.0
            if let q = cue { line = lineSupport(at, from: q, to: (x, y)); if line < 0.6 { if tried.count >= 10 { break }; continue } }
            if c.0 + line > best { best = c.0 + line; bi = c.1; bj = c.2 }
            if tried.count >= 10 { break }
        }
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
