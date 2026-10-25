import Foundation

/// AI for the fruit game: a small circle-physics simulation of the jar (gravity, walls, merging two of a kind)
/// and a search over where to drop the held fruit, looking one fruit ahead (the next fruit on the wheel).
/// The game's own physics differs a little, so answers are "best spot, give or take a few pixels".
final class SuikaEngine {
    struct Body {
        var t: Int
        var x: Double, y: Double
        var px = 0.0, py = 0.0     // position at the start of the step
        var vx = 0.0, vy = 0.0
        var r: Double, im: Double  // radius, 1 / mass
        var tag = 0                // 1 = the fruit we dropped
        var alive = true
        init(t: Int, x: Double, y: Double, tag: Int = 0) {
            self.t = t; self.x = x; self.y = y; self.tag = tag
            r = SK.radius[t]; im = 1 / (r * r)
        }
    }

    struct Result {
        var x: Double              // drop here (screen px, centre of the held fruit)
        var merges: [Int]          // kinds made by this drop, in order
        var nextX: Double?         // planned drop for the next fruit
        var value: Double
        var fill: Double           // how full the jar is afterwards (0 empty … 1 at the dashed line)
        var land: (x: Double, y: Double)?   // where the dropped fruit comes to rest when it doesn't merge
        var after: [SK.Fruit]      // the jar afterwards
        var depth: Int             // 1 = this drop only, 2 = with the next fruit
    }

    // physics
    static let g = 3200.0
    static let dt = 1.0 / 120
    static let iters = 6
    static let maxR = SK.radius.max()!

    /// value of making a fruit of kind k (the game scores roughly like this)
    static func made(_ k: Int) -> Double { Double(k * (k + 1)) / 2 }

    /// Runs the jar until everything stops (or maxT seconds). Merged kinds are appended to `created`.
    static func simulate(_ b: inout [Body], created: inout [Int], merge: Bool = true, maxT: Double = 3.0) {
        var t = 0.0, quiet = 0
        var order: [Int] = Array(b.indices)
        while t < maxT {
            for i in b.indices {
                b[i].px = b[i].x; b[i].py = b[i].y
                b[i].vy += g * dt
                b[i].x += b[i].vx * dt; b[i].y += b[i].vy * dt
            }
            var pairs: [(Int, Int)] = []
            for _ in 0..<iters {
                // sort by x so only neighbours are compared (insertion sort: the order barely changes)
                if order.count > 1 {
                    for a in 1..<order.count {
                        let k = order[a]; var c = a - 1
                        while c >= 0 && b[order[c]].x > b[k].x { order[c + 1] = order[c]; c -= 1 }
                        order[c + 1] = k
                    }
                }
                for a in 0..<order.count {
                    let i = order[a]
                    if !b[i].alive { continue }
                    var c = a + 1
                    while c < order.count {
                        let j = order[c]; c += 1
                        if b[j].x - b[i].x > b[i].r + maxR { break }
                        if !b[j].alive { continue }
                        let dx = b[j].x - b[i].x, dy = b[j].y - b[i].y
                        var rs = b[i].r + b[j].r
                        let same = b[i].t == b[j].t
                        if same && !merge { rs += 1 }   // the jar as read: two of a kind are apart, keep them apart
                        let d2 = dx * dx + dy * dy
                        if d2 >= rs * rs { continue }
                        if same && merge {
                            if !pairs.contains(where: { $0.0 == i || $0.1 == i || $0.0 == j || $0.1 == j }) { pairs.append((i, j)) }
                            continue
                        }
                        var d = d2.squareRoot(), nx = 0.0, ny = 1.0
                        if d > 1e-6 { nx = dx / d; ny = dy / d } else { d = 0 }
                        let pen = rs - d, w = b[i].im + b[j].im
                        let wi = b[i].im / w, wj = b[j].im / w
                        b[i].x -= nx * pen * wi; b[i].y -= ny * pen * wi
                        b[j].x += nx * pen * wj; b[j].y += ny * pen * wj
                    }
                    // walls and floor
                    let r = b[i].r
                    if b[i].x < SK.left + r { b[i].x = SK.left + r }
                    if b[i].x > SK.right - r { b[i].x = SK.right - r }
                    if b[i].y > SK.floor - r { b[i].y = SK.floor - r }
                }
            }
            var fastest = 0.0
            for i in b.indices {
                // velocity from how far it actually moved; a little damping stands in for friction
                var vx = (b[i].x - b[i].px) / dt, vy = (b[i].y - b[i].py) / dt
                let onFloor = b[i].y >= SK.floor - b[i].r - 0.5
                vx *= onFloor ? 0.96 : 0.985; vy *= 0.985
                b[i].vx = vx; b[i].vy = vy
                fastest = max(fastest, vx * vx + vy * vy)
            }
            if !pairs.isEmpty {
                for (i, j) in pairs where b[i].alive && b[j].alive {
                    b[i].alive = false; b[j].alive = false
                    let k = b[i].t + 1
                    created.append(k)
                    if k < SK.types {
                        var n = Body(t: k, x: (b[i].x + b[j].x) / 2, y: (b[i].y + b[j].y) / 2)
                        n.vx = (b[i].vx + b[j].vx) / 2; n.vy = (b[i].vy + b[j].vy) / 2
                        b.append(n)
                    }
                }
                b.removeAll { !$0.alive }
                order = Array(b.indices)
                quiet = 0
            }
            t += dt
            if fastest < 25 * 25 { quiet += 1; if quiet >= 12 && t > 0.25 { break } } else { quiet = 0 }
        }
    }

