import Foundation

/// 8-ball shot chooser and aim judge for WePlay Pool. Coordinates are screen pixels of a 1180×2556 screen
/// (see PoolReader). Straight-in and one-cushion bank shots, ghost-ball aiming, clear paths, pocket entry
/// angles, how much aiming error a shot forgives, and the power it needs.
enum PoolEngine {
    static let R = 23.5
    static let xMin = 207.5 + R, xMax = 966.5 - R, yMin = 584 + R, yMax = 2135 - R
    static let midX = 587.0, midY = 1359.5
    struct Pocket { let name: String; let x: Double; let y: Double; let side: Bool }
    static let pockets = [
        Pocket(name: "มุมซ้ายบน", x: 203, y: 581, side: false), Pocket(name: "มุมขวาบน", x: 975, y: 581, side: false),
        Pocket(name: "กลางซ้าย", x: 187, y: 1360, side: true), Pocket(name: "กลางขวา", x: 992, y: 1360, side: true),
        Pocket(name: "มุมซ้ายล่าง", x: 203, y: 2140, side: false), Pocket(name: "มุมขวาล่าง", x: 976, y: 2139, side: false)]

    // Measured on the Oct 25 recording (cue ball tracked at 60 fps over five of your shots):
    // the cue ball leaves at about 4150 px/s × power (51 % → 2070, 54 % → 2230, 63 % → 2700 px/s),
    // and slows by (100 + 1.4·v) px/s every second (fast balls lose speed quickly, slow ones roll on).
    // Refit Oct 26 on where 24 cue balls really came to rest (positions only, no clock): 6000 px/s at full power
    static let fullSpeed = 4480.0
    /// Measured on Atom's in-app clip (Oct 26, 60 fps, exact frame times) and the old 60 fps recording: the cue ball
    /// leaves at about 50 px/s per power % minus 520 (25 % → ~730, 35 % → ~1230, 100 % → ~4480), not in proportion.
    static func speedAt(power p: Double) -> Double { max(40, 50 * p - 520) }
    static func powerFor(speed v: Double) -> Double { (v + 520) / 50 }
    // Oct 25 logs (rolling balls, 36 shots): slow balls coast much further than (100 + 1.4·v) allowed, and full-power
    // runs went ~2300 px with two cushions; the low-speed part is eased to 30 (only total distances, not times, could be
    // trusted from the log)
    // clip: a struck ball first skids, losing ~2040 px/s every second until it is down to ~80 % of its start pace,
    // then rolls on, losing only (3 + 0.57·v) px/s every second
    static let slideDecel = 2040.0, slideTo = 0.8
    static let decel0 = 3.0, decelV = 0.57
    /// the cue ball rolls into the hit (a centre hit in this game is a rolling ball): afterwards it keeps this share of
    /// the pace along the hit ball's line on top of the tangent pace (2/7, as for a rolling ball; a full hit follows through)
    static let follow = 0.25   // 40 of your shots in the logs (where the cue ball really came to rest): 0.25 halves the miss of 0.15

    struct Ball: Equatable { var id: Int; var x: Double; var y: Double }
    struct Shot: Equatable {
        var ball: Int; var pocket: Int
        var cueX: Double; var cueY: Double            // where the cue ball is (or should be placed)
        var ghostX: Double; var ghostY: Double        // where the cue ball must be when it hits
        var cut: Double; var tolerance: Double        // degrees
        var scratch: Bool; var power: String; var placed: Bool
        var bank = false                              // object ball goes off one cushion first
        var objLen = 0.0                              // how far the object ball rolls to the pocket
        var powerPct = 50                             // power bar % to use
    }

    static func legal(group: Int) -> Set<Int> {
        switch group {
        case 1: return Set(1...7)
        case 2: return Set(9...15)
        case 3: return [8]
        default: return Set(1...15).subtracting([8])
        }
    }

    @inline(__always) static func clear(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ balls: [Ball], skip: Int, gap: Double) -> Bool {
        let dx = bx - ax, dy = by - ay, l2 = max(dx * dx + dy * dy, 1e-9)
        for b in balls where b.id != skip && b.id != 0 {
            let t = max(0, min(1, ((b.x - ax) * dx + (b.y - ay) * dy) / l2))
            let px = ax + t * dx - b.x, py = ay + t * dy - b.y
            if px * px + py * py < gap * gap { return false }
        }
        return true
    }

    /// Off a cushion: measured on the Oct 25 bank recording, a ball comes off flatter than it went in
    /// (tan of the angle from the cushion's normal grows by about 1.28), and keeps about half its speed.
    /// Oct 25 log, nine cushion hits read off rolling balls: the ball keeps ~85 % of its pace along the cushion and
    /// about 1/1.45 of that into it (tan of the angle from the normal grows ×1.45; fast hits 1.36–1.55, slow up to 2).
    /// "Sure" shots must still drop with this anywhere in `flatRange`.
    /// Measured on 8 clean object-ball cushion hits in Atom's in-app clips (60 fps): the ball keeps ~0.8 of its pace
    /// along the cushion and ~0.43 of its pace into it, so tan(out) ≈ 1.85·tan(in) — scatter about ±6° per cushion
    /// (a ball still skidding comes off differently from a rolling one). `flat` scales the ratio; "sure" banks must
    /// drop for any ratio 1.55…2.2 (`flatRange` 0.84…1.19).
    static let bounceFlatten = 1.0
    static let flatRange = [0.84, 1.19]
    static let keepAlong = 0.8
    static let keepInto = 0.8 / 1.85
    /// The direction off a cushion. 34 clean object-ball bounces read off the logs (Oct 25–26): tan(out) ≈ 1.40·tan(in)
    /// + 0.11 — shallow hits come off ~1.75× flatter, steep ones only ~1.3× (the old flat 1.85 sent banks ~5° wide).
    /// Pace kept: `keepAlong`/`keepInto` as before. `flat` scales tan(out).
    static let bounceA = 1.5, bounceB = 0.0
    /// 3.28: 50 clean object-ball bounces (all logs + the 09:27 clip at 60 fps): how much flatter the ball comes off,
    /// tan(out)/tan(in), by the angle it comes in at (degrees from square-on) — most around 20–30°, less when steep
    /// or square — and a ball that hits the cushion in its first 140 px (still sliding) comes off ~10 % less flat,
    /// later ~4 % flatter. Leaves about ±4° of scatter per cushion the model can't foresee.
    static let bounceTable: [(Double, Double)] = [(0, 1.4), (12, 1.45), (20, 1.65), (30, 1.62), (40, 1.45), (50, 1.38), (90, 1.3)]
    static func bounceRatio(_ deg: Double) -> Double {
        for k in 1..<bounceTable.count where deg <= bounceTable[k].0 {
            let (a0, r0) = bounceTable[k - 1], (a1, r1) = bounceTable[k]
            return r0 + (r1 - r0) * (deg - a0) / (a1 - a0)
        }
        return bounceTable.last!.1
    }   // (3.27: the +0.11 sent a near-square 8 bank 4° too wide; plain ×1.5 has no bias on the 34)
    /// a cushion hit this close to a pocket's centre is where the game's jaws behave unlike the model: never "sure"
    static let mouthNear = 90.0

