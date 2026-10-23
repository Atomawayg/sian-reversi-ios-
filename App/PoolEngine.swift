import Foundation

/// 8-ball shot chooser for WePlay Pool. Coordinates are screen pixels of a 1180×2556 screen
/// (see PoolReader). Straight-in shots only: ghost-ball aiming, clear paths, pocket entry angles,
/// and how much aiming error the shot forgives.
enum PoolEngine {
    static let R = 23.5
    static let xMin = 207.5 + R, xMax = 966.5 - R, yMin = 584 + R, yMax = 2135 - R
    static let midX = 587.0, midY = 1359.5
    struct Pocket { let name: String; let x: Double; let y: Double; let side: Bool }
    static let pockets = [
        Pocket(name: "มุมซ้ายบน", x: 203, y: 581, side: false), Pocket(name: "มุมขวาบน", x: 975, y: 581, side: false),
        Pocket(name: "กลางซ้าย", x: 187, y: 1360, side: true), Pocket(name: "กลางขวา", x: 992, y: 1360, side: true),
        Pocket(name: "มุมซ้ายล่าง", x: 203, y: 2140, side: false), Pocket(name: "มุมขวาล่าง", x: 976, y: 2139, side: false)]

    struct Ball: Equatable { var id: Int; var x: Double; var y: Double }
    struct Shot: Equatable {
        var ball: Int; var pocket: Int
        var cueX: Double; var cueY: Double            // where the cue ball is (or should be placed)
        var ghostX: Double; var ghostY: Double        // where the cue ball must be when it hits
        var cut: Double; var tolerance: Double        // degrees
        var scratch: Bool; var power: String; var placed: Bool
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

    /// All straight-in shots from a cue position, best first.
    static func shots(cueX: Double, cueY: Double, balls: [Ball], legal: Set<Int>, placed: Bool = false) -> [Shot] {
        var out: [Shot] = []
        for t in balls where legal.contains(t.id) {
            for (pi, p) in pockets.enumerated() {
                var ux = p.x - t.x, uy = p.y - t.y
                let d2 = (ux * ux + uy * uy).squareRoot(); ux /= d2; uy /= d2
                if p.side {
                    if abs(uy) > sin(55 * Double.pi / 180) { continue }       // too steep along the rail
                    if (p.x < midX) != (ux < 0) { continue }
                } else {
                    let cx: Double = p.x > midX ? 1 : -1, cy: Double = p.y > midY ? 1 : -1
                    if (ux * cx + uy * cy) / 2.0.squareRoot() < cos(62 * Double.pi / 180) { continue }
                }
                let gx = t.x - ux * 2 * R, gy = t.y - uy * 2 * R
                if gx < xMin - 2 || gx > xMax + 2 || gy < yMin - 2 || gy > yMax + 2 { continue }
                let vx = gx - cueX, vy = gy - cueY, d1 = (vx * vx + vy * vy).squareRoot()
                if d1 < 1 { continue }
                let cosCut = (vx * ux + vy * uy) / d1
                if cosCut < cos(78 * Double.pi / 180) { continue }
                if !clear(cueX, cueY, gx, gy, balls, skip: t.id, gap: 2 * R - 1) { continue }
                if !clear(t.x, t.y, p.x, p.y, balls, skip: t.id, gap: 2 * R - 3) { continue }
                let tol = (p.side ? 13.0 : 20.0) * 2 * R * cosCut / (max(d1, 2 * R) * max(d2, R))
                // scratch: after a stun hit the cue ball runs along the tangent line
                let side = vx * -uy + vy * ux > 0
                let tx = side ? -uy : uy, ty = side ? ux : -ux
                var scratch = false
                for q in pockets {
                    let wx = q.x - gx, wy = q.y - gy, along = wx * tx + wy * ty
                    if along > 0 && along < 500 && abs(wx * ty - wy * tx) < (q.side ? 21 : 28) { scratch = true }
                }
                let cut = acos(max(-1, min(1, cosCut))) * 180 / Double.pi
                let travel = d1 + d2 / max(0.3, cosCut)
                let power = travel < 700 ? "เบา" : (travel < 1400 ? "กลาง" : "แรง")
                out.append(Shot(ball: t.id, pocket: pi, cueX: cueX, cueY: cueY, ghostX: gx, ghostY: gy,
                                cut: cut, tolerance: tol * 180 / Double.pi, scratch: scratch, power: power, placed: placed))
            }
        }
        return out.sorted { score($0) > score($1) }
    }
    static func score(_ s: Shot) -> Double { s.tolerance * (s.scratch ? 0.6 : 1) }

    /// Ball in hand: try cue positions all over the table and keep the one with the easiest shot.
    static func bestPlacement(balls: [Ball], legal: Set<Int>) -> Shot? {
        var best: Shot? = nil
        var y = yMin
        while y <= yMax {
            var x = xMin
            while x <= xMax {
                if !balls.contains(where: { ($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y) < (2 * R + 4) * (2 * R + 4) }),
                   let s = shots(cueX: x, cueY: y, balls: balls, legal: legal, placed: true).first,
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

    /// Opening break: most balls still racked at the top.
    static func isBreak(_ balls: [Ball]) -> Bool {
        balls.filter { $0.id != 0 && $0.y < 1100 && $0.x > 430 && $0.x < 750 }.count >= 9
    }
}