    /// How good a settled jar is (higher is better).
    static func eval(_ b: [Body]) -> (v: Double, fill: Double) {
        if b.isEmpty { return (0, 0) }
        var top = Double.infinity
        for f in b { top = min(top, f.y - f.r) }
        let fill = (SK.floor - top) / (SK.floor - SK.dead)
        var v = 0.0
        if top < SK.dead + 4 { v -= 5000 + 100 * (SK.dead + 4 - top) }          // over the line: game over soon
        v -= 240 * pow(max(0, fill - 0.5), 2)                                      // the closer to the line the worse
        v -= 0.4 * Double(b.count)                                                 // fewer fruits = more room
        var bigT = -1, bigI = 0
        for i in b.indices where b[i].t > bigT { bigT = b[i].t; bigI = i }
        for i in b.indices {
            for j in (i + 1)..<b.count {
                let dx = b[j].x - b[i].x, dy = b[j].y - b[i].y
                let d = (dx * dx + dy * dy).squareRoot(), rs = b[i].r + b[j].r
                if b[i].t == b[j].t {
                    // two of a kind close together: one more fruit could join them
                    if d < rs * 1.35 { v += 0.4 * made(b[i].t + 1) * (1.35 - d / rs) / 0.35 }
                } else if d < rs + 3 {
                    // a small fruit buried under a much bigger one is hard to reach
                    let (lo, hi) = b[i].y > b[j].y ? (i, j) : (j, i)
                    let gap = b[hi].t - b[lo].t
                    if gap >= 2 && b[hi].y < b[lo].y - b[lo].r * 0.3 { v -= 0.35 * Double(gap) }
                }
            }
        }
        // keep the biggest fruit low and against a wall
        let f = b[bigI]
        let dWall = min(f.x - f.r - SK.left, SK.right - f.x - f.r)
        v += 0.25 * made(bigT) * max(0, 1 - dWall / 300)
        return (v, fill)
    }

    private static func xs(_ t: Int, _ n: Int) -> [Double] {
        let r = SK.radius[t], lo = SK.left + r + 1, hi = SK.right - r - 1
        return (0..<n).map { lo + (hi - lo) * Double($0) / Double(n - 1) }
    }

    private struct Try { var x: Double; var jar: [Body]; var created: [Int]; var v1: Double; var fill: Double; var land: (Double, Double)? }

    private static func drop(_ base: [Body], _ t: Int, _ x: Double) -> Try {
        var b = base
        b.append(Body(t: t, x: x, y: SK.dropY, tag: 1))
        var created: [Int] = []
        simulate(&b, created: &created)
        let e = eval(b)
        let gain = created.reduce(0.0) { $0 + made($1) }
        let me = b.first { $0.tag == 1 }
        return Try(x: x, jar: b, created: created, v1: gain + e.v, fill: e.fill, land: me.map { ($0.x, $0.y) })
    }

    /// Best drop for the held fruit. `cancel` is checked between simulations.
    func think(_ st: SK.State, ms: Int, cancel: () -> Bool) -> Result? {
        guard st.held >= 0 else { return nil }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(200, ms)) * 1_000_000
        func late() -> Bool { DispatchTime.now().uptimeNanoseconds > deadline || cancel() }
        // the jar as read, settled (small reading errors would otherwise make fruits jump on the first drop)
        var base = st.fruits.map { Body(t: $0.t, x: $0.x, y: $0.y) }
        var none: [Int] = []
        SuikaEngine.simulate(&base, created: &none, merge: false, maxT: 1.5)
        for i in base.indices { base[i].vx = 0; base[i].vy = 0 }

        // 1. this drop alone, across the jar
        let pos = SuikaEngine.xs(st.held, 31)
        var tries: [Try] = []
        for x in pos {
            if cancel() { return nil }
            tries.append(SuikaEngine.drop(base, st.held, x))
        }
        // a spot is only as good as its neighbours: you can't drop to the exact pixel
        func robust(_ k: Int, _ v: Double) -> Double {
            var r = v
            for n in [k - 1, k + 1] where n >= 0 && n < tries.count { r += 0.5 * min(0, tries[n].v1 - tries[k].v1) }
            return r
        }
        var best = 0
        for k in tries.indices where robust(k, tries[k].v1) > robust(best, tries[best].v1) { best = k }
        var total = tries.map { $0.v1 }
        var nextX: [Double?] = Array(repeating: nil, count: tries.count)
        var depth = 1

        // 2. look one fruit ahead for the most promising spots
        if st.next >= 0 && !late() {
            let order = tries.indices.sorted { tries[$0].v1 > tries[$1].v1 }
            let pos2 = SuikaEngine.xs(st.next, 15)
            var done = Set<Int>()
            for k in order.prefix(8) {
                if late() { break }
                var b2 = tries[k].jar
                for i in b2.indices { b2[i].tag = 0 }
                let gain1 = tries[k].created.reduce(0.0) { $0 + SuikaEngine.made($1) }
                var bestV = -Double.infinity, bestX = 0.0
                for x in pos2 {
                    let t2 = SuikaEngine.drop(b2, st.next, x)
                    if t2.v1 > bestV { bestV = t2.v1; bestX = x }
                }
                total[k] = gain1 + 0.9 * bestV + 0.1 * tries[k].v1
                nextX[k] = bestX
                done.insert(k)
            }
            if done.count == min(8, tries.count) { depth = 2 }
            // only spots looked at twice compete, so the second look decides
            if let b = done.max(by: { robust($0, total[$0]) < robust($1, total[$1]) }) { best = b }
        }
        let w = tries[best]
        return Result(x: w.x, merges: w.created, nextX: nextX[best], value: total[best], fill: w.fill,
                      land: w.land.map { (x: $0.0, y: $0.1) },
                      after: w.jar.map { SK.Fruit(t: $0.t, x: $0.x, y: $0.y) }, depth: depth)
    }
}
