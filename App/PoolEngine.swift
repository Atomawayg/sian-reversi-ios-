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
    /// how far off the pocket centre a ball's line may pass and still drop
    static func mouth(_ p: Pocket) -> Double { p.side ? 20 : 27 }

    // Measured on the Oct 25 recording (cue ball tracked at 60 fps over five of your shots):
    // the cue ball leaves at about 4150 px/s × power (51 % → 2070, 54 % → 2230, 63 % → 2700 px/s),
    // and slows by (100 + 1.4·v) px/s every second (fast balls lose speed quickly, slow ones roll on).
    static let fullSpeed = 4150.0
    static let decel0 = 100.0, decelV = 1.4

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

    // MARK: rolling and power

    /// how far a ball rolls from speed v before it stops
    static func rollDistance(_ v: Double) -> Double {
        let c = decelV, a = decel0
        return v / c - a / (c * c) * log(1 + c * v / a)
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
        let pct = v0 / fullSpeed * 100
        return max(10, min(100, Int((pct / 5).rounded()) * 5))
    }

    // MARK: shots

    /// An object ball heading along (ux,uy) from (tx,ty): where it ends up. Direct into a pocket, or off one
    /// cushion into one. Returns pocket index, path length, whether it banked, and how far off the pocket
    /// centre it runs (0 = dead centre, 1 = on the edge of the mouth).
    static func trace(_ tx: Double, _ ty: Double, _ ux0: Double, _ uy0: Double, balls: [Ball], skip: Int) -> (pocket: Int, len: Double, bank: Bool, off: Double)? {
        var x = tx, y = ty, ux = ux0, uy = uy0, len = 0.0
        for leg in 0..<2 {
            // the cushion it would reach
            var tw = Double.infinity
            if ux < 0 { tw = min(tw, (xMin - x) / ux) }; if ux > 0 { tw = min(tw, (xMax - x) / ux) }
            if uy < 0 { tw = min(tw, (yMin - y) / uy) }; if uy > 0 { tw = min(tw, (yMax - y) / uy) }
            // a pocket on the way, before (or at) that cushion
            var best: (Int, Double, Double)? = nil
            for (i, p) in pockets.enumerated() {
                let wx = p.x - x, wy = p.y - y, along = wx * ux + wy * uy
                if along <= 0 || along > tw + 60 { continue }
                let perp = abs(wx * uy - wy * ux)
                if perp > mouth(p) { continue }
                if p.side && abs(uy) > sin(64 * Double.pi / 180) { continue }   // too steep into a side pocket
                if best == nil || along < best!.1 { best = (i, along, perp / mouth(p)) }
            }
            if let b = best {
                let p = pockets[b.0]
                if !clear(x, y, p.x, p.y, balls, skip: skip, gap: 2 * R - 3) { return nil }
                return (b.0, len + b.1, leg == 1, b.2)
            }
            if leg == 1 || !tw.isFinite { return nil }
            let hx = x + ux * tw, hy = y + uy * tw
            if !clear(x, y, hx, hy, balls, skip: skip, gap: 2 * R - 3) { return nil }
            len += tw
            x = hx; y = hy
            if abs(x - xMin) < 0.5 || abs(x - xMax) < 0.5 { ux = -ux } else { uy = -uy }
        }
        return nil
    }

    /// Scratch after a stun hit: the cue ball runs along the tangent line from the ghost position.
    static func scratches(cueX: Double, cueY: Double, gx: Double, gy: Double, ux: Double, uy: Double) -> Bool {
        let vx = gx - cueX, vy = gy - cueY
        let side = vx * -uy + vy * ux > 0
        let tx = side ? -uy : uy, ty = side ? ux : -ux
        for q in pockets {
            let wx = q.x - gx, wy = q.y - gy, along = wx * tx + wy * ty
            if along > 0 && along < 500 && abs(wx * ty - wy * tx) < (q.side ? 21 : 28) { return true }
        }
        return false
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
                    guard let tr = trace(t.x, t.y, ux, uy, balls: balls, skip: t.id), tr.pocket == pi, tr.bank == bank, tr.off < 0.8 else { continue }
                    let gx = t.x - ux * 2 * R, gy = t.y - uy * 2 * R
                    if gx < xMin - 2 || gx > xMax + 2 || gy < yMin - 2 || gy > yMax + 2 { continue }
                    let vx = gx - cueX, vy = gy - cueY, d1 = (vx * vx + vy * vy).squareRoot()
                    if d1 < 1 { continue }
                    let cosCut = (vx * ux + vy * uy) / d1
                    if cosCut < cos(82 * Double.pi / 180) { continue }   // thin cuts still count (the game forgives them)
                    if !clear(cueX, cueY, gx, gy, balls, skip: t.id, gap: 2 * R - 3) { continue }
                    var tol = (p.side ? 13.0 : 20.0) * 2 * R * cosCut / (max(d1, 2 * R) * max(tr.len, R))
                    if bank { tol *= 0.5 }
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
    static func judge(cueX: Double, cueY: Double, aimX: Double, aimY: Double, balls: [Ball], legal: Set<Int>) -> Verdict {
        // the aim circle sits where the cue ball touches the first ball: that ball is 2R from it
        guard let t = balls.filter({ $0.id != 0 }).min(by: { hypot($0.x - aimX, $0.y - aimY) < hypot($1.x - aimX, $1.y - aimY) }),
              hypot(t.x - aimX, t.y - aimY) < 2 * R + 8 else { return Verdict(ball: -1) }
        var v = Verdict(ball: t.id)
        v.foul = !legal.contains(t.id)
        var ux = t.x - aimX, uy = t.y - aimY
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        if let tr = trace(t.x, t.y, ux, uy, balls: balls, skip: t.id) {
            v.pocket = tr.pocket; v.bank = tr.bank; v.off = tr.off
            let vx = aimX - cueX, vy = aimY - cueY, d1 = (vx * vx + vy * vy).squareRoot()
            let cut = acos(max(-1, min(1, (vx * ux + vy * uy) / max(d1, 1e-6)))) * 180 / Double.pi
            v.powerPct = powerPct(cueToGhost: d1, objLen: tr.len, cut: cut, bank: tr.bank)
        }
        v.scratch = scratches(cueX: cueX, cueY: cueY, gx: aimX, gy: aimY, ux: ux, uy: uy)
        return v
    }


    // MARK: paths to draw

    /// Where a ball rolling from (x,y) along (ux,uy) goes: up to two legs (one cushion), stopping at a pocket,
    /// a ball in the way, or after `maxLen` px. x,y pairs.
    static func path(_ x0: Double, _ y0: Double, _ ux0: Double, _ uy0: Double, balls: [Ball], skip: Int, maxLen: Double = 2400) -> [Double] {
        var out = [x0, y0]
        var x = x0, y = y0, ux = ux0, uy = uy0, left = maxLen
        for _ in 0..<2 {
            var tw = Double.infinity
            if ux < 0 { tw = min(tw, (xMin - x) / ux) }; if ux > 0 { tw = min(tw, (xMax - x) / ux) }
            if uy < 0 { tw = min(tw, (yMin - y) / uy) }; if uy > 0 { tw = min(tw, (yMax - y) / uy) }
            var stop = min(tw, left)
            // a pocket on the way
            for p in pockets {
                let wx = p.x - x, wy = p.y - y, along = wx * ux + wy * uy
                if along > 0 && along < stop + 60 && abs(wx * uy - wy * ux) < mouth(p) { out += [p.x, p.y]; return out }
            }
            // a ball in the way (stop where it touches)
            for b in balls where b.id != skip && b.id != 0 {
                let wx = b.x - x, wy = b.y - y, along = wx * ux + wy * uy
                let perp = abs(wx * uy - wy * ux)
                if along > 0 && perp < 2 * R { let hit = along - (4 * R * R - perp * perp).squareRoot(); if hit < stop { stop = max(0, hit) } }
            }
            x += ux * stop; y += uy * stop; left -= stop
            out += [x, y]
            if stop < tw - 0.5 || left <= 0 { return out }
            if abs(x - xMin) < 0.5 || abs(x - xMax) < 0.5 { ux = -ux } else { uy = -uy }
        }
        return out
    }

    /// The object ball's path for a hit from ghost position (gx,gy).
    static func objectPath(_ bx: Double, _ by: Double, gx: Double, gy: Double, balls: [Ball], skip: Int, pocket: Pocket? = nil) -> [Double] {
        var ux = bx - gx, uy = by - gy
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        return path(bx, by, ux, uy, balls: balls, skip: skip)
    }

    /// Where the cue ball runs after a centre-ball hit: along the tangent line (a dead-straight hit stops it).
    static func cuePath(cueX: Double, cueY: Double, gx: Double, gy: Double, bx: Double, by: Double, balls: [Ball]) -> [Double] {
        var ux = bx - gx, uy = by - gy
        let d = (ux * ux + uy * uy).squareRoot(); ux /= max(d, 1e-6); uy /= max(d, 1e-6)
        let vx = gx - cueX, vy = gy - cueY
        let dv = (vx * vx + vy * vy).squareRoot()
        let along = (vx * ux + vy * uy) / max(dv, 1e-6)          // cos of the cut
        if along > 0.995 { return [] }                            // straight hit: the cue ball stops
        let side = vx * -uy + vy * ux > 0
        let tx = side ? -uy : uy, ty = side ? ux : -ux
        let len = 900 * (1 - along * along).squareRoot()          // thinner cut, more pace left on the cue ball
        return path(gx, gy, tx, ty, balls: balls, skip: 0, maxLen: len)
    }

    /// Opening break: most balls still racked at the top.
    static func isBreak(_ balls: [Ball]) -> Bool {
        balls.filter { $0.id != 0 && $0.y < 1100 && $0.x > 430 && $0.x < 750 }.count >= 9
    }
}