    // MARK: table edges with the pocket jaws
    // Measured on the 1180×2556 screen (same on every table theme), then checked against shots in the logs:
    // the game's corner noses reach ~9 px further than drawn (a ball read as dropping rattled out), so they stop
    // 53 px from the corner and a jaw runs back at 45°. All for the ball's centre: a ball touches a cushion nose
    // when its centre is R from it. Side pockets: an 80 px gap with short jaws.
    struct Seg { let x1, y1, x2, y2: Double; let jaw: Bool }
    static let segs: [Seg] = {
        var out: [Seg] = []
        func mx(_ x: Double) -> Double { 2 * PoolEngine.midX - x }
        func my(_ y: Double) -> Double { 2 * PoolEngine.midY - y }
        let x0 = 207.5, x1 = 966.5, y0 = 584.0, y1 = 2135.0
        out.append(Seg(x1: 261, y1: y0, x2: mx(261), y2: y0, jaw: false))
        out.append(Seg(x1: 261, y1: y1, x2: mx(261), y2: y1, jaw: false))
        for x in [x0, x1] {
            out.append(Seg(x1: x, y1: 641, x2: x, y2: 1319.5, jaw: false))
            out.append(Seg(x1: x, y1: 1399.5, x2: x, y2: my(641), jaw: false))
        }
        for (a, b) in [((261.0, y0), (231.0, y0 - 30)), ((x0, 641.0), (x0 - 30, 611.0))] {
            for fx in [false, true] { for fy in [false, true] {
                out.append(Seg(x1: fx ? mx(a.0) : a.0, y1: fy ? my(a.1) : a.1, x2: fx ? mx(b.0) : b.0, y2: fy ? my(b.1) : b.1, jaw: true))
            } }
        }
        for fx in [false, true] {
            for (a, b) in [((x0, 1319.5), (190.0, 1321.0)), ((x0, 1399.5), (190.0, 1398.0))] {
                out.append(Seg(x1: fx ? mx(a.0) : a.0, y1: a.1, x2: fx ? mx(b.0) : b.0, y2: b.1, jaw: true))
            }
        }
        return out
    }()
    /// where a ball drops: its centre gets this close to the hole's centre (same order as `pockets`)
    static let holes: [(x: Double, y: Double, r: Double)] = [
        (195, 570, 40), (979, 570, 40), (170, 1360, 37), (1004, 1360, 37), (195, 2149, 40), (979, 2149, 40)]

    @inline(__always) static func rayCircle(_ px: Double, _ py: Double, _ ux: Double, _ uy: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Double? {
        let fx = px - cx, fy = py - cy, b = fx * ux + fy * uy, c = fx * fx + fy * fy - r * r
        if b >= 0 { return nil }       // moving away (balls read a pixel too close together don't stop each other)
        if c < 0 { return 0 }
        let d = b * b - c
        if d < 0 { return nil }
        let t = -b - d.squareRoot()
        return t > 1e-6 ? t : nil
    }
    /// first touch of a ball centre moving from p along u with a cushion piece (a line with rounded ends);
    /// returns the distance and the push-out direction
    static func rayCapsule(_ px: Double, _ py: Double, _ ux: Double, _ uy: Double, _ s: Seg, face: Double = R, end: Double = R) -> (Double, Double, Double)? {
        let dx = s.x2 - s.x1, dy = s.y2 - s.y1, l = (dx * dx + dy * dy).squareRoot()
        let tx = dx / l, ty = dy / l, nx = -ty, ny = tx
        var best: (Double, Double, Double)? = nil
        for sg in [1.0, -1.0] {
            let den = ux * nx * sg + uy * ny * sg
            if den >= 0 { continue }   // only when moving towards this face
            let ox = s.x1 + nx * face * sg, oy = s.y1 + ny * face * sg
            let t = ((ox - px) * nx * sg + (oy - py) * ny * sg) / den
            if t <= 1e-6 { continue }
            let hx = px + ux * t, hy = py + uy * t, a = (hx - s.x1) * tx + (hy - s.y1) * ty
            if a >= 0 && a <= l && (best == nil || t < best!.0) { best = (t, nx * sg, ny * sg) }
        }
        for (ex, ey) in [(s.x1, s.y1), (s.x2, s.y2)] {
            if let t = rayCircle(px, py, ux, uy, ex, ey, end), t > 1e-6, best == nil || t < best!.0 {
                let hx = px + ux * t, hy = py + uy * t
                best = (t, (hx - ex) / end, (hy - ey) / end)
            }
        }
        return best
    }

    struct Run { var pts: [Double]; var pocket = -1; var ball: Int? = nil; var rails = 0; var jaws = 0; var railJaws = 0; var len = 0.0; var off = 1.0; var left = 0.0; var nearMouth = false }
    /// A ball rolling along a cushion (within 12° of it, centre at most 16 px off touching it): it slides past the
    /// corner jaw into the pocket. Seen in the logs: 5 px off the left cushion up into the top-left corner, 13 px off
    /// it down into the bottom-left one; both nudged the jaw and dropped.
    @inline(__always) static func alongRail(_ x: Double, _ y: Double, _ ux: Double, _ uy: Double) -> Bool {
        let c = cos(12 * Double.pi / 180), n = R + 16
        if abs(uy) >= c && (x - 207.5 < n || 966.5 - x < n) { return true }
        if abs(ux) >= c && (y - 584 < n || 2135 - y < n) { return true }
        return false
    }
    /// A ball rolling from (x,y) along (ux,uy): off cushions and jaws (they bend it: tan of the angle from the
    /// normal grows ×1.28), until it drops, touches another ball, or has gone `maxLen` / `maxRails` cushions.
    /// `pad`: make the pocket jaws and the cushion ends that much fatter. The game's own jaws sit a few px off
    /// where they are drawn (a ball read as going in rattled out), so "sure" pots are worked out with pad 4.
    static let safePad = 4.0
    /// `speed` (px/s): roll only as far as that pace carries the ball, losing half of it at each cushion.
    static func run(_ x0: Double, _ y0: Double, _ ux0: Double, _ uy0: Double, balls: [Ball], skip: Int, maxLen: Double = 3000, maxRails: Int = 2, gap: Double = 2 * R, pad: Double = 0, speed: Double? = nil, flat: Double = bounceFlatten) -> Run {
        var r = Run(pts: [x0, y0])
        let start = speed.map { rollDistance($0) } ?? maxLen
        var x = x0, y = y0, ux = ux0, uy = uy0, left = start, trav = 0.0
        for _ in 0..<10 {
            var best = left, kind = 0, which = -1, nx = 0.0, ny = 0.0, isJaw = false
            for (k, h) in holes.enumerated() { if let t = rayCircle(x, y, ux, uy, h.x, h.y, h.r), t < best { best = t; kind = 1; which = k } }
            for sg in segs { if let c = rayCapsule(x, y, ux, uy, sg, face: sg.jaw ? R + pad : R, end: R + pad), c.0 < best { best = c.0; kind = 2; nx = c.1; ny = c.2; isJaw = sg.jaw } }
            for b in balls where b.id != skip {
                if let t = rayCircle(x, y, ux, uy, b.x, b.y, gap), t > 1e-6, t < best { best = t; kind = 3; which = b.id }
            }
            let along = alongRail(x, y, ux, uy)
            x += ux * best; y += uy * best; left -= best; trav += best; r.pts += [x, y]
            if kind == 1 {
                r.pocket = which
                // how central: the last leg's line against the hole centre (0 middle … 1 by the jaw);
                // a ball that only brushed the corner jaw rolling along the cushion drops for sure
                let h = holes[which], perp = abs((h.x - x) * uy - (h.y - y) * ux)
                r.off = r.jaws > 0 ? 0.85 : (r.railJaws > 0 ? 0.5 : min(1, perp / (which == 2 || which == 3 ? 16.5 : 20)))
            }
            if kind == 3 { r.ball = which }
            if kind != 2 { break }
            let vn = ux * nx + uy * ny, tx = ux - vn * nx, ty = uy - vn * ny
            if isJaw {
                if along && abs(y - midY) > 300 { r.railJaws += 1 } else { r.jaws += 1 }
            } else if abs(vn) >= sin(12 * Double.pi / 180) {
                r.rails += 1   // a ball grazing the cushion it rolls along is no bank
            }
            if r.rails > maxRails { break }
            if !isJaw && abs(vn) >= sin(12 * Double.pi / 180) && holes.contains(where: { hypot($0.x - x, $0.y - y) < mouthNear }) { r.nearMouth = true }
            // off the cushion: the angle from the law above; the pace kept from along × keepAlong, into × keepInto
            let an = abs(vn), tm = (tx * tx + ty * ty).squareRoot()
            let l = ((tm * keepAlong) * (tm * keepAlong) + (an * keepInto) * (an * keepInto)).squareRoot()
            let tanIn = tm / max(an, 1e-6)
            let slid = trav < 140 ? 0.9 : 1.04
            let tanOut = flat * tanIn * bounceRatio(atan(tanIn) * 180 / Double.pi) * slid
            let co = 1 / (1 + tanOut * tanOut).squareRoot(), so = tanOut * co
            if tm > 1e-9 { ux = tx / tm * so + nx * co; uy = ty / tm * so + ny * co } else { ux = nx; uy = ny }
            if speed != nil && (isJaw || abs(vn) >= sin(12 * Double.pi / 180)) { left = rollDistance(l * speedFor(distance: left)) }
            x += nx * 0.01; y += ny * 0.01
        }
        r.len = start - left; r.left = left
        return r
    }
    /// the pace that rolls exactly d before stopping (inverse of rollDistance)
    static func speedFor(distance d: Double) -> Double {
        if d <= 0 { return 0 }
        var lo = 0.0, hi = 30000.0
        for _ in 0..<40 { let m = (lo + hi) / 2; if rollDistance(m) < d { lo = m } else { hi = m } }
        return hi
    }

    /// The cue ball after the hit at `vHit`, coming in along (ix,iy), the hit ball leaving along (ox,oy): the tangent pace
    /// plus `follow` of the hit pace along the ball's line.
    static func cueAfter(_ gx: Double, _ gy: Double, ix: Double, iy: Double, ox: Double, oy: Double, vHit: Double, balls: [Ball], skip: Int) -> Run {
        let along = max(0, min(1, ix * ox + iy * oy)), sn = (1 - along * along).squareRoot()
        let side = ix * -oy + iy * ox > 0
        let tx = side ? -oy : oy, ty = side ? ox : -ox
        let vx = tx * vHit * sn + ox * follow * vHit * along, vy = ty * vHit * sn + oy * follow * vHit * along
        let sp = (vx * vx + vy * vy).squareRoot()
        if sp < 1 { return Run(pts: [gx, gy]) }
        return run(gx, gy, vx / sp, vy / sp, balls: balls, skip: skip, maxRails: 4, speed: sp)
    }

    /// Where both balls go for your aim at a given power (%): the hit ball off up to four cushions until it drops or
    /// stops, and the cue ball along the tangent line (a stun hit; a straight hit stops it) until it stops.
    /// With no ball hit, the cue ball's own run. `cueStop` is where the cue ball comes to rest.
    static func powerPaths(cueX: Double, cueY: Double, aimX: Double, aimY: Double, target: Ball?, balls: [Ball], dir: Double?, power: Int) -> (obj: [Double], cue: [Double], cueStop: (Double, Double), objDrops: Bool, cueDrops: Bool) {
        let others = balls.filter { $0.id != 0 }
        let v0 = speedAt(power: Double(max(1, power)))
        var ax = aimX - cueX, ay = aimY - cueY
        let d1 = (ax * ax + ay * ay).squareRoot(); ax /= max(d1, 1e-6); ay /= max(d1, 1e-6)
        guard let b = target else {
            let c = run(cueX, cueY, ax, ay, balls: others, skip: 0, maxRails: 4, speed: v0)
            return ([], c.pts, (c.pts[c.pts.count - 2], c.pts[c.pts.count - 1]), false, c.pocket >= 0)
        }
        let vHit = speedFor(distance: max(0, rollDistance(v0) - d1))
        var ux = b.x - aimX, uy = b.y - aimY
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        if let a = dir { ux = cos(a); uy = sin(a) }
        let along = max(0, min(1, ax * ux + ay * uy))
        let o = run(b.x, b.y, ux, uy, balls: others, skip: b.id, maxRails: 4, speed: vHit * along)
        let c = cueAfter(aimX, aimY, ix: ax, iy: ay, ox: ux, oy: uy, vHit: vHit, balls: others, skip: b.id)
        return (o.pts, c.pts, (c.pts[c.pts.count - 2], c.pts[c.pts.count - 1]), o.pocket >= 0, c.pocket >= 0)
    }

    /// Does the hit ball, once off its first cushion, run into the cue ball's way (or where it stops)? A bank coming back
    /// across the table met the cue ball (3.29, log 26 Oct 11:2x). Timing is ignored: anywhere near its way = not sure.
    static func meetsCue(obj: [Double], cue: [Double]) -> Bool {
        guard obj.count >= 6, cue.count >= 2 else { return false }
        func segDist(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ px: Double, _ py: Double) -> Double {
            let dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
            let t = l2 < 1e-9 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
            return hypot(ax + dx * t - px, ay + dy * t - py)
        }
        func segSeg(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> Double {
            // closest approach of two segments: crossing = 0, else the nearest endpoint to the other segment
            func cr(_ ox: Double, _ oy: Double, _ px: Double, _ py: Double, _ qx: Double, _ qy: Double) -> Double { (px - ox) * (qy - oy) - (py - oy) * (qx - ox) }
            let d1 = cr(a.0, a.1, a.2, a.3, b.0, b.1), d2 = cr(a.0, a.1, a.2, a.3, b.2, b.3)
            let d3 = cr(b.0, b.1, b.2, b.3, a.0, a.1), d4 = cr(b.0, b.1, b.2, b.3, a.2, a.3)
            if d1 * d2 < 0 && d3 * d4 < 0 { return 0 }
            return min(segDist(a.0, a.1, a.2, a.3, b.0, b.1), segDist(a.0, a.1, a.2, a.3, b.2, b.3),
                       segDist(b.0, b.1, b.2, b.3, a.0, a.1), segDist(b.0, b.1, b.2, b.3, a.2, a.3))
        }
        var cs: [(Double, Double, Double, Double)] = []
        if cue.count >= 4 { for i in stride(from: 0, to: cue.count - 3, by: 2) { cs.append((cue[i], cue[i + 1], cue[i + 2], cue[i + 3])) } }
        else { cs.append((cue[0], cue[1], cue[0], cue[1])) }
        for i in stride(from: 2, to: obj.count - 3, by: 2) {   // from the first cushion on
            let s = (obj[i], obj[i + 1], obj[i + 2], obj[i + 3])
            for c in cs where segSeg(s, c) < 2 * R + 4 { return true }
        }
        return false
    }

    // MARK: diamonds (the light dots on the rails)
    // Three on the top and bottom rails, six on each side (three either side of the middle pocket), a quarter of
    // the way between pocket centres each. Rails are named as you see the table; dots count from the top / left.
    static func railSpot(_ x: Double, _ y: Double) -> String {
        func half(_ k: Double) -> String {
            let q = (k * 2).rounded() / 2, w = Int(q)
            return q == Double(w) ? "\(w)" : (w == 0 ? "½" : "\(w)½")
        }
        if abs(x - xMin) < 3 || abs(x - xMax) < 3 {
            let rail = abs(x - xMin) < 3 ? "ขอบซ้าย" : "ขอบขวา"
            // 0 … 4 from the corner pocket to the middle pocket on the top half, 4 … 8 on the bottom half
            let k = y < midY ? (y - 581) / ((midY - 581) / 4) : 4 + (y - midY) / ((2140 - midY) / 4)
            if k < 0.25 || k > 7.75 { return rail + " ข้างหลุมมุม" }
            if k > 3.75 && k < 4.25 { return rail + " ข้างหลุมกลาง" }
            return rail + " จุด " + half(k < 4 ? k : k - 1)   // the dots below the middle pocket are 4, 5, 6
        }
        let rail = y < midY ? "ขอบบน" : "ขอบล่าง"
        let k = (x - 203) / ((975 - 203) / 4.0)
        if k < 0.25 || k > 3.75 { return rail + " ข้างหลุมมุม" }
        return rail + " จุด " + half(k)
    }
    static func onRail(_ x: Double, _ y: Double) -> Bool { abs(x - xMin) < 3 || abs(x - xMax) < 3 || abs(y - yMin) < 3 || abs(y - yMax) < 3 }
    /// where a ball sent from (bx,by) along (ux,uy) first meets a cushion, if it does before anything else
    static func cushionHit(_ bx: Double, _ by: Double, _ ux: Double, _ uy: Double, balls: [Ball], skip: Int) -> (Double, Double)? {
        let r = run(bx, by, ux, uy, balls: balls.filter { $0.id != 0 }, skip: skip, maxRails: 1)
        guard r.rails >= 1, r.pts.count >= 4 else { return nil }
        let x = r.pts[2], y = r.pts[3]
        return onRail(x, y) ? (x, y) : nil
    }

    // MARK: rolling and power

    /// how far a ball rolls from speed v before it stops
    static func rollDistance(_ v: Double) -> Double {
        if v <= 0 { return 0 }
        let c = decelV, a = decel0, vr = slideTo * v
        let skid = (v * v - vr * vr) / (2 * slideDecel)
        return skid + vr / c - a / (c * c) * log(1 + c * vr / a)
    }
    /// start speed that leaves `arrive` px/s after rolling d
    static func speedNeeded(toRoll d: Double, arriving: Double) -> Double {
        let target = d + rollDistance(arriving)
        var lo = 0.0, hi = 20000.0
        for _ in 0..<50 { let m = (lo + hi) / 2; if rollDistance(m) < target { lo = m } else { hi = m } }
        return hi
    }
    /// power-bar % so the object ball still has some pace at the pocket
    static func powerPct(cueToGhost d1: Double, objLen d2: Double, cut: Double, bank: Bool) -> Int {
        // a cushion takes speed off; ask for a little more on banks
        let vObj = speedNeeded(toRoll: d2 * (bank ? 1.25 : 1), arriving: 260)
        let vHit = vObj / max(0.3, cos(cut * Double.pi / 180))
        let v0 = speedNeeded(toRoll: d1, arriving: vHit)
        let pct = powerFor(speed: v0)
        return max(10, min(100, Int((pct / 5).rounded()) * 5))
    }

    // MARK: shots

    /// An object ball heading along (ux,uy) from (tx,ty): where it ends up. Direct into a pocket (jaws included),
    /// or off one cushion into one. Returns pocket index, path length, whether it banked, and how far off the
    /// pocket centre it runs (0 = dead centre, 1 = on the edge; 0.85 = it needs the jaw).
    static func trace(_ tx: Double, _ ty: Double, _ ux0: Double, _ uy0: Double, balls: [Ball], skip: Int, pad: Double = 0) -> (pocket: Int, len: Double, bank: Bool, off: Double)? {
        let r = run(tx, ty, ux0, uy0, balls: balls.filter { $0.id != 0 }, skip: skip, maxRails: 4, gap: 2 * R - 3, pad: pad)
        guard r.pocket >= 0 else { return nil }
        return (r.pocket, r.len, r.rails >= 1, r.off)
    }

    /// Scratch after a stun hit: the cue ball runs along the tangent line from the ghost position.
    static func scratches(cueX: Double, cueY: Double, gx: Double, gy: Double, ux: Double, uy: Double) -> Bool {
        let vx = gx - cueX, vy = gy - cueY
        let side = vx * -uy + vy * ux > 0
        let tx = side ? -uy : uy, ty = side ? ux : -ux
        return run(gx, gy, tx, ty, balls: [], skip: 0, maxLen: 500, maxRails: 0).pocket >= 0
    }

    /// All shots from a cue position (straight-in and one-cushion banks), best first.
    static func shots(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>, placed: Bool = false, banks: Bool = true) -> [Shot] {
        var out: [Shot] = []
        for t in balls where legal.contains(t.id) {
            for (pi, p) in pockets.enumerated() {
                // where to send the object ball: the pocket itself, or its mirror image across one cushion
                var aims: [(Double, Double, Bool)] = [(p.x, p.y, false)]
                if banks {   // trace() checks the ball really comes off that cushion into this pocket
                    aims += [(2 * xMin - p.x, p.y, true), (2 * xMax - p.x, p.y, true), (p.x, 2 * yMin - p.y, true), (p.x, 2 * yMax - p.y, true)]
                }
                for (ax, ay, bank) in aims {
                    var ux = ax - t.x, uy = ay - t.y
                    let dd = (ux * ux + uy * uy).squareRoot(); if dd < 1 { continue }
                    ux /= dd; uy /= dd
                    if bank {
                        // cushions don't reflect like a mirror (the ball comes off flatter): search around the
                        // mirror line for the direction that really ends in this pocket
                        let a0 = atan2(uy, ux)
                        var bestA: Double? = nil, bestOff = 1.0
                        for k in -60...60 {
                            let a = a0 + Double(k) * 0.2 * Double.pi / 180
                            if let tr = trace(t.x, t.y, cos(a), sin(a), balls: balls, skip: t.id, pad: safePad), tr.pocket == pi, tr.bank, tr.off < bestOff { bestOff = tr.off; bestA = a }
                        }
                        guard let a = bestA else { continue }
                        ux = cos(a); uy = sin(a)
                    }
                    guard let tr = trace(t.x, t.y, ux, uy, balls: balls, skip: t.id, pad: safePad), tr.pocket == pi, tr.bank == bank, tr.off < 0.8 else { continue }
                    let gx = t.x - ux * 2 * R, gy = t.y - uy * 2 * R
                    if gx < xMin - 2 || gx > xMax + 2 || gy < yMin - 2 || gy > yMax + 2 { continue }
                    let vx = gx - cueX, vy = gy - cueY, d1 = (vx * vx + vy * vy).squareRoot()
                    if d1 < 1 { continue }
                    let cosCut = (vx * ux + vy * uy) / d1
                    if cosCut < cos(82 * Double.pi / 180) { continue }   // thin cuts still count (the game forgives them)
                    if !clear(cueX, cueY, gx, gy, balls, skip: t.id, gap: 2 * R - 3) { continue }
                    var tol = (p.side ? 13.0 : 20.0) * 2 * R * cosCut / (max(d1, 2 * R) * max(tr.len, R))
                    if bank { tol *= 0.5; if tol * 180 / Double.pi < 0.04 { continue } }   // a bank that needs a perfect hit is no suggestion
                    let cut = acos(max(-1, min(1, cosCut))) * 180 / Double.pi
                    let pct = powerPct(cueToGhost: d1, objLen: tr.len, cut: cut, bank: bank)
                    let power = pct < 35 ? "เบา" : (pct < 70 ? "กลาง" : "แรง")
                    out.append(Shot(ball: t.id, pocket: pi, cueX: cueX, cueY: cueY, ghostX: gx, ghostY: gy,
                                    cut: cut, tolerance: tol * 180 / Double.pi,
                                    scratch: scratches(cueX: cueX, cueY: cueY, gx: gx, gy: gy, ux: ux, uy: uy),
                                    power: power, placed: placed, bank: bank, objLen: tr.len, powerPct: pct))
                }
            }
        }
        return out.sorted { score($0) > score($1) }
    }
    static func score(_ s: Shot) -> Double { s.tolerance * (s.scratch ? 0.4 : 1) * (s.powerPct > 90 ? 0.8 : 1) }

    /// Ball in hand: try cue positions all over the table and keep the one with the easiest shot.
    static func bestPlacement(balls: [Ball], legal: Set<Int>) -> Shot? {
        var best: Shot? = nil
        var y = yMin
        while y <= yMax {
            var x = xMin
            while x <= xMax {
                if !balls.contains(where: { ($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y) < (2 * R + 4) * (2 * R + 4) }),
                   let s = shots(cueX: x, cueY: y, balls: balls, legal: legal, placed: true, banks: false).first,
                   best == nil || score(s) > score(best!) { best = s }
                x += 24
            }
            y += 24
        }
        return best
    }

    /// No pottable ball: the easiest legal ball to at least hit first (a safety, not a pot).
    static func safety(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>) -> Ball? {
        balls.filter { legal.contains($0.id) && clear(cueX, cueY, $0.x, $0.y, balls, skip: $0.id, gap: 2 * R - 1) }
            .min { hypot($0.x - cueX, $0.y - cueY) < hypot($1.x - cueX, $1.y - cueY) }
    }

    /// How the player's current aim (the game's aim circle) compares with the shot.
    /// Returns the angle to turn in degrees (+ = clockwise on screen) and whether it is close enough.
    static func aimError(_ s: Shot, aimX: Double, aimY: Double) -> (turn: Double, ok: Bool) {
        let a1 = atan2(aimY - s.cueY, aimX - s.cueX), a2 = atan2(s.ghostY - s.cueY, s.ghostX - s.cueX)
        var d = (a2 - a1) * 180 / Double.pi
        while d > 180 { d -= 360 }; while d < -180 { d += 360 }
        return (d, abs(d) <= max(0.08, s.tolerance * 0.45))
    }

    /// What the current aim does: which ball it hits first, and whether that ball drops (and where).
    struct Verdict: Equatable {
        var ball: Int                 // first ball hit, -1 none
        var pocket = -1               // where it drops, -1 it doesn't
        var bank = false
        var off = 1.0                 // 0 dead centre of the pocket … 1 edge
        var scratch = false
        var foul = false              // first ball hit is not yours (or the 8 too early)
        var powerPct = 0
    }
    static func judge(cueX: Double, cueY: Double, aimX: Double, aimY: Double, balls: [Ball], legal: Set<Int>, dir: Double? = nil) -> Verdict {
        // the aim circle sits where the cue ball touches the first ball: that ball is 2R from it
        guard let t = balls.filter({ $0.id != 0 }).min(by: { hypot($0.x - aimX, $0.y - aimY) < hypot($1.x - aimX, $1.y - aimY) }),
              hypot(t.x - aimX, t.y - aimY) < 2 * R + 8 else { return Verdict(ball: -1) }
        var v = Verdict(ball: t.id)
        v.foul = !legal.contains(t.id)
        var ux = t.x - aimX, uy = t.y - aimY
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        if let a = dir { ux = cos(a); uy = sin(a) }    // the game's own line beats our estimate from positions
        if let tr = trace(t.x, t.y, ux, uy, balls: balls, skip: t.id) {
            v.pocket = tr.pocket; v.bank = tr.bank; v.off = tr.off
            // a sure pot also drops with the jaws a little fatter (where the game really has them is only known to a few px)
            if trace(t.x, t.y, ux, uy, balls: balls, skip: t.id, pad: safePad)?.pocket != tr.pocket { v.off = max(v.off, 0.8) }
            // a bank is sure only if it drops however lively the cushions turn out (within what was measured)
            if tr.bank {
                if run(t.x, t.y, ux, uy, balls: balls.filter { $0.id != 0 }, skip: t.id, maxRails: 4, gap: 2 * R - 3, pad: safePad).nearMouth { v.off = max(v.off, 0.8) }
                for f in flatRange where run(t.x, t.y, ux, uy, balls: balls.filter { $0.id != 0 }, skip: t.id, maxRails: 4, gap: 2 * R - 3, pad: safePad, flat: f).pocket != tr.pocket { v.off = max(v.off, 0.8) }
            }
            let vx = aimX - cueX, vy = aimY - cueY, d1 = (vx * vx + vy * vy).squareRoot()
            let cut = acos(max(-1, min(1, (vx * ux + vy * uy) / max(d1, 1e-6)))) * 180 / Double.pi
            v.powerPct = powerPct(cueToGhost: d1, objLen: tr.len, cut: cut, bank: tr.bank)
        }
        v.scratch = scratches(cueX: cueX, cueY: cueY, gx: aimX, gy: aimY, ux: ux, uy: uy)
        return v
    }


    /// How far you can turn the cue either way and still pot: cue-angle window in degrees (0 = your aim now,
    /// + = turning clockwise on screen) for the pocket your line goes to (or the nearest one it could go to).
    struct Window: Equatable { var pocket: Int; var lo: Double; var hi: Double; var centreDir: Double; var sure = true }
    static func potWindow(cueX: Double, cueY: Double, aimX: Double, aimY: Double, target t: Ball, balls: [Ball], dir: Double?) -> Window? {
        let a0 = atan2(aimY - cueY, aimX - cueX)
        func objDir(_ d: Double) -> Double? {
            let ux = cos(a0 + d * Double.pi / 180), uy = sin(a0 + d * Double.pi / 180)
            let fx = cueX - t.x, fy = cueY - t.y, b = fx * ux + fy * uy, c = fx * fx + fy * fy - 4 * R * R
            let disc = b * b - c
            if disc < 0 || b >= 0 { return nil }
            let sDist = -b - disc.squareRoot()
            return atan2(t.y - (cueY + uy * sDist), t.x - (cueX + ux * sDist))
        }
        guard let g0 = objDir(0) else { return nil }
        // the game's own line is a little more exact than the geometry: shift every direction by the difference
        var shift = 0.0
        if let gd = dir {
            var d = gd - g0
            while d > Double.pi { d -= 2 * Double.pi }; while d < -Double.pi { d += 2 * Double.pi }
            if abs(d) < 0.2 { shift = d }
        }
        let step = 0.05, n = 80
        var res = [Int](repeating: -1, count: 2 * n + 1)
        var sure = true
        for pad in [safePad, 0] {
            for k in -n...n {
                if let o = objDir(Double(k) * step), let tr = trace(t.x, t.y, cos(o + shift), sin(o + shift), balls: balls, skip: t.id, pad: pad) {
                    res[k + n] = tr.pocket
                }
            }
            if res.contains(where: { $0 >= 0 }) { break }
            sure = false   // nothing drops for sure: show where it only just drops
        }
        // the pocket at 0, or the nearest potting turn
        var k0 = n
        if res[n] < 0 {
            guard let near = res.indices.filter({ res[$0] >= 0 }).min(by: { abs($0 - n) < abs($1 - n) }) else { return nil }
            k0 = near
        }
        let p = res[k0]
        var lo = k0, hi = k0
        while lo > 0 && res[lo - 1] == p { lo -= 1 }
        while hi < 2 * n && res[hi + 1] == p { hi += 1 }
        let l = Double(lo - n) * step, h = Double(hi - n) * step
        return Window(pocket: p, lo: l, hi: h, centreDir: (objDir((l + h) / 2) ?? g0) + shift, sure: sure)
    }

    // MARK: paths to draw

    /// Where a ball rolling from (x,y) along (ux,uy) goes: off up to two cushions (and the jaws), stopping at a
    /// pocket, a ball in the way, or after `maxLen` px. x,y pairs.
    static func path(_ x0: Double, _ y0: Double, _ ux0: Double, _ uy0: Double, balls: [Ball], skip: Int, maxLen: Double = 2400) -> [Double] {
        run(x0, y0, ux0, uy0, balls: balls.filter { $0.id != 0 }, skip: skip, maxLen: maxLen, maxRails: 2).pts
    }

    /// The object ball's path for a hit from ghost position (gx,gy).
    static func objectPath(_ bx: Double, _ by: Double, gx: Double, gy: Double, balls: [Ball], skip: Int, pocket: Pocket? = nil, dir: Double? = nil) -> [Double] {
        var ux = bx - gx, uy = by - gy
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        if let a = dir { ux = cos(a); uy = sin(a) }
        return path(bx, by, ux, uy, balls: balls, skip: skip)
    }

    /// Where the cue ball runs after a centre-ball hit: along the tangent line (a dead-straight hit stops it).
    static func cuePath(cueX: Double, cueY: Double, gx: Double, gy: Double, bx: Double, by: Double, balls: [Ball], dir: Double? = nil) -> [Double] {
        var ux = bx - gx, uy = by - gy
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        if let a = dir { ux = cos(a); uy = sin(a) }
        let vx = gx - cueX, vy = gy - cueY
        let dv = (vx * vx + vy * vy).squareRoot()
        let along = (vx * ux + vy * uy) / max(dv, 1e-6)          // cos of the cut
        if along > 0.995 { return [] }                            // straight hit: the cue ball stops
        let side = vx * -uy + vy * ux > 0
        let tx = side ? -uy : uy, ty = side ? ux : -ux
        let len = 900 * (1 - along * along).squareRoot()          // thinner cut, more pace left on the cue ball
        return path(gx, gy, tx, ty, balls: balls, skip: 0, maxLen: len)
    }


    // MARK: planning a run (which ball first, where the cue ball ends up, what is next)

    /// Where the cue ball comes to rest after a centre-ball shot at the given power: it leaves the hit along
    /// the tangent line with the share of pace a cut gives it, and rolls (off a cushion if it gets there).
    static func cueEnd(_ s: Shot, balls: [Ball]) -> (Double, Double) {
        guard let b = balls.first(where: { $0.id == s.ball }) else { return (s.cueX, s.cueY) }
        let d1 = hypot(s.ghostX - s.cueX, s.ghostY - s.cueY)
        let v0 = speedAt(power: Double(s.powerPct))
        let vHit = speedFor(distance: max(0, rollDistance(v0) - d1))
        let ix = (s.ghostX - s.cueX) / max(d1, 1e-6), iy = (s.ghostY - s.cueY) / max(d1, 1e-6)
        let od = max(1e-6, hypot(b.x - s.ghostX, b.y - s.ghostY))
        let r = cueAfter(s.ghostX, s.ghostY, ix: ix, iy: iy, ox: (b.x - s.ghostX) / od, oy: (b.y - s.ghostY) / od, vHit: vHit, balls: balls.filter { $0.id != s.ball }, skip: s.ball)
        return (r.pts[r.pts.count - 2], r.pts[r.pts.count - 1])
    }

    struct Plan { var first: Shot; var next: Shot?; var cueEnd: (Double, Double) }

    /// Try the best few shots; for each, where the cue ball stops and how good the next shot is from there.
    /// group: 1 solids, 2 stripes, 0 open (the 8 follows once your group is gone).
    static func plan(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>, group: Int) -> Plan? {
        let firsts = shots(cueX: cueX, cueY: cueY, balls: balls, legal: legal, banks: false)
        guard !firsts.isEmpty else { return nil }
        var best: (Double, Plan)? = nil
        for s in firsts.prefix(6) {
            let rest = balls.filter { $0.id != s.ball }
            let end = cueEnd(s, balls: balls)
            var nextLegal = legal.subtracting([s.ball])
            if nextLegal.isEmpty && s.ball != 8 { nextLegal = [8] }
            let n = s.ball == 8 ? nil : shots(cueX: end.0, cueY: end.1, balls: rest, legal: nextLegal, banks: false).first
            // this shot's ease, and most of the next one's (no next shot at all is a real cost)
            let v = score(s) + (n.map { 0.7 * score($0) } ?? (s.ball == 8 ? 0 : -0.15))
            if s.scratch { continue }
            let p = Plan(first: s, next: n, cueEnd: end)
            if best == nil || v > best!.0 { best = (v, p) }
        }
        return best?.1 ?? firsts.first.map { Plan(first: $0, next: nil, cueEnd: cueEnd($0, balls: balls)) }
    }

    /// Opening break: most balls still racked at the top.
    static func isBreak(_ balls: [Ball]) -> Bool {
        balls.filter { $0.id != 0 && $0.y < 1100 && $0.x > 430 && $0.x < 750 }.count >= 9
    }

    // MARK: every shot from here (straight, banks, cue ball off cushions first)

    /// One way to pot a ball: turn the cue to `angle` (± `width`/2 still pots), pull `power`.
    struct Found: Equatable {
        var ball: Int, pocket: Int
        var angle: Double, width: Double          // cue direction (radians) and how much turn still pots (degrees)
        var objRails: Int, cueRails: Int
        var power: Int                             // power-bar % (the least that drops it, plus a margin)
        var ghostX: Double, ghostY: Double         // where the cue ball meets the ball
        var cuePts: [Double], objPts: [Double]     // the cue ball's way to the ball, the ball's way to the pocket
        var cueStop: [Double]                      // the cue ball after the hit until it stops (x,y pairs)
    }

    private struct Hit: Equatable { var ball: Int, pocket: Int, objRails: Int, cueRails: Int }
    private static func hitAt(_ cx: Double, _ cy: Double, _ a: Double, _ others: [Ball], flat: Double) -> (Hit, Run, Run)? {
        let ux = cos(a), uy = sin(a)
        let c = run(cx, cy, ux, uy, balls: others, skip: 0, maxLen: 4000, maxRails: 2, gap: 2 * R, flat: flat)
        guard c.pocket < 0, let id = c.ball, let b = others.first(where: { $0.id == id }), c.pts.count >= 4 else { return nil }
        let gx = c.pts[c.pts.count - 2], gy = c.pts[c.pts.count - 1]
        var ox = b.x - gx, oy = b.y - gy
        let d = (ox * ox + oy * oy).squareRoot(); ox /= max(d, 1e-6); oy /= max(d, 1e-6)
        let o = run(b.x, b.y, ox, oy, balls: others, skip: id, maxLen: 4000, maxRails: 4, gap: 2 * R - 3, pad: safePad, flat: flat)
        guard o.pocket >= 0, !o.nearMouth, !c.nearMouth else { return nil }
        return (Hit(ball: id, pocket: o.pocket, objRails: o.rails, cueRails: c.rails), c, o)
    }

    /// Sweep the cue all the way round (0.1° steps) and keep, for your balls, every window of directions that pots:
    /// only shots that are sure — at least 0.3° of turn to spare (0.2° for banks), still dropping with the cushions bouncing anywhere
    /// in `flatRange`, within 90 % power, and the cue ball not following it in.
    static func sweep(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>) -> [Found] {
        let others = balls.filter { $0.id != 0 }
        let n = 3600, step = 2 * Double.pi / Double(n)
        var keys = [Hit?](repeating: nil, count: n)
        for k in 0..<n { if let h = hitAt(cueX, cueY, Double(k) * step, others, flat: bounceFlatten), legal.contains(h.0.ball) { keys[k] = h.0 } }
        // windows (the sweep wraps round)
        var out: [Found] = []
        guard let firstGap = keys.firstIndex(where: { $0 == nil }) else { return [] }
        var visited = 0
        var k = firstGap
        while visited < n {
            guard let h = keys[k % n] else { k += 1; visited += 1; continue }
            var len = 0
            while len < n && keys[(k + len) % n] == h { len += 1 }
            visited += len
            let w = Double(len) * 0.1
            let mid = (Double(k) + Double(len - 1) / 2) * step
            k += len
            if w < (h.objRails + h.cueRails > 0 ? 0.2 : 0.3) { continue }
            // sure: the middle still pots with the cushions a bit livelier or deader than measured
            if h.objRails + h.cueRails > 0 {
                var ok = true
                for f in flatRange { if hitAt(cueX, cueY, mid, others, flat: f)?.0 != h { ok = false } }
                if !ok { continue }
            }
            guard let hm = hitAt(cueX, cueY, mid, others, flat: bounceFlatten) else { continue }
            let c = hm.1
            // power: every power (steps of 5) that drops it cleanly — the ball doesn't meet the cue ball on its way, the
            // cue ball doesn't follow it in. Then from the least that drops +10 up, the one leaving the easiest next ball
            // (3.29: it was always least +10, mostly 30–40, with no thought for the next shot)
            guard let tb = others.first(where: { $0.id == h.ball }) else { continue }
            var ok: [Int: (obj: [Double], stop: [Double])] = [:]
            var p = 10
            while p <= 90 {
                let v0 = speedAt(power: Double(p))
                let cr = run(cueX, cueY, cos(mid), sin(mid), balls: others, skip: 0, maxLen: 4000, maxRails: 2, gap: 2 * R, speed: v0)
                if cr.ball == h.ball, cr.pts.count >= 4 {
                    let gx = cr.pts[cr.pts.count - 2], gy = cr.pts[cr.pts.count - 1]
                    let lx = gx - cr.pts[cr.pts.count - 4], ly = gy - cr.pts[cr.pts.count - 3], ll = max(1e-6, (lx * lx + ly * ly).squareRoot())
                    var ox = tb.x - gx, oy = tb.y - gy
                    let d = max(1e-6, (ox * ox + oy * oy).squareRoot()); ox /= d; oy /= d
                    let along = max(0, min(1, (lx * ox + ly * oy) / ll))
                    let vHit = speedFor(distance: cr.left)
                    let o = run(tb.x, tb.y, ox, oy, balls: others, skip: h.ball, maxLen: 4000, maxRails: 4, gap: 2 * R - 3, pad: safePad, speed: vHit * along)
                    if o.pocket == h.pocket {
                        let cAfter = cueAfter(gx, gy, ix: lx / ll, iy: ly / ll, ox: ox, oy: oy, vHit: vHit, balls: others, skip: h.ball)
                        if cAfter.pocket < 0 && !meetsCue(obj: o.pts, cue: cAfter.pts) { ok[p] = (o.pts, cAfter.pts) }
                    }
                }
                p += 5
            }
            guard let least = ok.keys.min() else { continue }
            var nl = legal.subtracting([h.ball]); if nl.isEmpty && h.ball != 8 { nl = [8] }
            let rest = others.filter { $0.id != h.ball }
            var need: Int? = nil, objPts: [Double] = [], stop: [Double] = [], bestV = -1.0
            for q in stride(from: min(90, least + 10), through: 90, by: 5) {
                guard let r = ok[q], r.stop.count >= 2, ok[q - 5] != nil else { continue }   // a power either side of it drops too
                let cx = r.stop[r.stop.count - 2], cy = r.stop[r.stop.count - 1]
                let nxt = h.ball == 8 ? 1 : (shots(cueX: cx, cueY: cy, balls: rest, legal: nl, banks: false).filter { !$0.scratch }.map { dropChance($0.tolerance) }.max() ?? 0)
                let val = nxt * (1 - Double(q) / 400)
                if val > bestV + 1e-9 { bestV = val; need = q; objPts = r.obj; stop = r.stop }
            }
            if need == nil, let r = ok[least] { need = min(90, least + 10); objPts = r.obj; stop = r.stop }
            guard let pw = need else { continue }
            out.append(Found(ball: h.ball, pocket: h.pocket, angle: mid, width: w, objRails: h.objRails, cueRails: h.cueRails,
                             power: pw, ghostX: c.pts[c.pts.count - 2], ghostY: c.pts[c.pts.count - 1],
                             cuePts: c.pts, objPts: objPts, cueStop: stop))
        }
        // easiest first: more turn to spare, fewer cushions, less power
        func score(_ f: Found) -> Double { f.width * pow(0.75, Double(f.objRails)) * pow(0.6, Double(f.cueRails)) * (f.power > 80 ? 0.8 : 1) }
        return out.sorted { score($0) > score($1) }
    }

    // MARK: clearing the table in one visit

    /// chance a shot drops, from how much the cue may turn (± degrees) and still pot it
    static func dropChance(_ halfWindow: Double) -> Double { min(0.97, halfWindow / (halfWindow + 0.12)) }

    /// Look ahead through the whole rack: from each sure first shot, where the cue ball stops, then the best few
    /// straight shots from there (and where it stops after each), down to the 8 — a beam of the likeliest runs.
    /// Returns the first shot of the run that clears the most (or is likeliest to), how many balls that run pots,
    /// and whether it ends with the 8.
    static func runOut(balls: [Ball], legal: Set<Int>, firsts: [Found]) -> (pick: Found, count: Int, wins: Bool, chance: Double)? {
        struct State { var cue: (Double, Double); var left: [Ball]; var legal: Set<Int>; var p: Double; var n: Int; var first: Int; var done: Bool }
        func value(_ s: State) -> Double { s.p * (Double(s.n) + (s.done ? 4 : 0)) }
        var beam: [State] = []
        for (i, f) in firsts.prefix(8).enumerated() {
            guard f.cueStop.count >= 2 else { continue }
            var nl = legal.subtracting([f.ball])
            if nl.isEmpty && f.ball != 8 { nl = [8] }
            beam.append(State(cue: (f.cueStop[f.cueStop.count - 2], f.cueStop[f.cueStop.count - 1]),
                              left: balls.filter { $0.id != f.ball }, legal: nl,
                              p: dropChance(f.width / 2), n: 1, first: i, done: f.ball == 8))
        }
        if beam.isEmpty { return nil }
        for _ in 0..<8 {
            var next: [State] = []
            var grew = false
            for st in beam {
                if st.done { next.append(st); continue }
                let options = shots(cueX: st.cue.0, cueY: st.cue.1, balls: st.left, legal: st.legal, banks: false).filter { !$0.scratch }.prefix(3)
                if options.isEmpty { next.append(st); continue }   // stuck: the run ends here
                for o in options {
                    grew = true
                    let end = cueEnd(o, balls: st.left)
                    var nl = st.legal.subtracting([o.ball])
                    if nl.isEmpty && o.ball != 8 { nl = [8] }
                    next.append(State(cue: end, left: st.left.filter { $0.id != o.ball }, legal: nl,
                                      p: st.p * dropChance(o.tolerance), n: st.n + 1, first: st.first, done: o.ball == 8))
                }
            }
            beam = Array(next.sorted { value($0) > value($1) }.prefix(12))
            if !grew { break }
        }
        guard let best = beam.max(by: { value($0) < value($1) }) else { return nil }
        return (firsts[best.first], best.n, best.done, best.p)
    }

    // MARK: safety (no sure pot)

    /// A safety: touch one of your balls first, a cushion after, the cue ball stays up, and it comes to rest where the
    /// other side has nothing easy (best: no straight line to any of their balls at all).
    struct Safety: Equatable {
        var ball: Int
        var angle: Double, power: Int
        var ghostX: Double, ghostY: Double        // where the cue ball meets the ball (the aim ring then sits here)
        var cuePts: [Double]                      // the cue ball to the hit (cushions first included)
        var objPts: [Double]                      // the hit ball until it stops
        var cueStop: [Double]                     // the cue ball after the hit until it stops
        var hidden: Bool                          // they can't see any of their balls (a snooker)
        var oppChance: Double                     // what they are left: sum of drop chances of their straight pots (worst of power ±5)
        var cueRails = 0                          // cushions the cue ball takes before the hit (a kick)
        var tier = 1                              // 1 a full safety, 2 a ball runs into another (stops less certain), 3 just a legal touch
    }

    private struct SafeTry { var ball: Int; var c: Run; var o: Run; var after: Run; var cue: (Double, Double); var obj: (Double, Double) }
    /// One try: cue along `a` at `power`; nil when it is a foul or can't be told (wrong ball or none first, no cushion
    /// after the hit, a ball dropping, or the balls running into others — those positions can't be foreseen).
    private static func safeTry(_ cx: Double, _ cy: Double, _ a: Double, _ power: Int, _ others: [Ball], _ legal: Set<Int>, tier: Int = 1) -> SafeTry? {
        let cr = run(cx, cy, cos(a), sin(a), balls: others, skip: 0, maxLen: 4000, maxRails: 2, speed: speedAt(power: Double(power)))
        guard cr.pocket < 0, cr.jaws == 0, let id = cr.ball, legal.contains(id), let b = others.first(where: { $0.id == id }), cr.pts.count >= 4 else { return nil }
        let n = cr.pts.count
        let gx = cr.pts[n - 2], gy = cr.pts[n - 1]
        let lx = gx - cr.pts[n - 4], ly = gy - cr.pts[n - 3], ll = max(1e-6, (lx * lx + ly * ly).squareRoot())
        var ox = b.x - gx, oy = b.y - gy
        let d = max(1e-6, (ox * ox + oy * oy).squareRoot()); ox /= d; oy /= d
        let along = max(0, min(1, (lx * ox + ly * oy) / ll))
        let vHit = speedFor(distance: cr.left)
        let o = run(b.x, b.y, ox, oy, balls: others, skip: id, maxLen: 4000, maxRails: 6, speed: vHit * along)
        if tier < 3 { guard o.pocket < 0 else { return nil } }
        if tier < 2 { guard o.ball == nil else { return nil } }
        let after = cueAfter(gx, gy, ix: lx / ll, iy: ly / ll, ox: ox, oy: oy, vHit: vHit, balls: others, skip: id)
        guard after.pocket < 0 else { return nil }
        if tier < 2 { guard after.ball == nil else { return nil } }
        // a cushion after the hit (by either ball), or it is a foul (a ball sent into another may still reach one: tier 3)
        if tier < 3 { guard o.rails + o.jaws + after.rails + after.jaws >= 1 || o.pocket >= 0 else { return nil } }
        let oe = (o.pts[o.pts.count - 2], o.pts[o.pts.count - 1]), ce = (after.pts[after.pts.count - 2], after.pts[after.pts.count - 1])
        // the two balls must not end up on top of each other (they would have met on the way)
        if tier < 3 && hypot(oe.0 - ce.0, oe.1 - ce.1) < 2 * R { return nil }
        return SafeTry(ball: id, c: cr, o: o, after: after, cue: ce, obj: oe)
    }

    /// What the other side is left with the cue ball at `cue`: the summed drop chance of their straight pots, and
    /// whether they can see any of their balls at all (centre or either edge).
    static func leaves(cue: (Double, Double), balls: [Ball], opp: Set<Int>) -> (chance: Double, hidden: Bool) {
        let theirs = balls.filter { opp.contains($0.id) }
        var seen = false
        for t in theirs where !seen {
            var ux = t.x - cue.0, uy = t.y - cue.1
            let d = max(1e-6, (ux * ux + uy * uy).squareRoot()); ux /= d; uy /= d
            for side in [-0.85, 0, 0.85] {
                // the cue ball touching the ball on this side: 2R from its centre
                let gx = t.x - ux * 2 * R * (1 - side * side).squareRoot() - uy * 2 * R * side
                let gy = t.y - uy * 2 * R * (1 - side * side).squareRoot() + ux * 2 * R * side
                if clear(cue.0, cue.1, gx, gy, balls, skip: t.id, gap: 2 * R - 1) { seen = true; break }
            }
        }
        let shotsLeft = shots(cueX: cue.0, cueY: cue.1, balls: balls, legal: opp, banks: false).filter { !$0.scratch }
        let chance = shotsLeft.prefix(4).reduce(0.0) { $0 + dropChance($1.tolerance) }
        return (chance, !seen)
    }

    /// Search every cue direction (½° steps) and power (10–60 %) for the safety that leaves the other side least, and still
    /// works with the power 5 off either way and the cue turned ½° either way (where the cue ball stops is only known
    /// roughly). `opp`: the balls they would be on.
    static func safetyPlan(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>, opp: Set<Int>) -> Safety? {
        // a full safety if there is one; else let the balls run into others; else at least a legal touch (a kick off
        // cushions when nothing is in sight) — anything beats giving away ball in hand
        for tier in 1...3 { if let s = safetyPlan(cueX: cueX, cueY: cueY, balls: balls, legal: legal, opp: opp, tier: tier) { return s } }
        return nil
    }
    private static func safetyPlan(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>, opp: Set<Int>, tier: Int) -> Safety? {
        let others = balls.filter { $0.id != 0 }
        let n = 720, step = 2 * Double.pi / Double(n)
        let powers = Array(stride(from: 5, through: 65, by: 5))
        // directions whose first ball (ignoring pace) is one of yours
        var okDir = [Bool](repeating: false, count: n)
        for k in 0..<n {
            let a = Double(k) * step
            let c = run(cueX, cueY, cos(a), sin(a), balls: others, skip: 0, maxLen: 4000, maxRails: 2)
            if c.pocket < 0, c.jaws == 0, let id = c.ball, legal.contains(id) { okDir[k] = true }
        }
        var tries = [[SafeTry?]](repeating: [SafeTry?](repeating: nil, count: powers.count), count: n)
        for k in 0..<n where okDir[k] {
            for (j, p) in powers.enumerated() { tries[k][j] = safeTry(cueX, cueY, Double(k) * step, p, others, legal, tier: tier) }
        }
        // what they are left (cached by where the two balls stop, to 6 px)
        var memo: [String: (Double, Bool)] = [:]
        func left(_ t: SafeTry) -> (Double, Bool) {
            let key = "\(t.ball):\(Int(t.cue.0 / 6)),\(Int(t.cue.1 / 6)):\(Int(t.obj.0 / 6)),\(Int(t.obj.1 / 6))"
            if let m = memo[key] { return m }
            var after = others.filter { $0.id != t.ball }; after.append(Ball(id: t.ball, x: t.obj.0, y: t.obj.1))
            let r = leaves(cue: t.cue, balls: after, opp: opp)
            memo[key] = (r.chance, r.hidden); return (r.chance, r.hidden)
        }
        var best: (cost: Double, k: Int, j: Int, chance: Double, hidden: Bool)? = nil
        for k in 0..<n where okDir[k] {
            for j in 1..<(powers.count - 1) where powers[j] >= 10 && powers[j] <= 60 {
                guard let t = tries[k][j] else { continue }
                // tier 1: still a safety with the power 5 off and the cue ½° off; tier 2: the power 5 off; tier 3: as is
                var group: [SafeTry] = [t]
                if tier <= 2 {
                    guard let lo = tries[k][j - 1], let hi = tries[k][j + 1], lo.ball == t.ball, hi.ball == t.ball else { continue }
                    group += [lo, hi]
                }
                if tier == 1 {
                    guard let l = tries[(k + n - 1) % n][j], let r = tries[(k + 1) % n][j], l.ball == t.ball, r.ball == t.ball else { continue }
                    group += [l, r]
                }
                var worst = 0.0, allHidden = true
                if opp.isEmpty { allHidden = false } else {
                    for x in group { let e = left(x); worst = max(worst, e.0); allHidden = allHidden && e.1 }
                }
                // least left for them; a snooker is worth a lot; gentle shots and fewer kick cushions are easier to get right
                let cost = worst * 10 + (allHidden ? 0 : 1.5) + Double(powers[j]) / 100 + Double(t.c.rails) * 0.4
                if best == nil || cost < best!.cost { best = (cost, k, j, worst, allHidden) }
            }
        }
        guard let b = best, let t = tries[b.k][b.j] else { return nil }
        let g = t.c.pts
        return Safety(ball: t.ball, angle: Double(b.k) * step, power: powers[b.j], ghostX: g[g.count - 2], ghostY: g[g.count - 1],
                      cuePts: t.c.pts, objPts: t.o.pts, cueStop: t.after.pts, hidden: b.hidden, oppChance: b.chance, cueRails: t.c.rails, tier: tier)
    }

    // MARK: ball in hand

    /// Where to put the cue ball: the spot (24 px grid, then the best few checked with the full sweep) whose sure
    /// shot leads the longest run. Returns the spot and its shot.
    static func handSpot(balls: [Ball], legal: Set<Int>) -> (x: Double, y: Double, pick: Found)? {
        let others = balls.filter { $0.id != 0 }
        var cands: [(Double, Double, Double)] = []
        var y = yMin + 2
        while y <= yMax - 2 {
            var x = xMin + 2
            while x <= xMax - 2 {
                if !others.contains(where: { ($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y) < (2 * R + 4) * (2 * R + 4) }),
                   let s = shots(cueX: x, cueY: y, balls: others, legal: legal, placed: true, banks: false).filter({ !$0.scratch }).first {
                    cands.append((x, y, score(s)))
                }
                x += 24
            }
            y += 24
        }
        var best: (x: Double, y: Double, pick: Found, v: Double)? = nil
        for c in cands.sorted(by: { $0.2 > $1.2 }).prefix(6) {
            let found = sweep(cueX: c.0, cueY: c.1, balls: [Ball(id: 0, x: c.0, y: c.1)] + others, legal: legal)
            guard let f0 = found.first else { continue }
            var pick = f0, v = dropChance(f0.width / 2)
            if let r = runOut(balls: others, legal: legal, firsts: found) { pick = r.pick; v = r.chance * (Double(r.count) + (r.wins ? 4 : 0)) }
            if best == nil || v > best!.v { best = (c.0, c.1, pick, v) }
        }
        return best.map { ($0.x, $0.y, $0.pick) }
    }

    // MARK: every way a ball can reach each pocket (the guide lines)

    /// For one ball: the straight line into each pocket it can reach unblocked, and for each pocket the one-cushion
    /// bank off each cushion (searched around the mirror line with the cushion law). Paths as x,y pairs.
    struct Guide: Equatable { var pocket: Int; var pts: [Double]; var dir: Double; var bank: Bool }
    static func pocketLines(_ b: Ball, balls: [Ball]) -> [Guide] {
        let others = balls.filter { $0.id != 0 && $0.id != b.id }
        var out: [Guide] = []
        func guide(_ pi: Int, _ pts: [Double], _ bank: Bool) -> Guide { Guide(pocket: pi, pts: pts, dir: atan2(pts[3] - pts[1], pts[2] - pts[0]), bank: bank) }
        for (pi, p) in pockets.enumerated() {
            var ux = p.x - b.x, uy = p.y - b.y
            let d = (ux * ux + uy * uy).squareRoot(); ux /= d; uy /= d
            let r = run(b.x, b.y, ux, uy, balls: others, skip: b.id, maxRails: 0, gap: 2 * R - 3)
            if r.pocket == pi, r.pts.count >= 4 { out.append(guide(pi, r.pts, false)) }
            for (mx, my) in [(2 * xMin - p.x, p.y), (2 * xMax - p.x, p.y), (p.x, 2 * yMin - p.y), (p.x, 2 * yMax - p.y)] {
                let a0 = atan2(my - b.y, mx - b.x)
                var best: Run? = nil
                for k in -60...60 {
                    let a = a0 + Double(k) * 0.2 * Double.pi / 180
                    let t = run(b.x, b.y, cos(a), sin(a), balls: others, skip: b.id, maxRails: 1, gap: 2 * R - 3)
                    if t.pocket == pi && t.rails == 1 && (best == nil || t.off < best!.off) { best = t }
                }
                if let t = best, t.pts.count >= 4 { out.append(guide(pi, t.pts, true)) }
            }
        }
        return out
    }
}
