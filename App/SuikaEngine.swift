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
        var fresh = false          // dropped or made by a merge (fruits read off the screen are not)
        var alive = true
        init(t: Int, x: Double, y: Double, tag: Int = 0) {
            self.t = t; self.x = x; self.y = y; self.tag = tag
            r = SuikaEngine.fitted ? SK.hit[t] : SK.radius[t] * SuikaEngine.hitScale; im = 1 / (r * r)
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
    // measured on two screen recordings (129 drops replayed): gravity from a falling fruit's path at 60 fps,
    // the rest fitted so replayed drops land and merge where the game's did
    static let g = 3490.0
    static let hitScale = 1.03      // (before 3.41: one scale for every kind)
    static var fitted = true        // per-kind collision sizes (SK.hit); false only to compare in the tests
    static let dt = 1.0 / 120
    static let iters = 10
    static let mu = 0.1             // fruits are slippery: piles slide more than they stick
    static let maxR = SK.radius.max()!

    /// strategy weights (tuned offline by Tools/SuikaSim, which plays whole games in this physics)
    struct Knobs {
        var pair = 0.6, bury = 1.5, small = 0.6, count = 0.4, wall = 0.25, combo = 0.6
        var fill = 240.0, fill0 = 0.5, ahead = 0.9, chain = 0.0, roll = 1.5
    }
    static var k = Knobs()

    /// value of making a fruit of kind k (the game scores roughly like this)
    static func made(_ k: Int) -> Double { Double(k * (k + 1)) / 2 }

    /// Runs the jar until everything stops (or maxT seconds). Merged kinds are appended to `created`.
    /// `tagX` ends as the x where the dropped fruit (tag 1) came to rest or merged.
    static func simulate(_ b: inout [Body], created: inout [Int], merge: Bool = true, maxT: Double = 3.0, damp: Double = 1) {
        var tagX = 0.0
        simulate(&b, created: &created, tagX: &tagX, merge: merge, maxT: maxT, damp: damp)
    }

    /// `damp` < 1 slows everything down (used to let the jar as read settle in place instead of rolling away)
    static func simulate(_ b: inout [Body], created: inout [Int], tagX: inout Double, merge: Bool = true, maxT: Double = 3.0, damp: Double = 1) {
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
                        // two fruits read off the screen never merge with each other: the game would already have merged
                        // them if they touched, so if they do here it's only our reading being a few pixels off
                        let same = b[i].t == b[j].t && (b[i].fresh || b[j].fresh || !merge)
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
                        // friction: take back some of the sliding along the contact made this step
                        // (without it a pile slides apart that holds in the game)
                        let tx = -ny, ty = nx
                        let slide = ((b[j].x - b[j].px) - (b[i].x - b[i].px)) * tx + ((b[j].y - b[j].py) - (b[i].y - b[i].py)) * ty
                        let cap = SuikaEngine.mu * pen
                        let f = abs(slide) <= cap ? slide : (slide > 0 ? cap : -cap)
                        b[i].x += tx * f * wi; b[i].y += ty * f * wi
                        b[j].x -= tx * f * wj; b[j].y -= ty * f * wj
                    }
                    // walls and floor
                    let r = b[i].r
                    if b[i].x < SK.left + r || b[i].x > SK.right - r {
                        let wx = b[i].x < SK.left + r ? SK.left + r : SK.right - r
                        let pen = abs(b[i].x - wx)
                        b[i].x = wx
                        let slide = b[i].y - b[i].py, cap = SuikaEngine.mu * pen
                        b[i].y -= abs(slide) <= cap ? slide : (slide > 0 ? cap : -cap)
                    }
                    // the rounded bottom corners: a fruit smaller than the curve sits further in (3.36)
                    if r < SK.corner && b[i].y > SK.floor - SK.corner {
                        let cx = b[i].x < SK.left + SK.corner ? SK.left + SK.corner : (b[i].x > SK.right - SK.corner ? SK.right - SK.corner : b[i].x)
                        let cy = SK.floor - SK.corner
                        if cx != b[i].x {
                            let dx = b[i].x - cx, dy = b[i].y - cy, d = (dx * dx + dy * dy).squareRoot(), lim = SK.corner - r
                            if d > lim && d > 1e-6 { b[i].x = cx + dx / d * lim; b[i].y = cy + dy / d * lim }
                        }
                    }
                    if b[i].y > SK.floor - r {
                        let pen = b[i].y - (SK.floor - r)
                        b[i].y = SK.floor - r
                        let slide = b[i].x - b[i].px, cap = SuikaEngine.mu * pen
                        b[i].x -= abs(slide) <= cap ? slide : (slide > 0 ? cap : -cap)
                    }
                }
            }
            var fastest = 0.0
            for i in b.indices {
                // velocity from how far it actually moved; a little damping stands in for friction
                var vx = (b[i].x - b[i].px) / dt, vy = (b[i].y - b[i].py) / dt
                // a fruit pops out of a merge, it doesn't fly off: cap the speed a big push gives
                let sp = (vx * vx + vy * vy).squareRoot()
                if sp > 1500 { vx *= 1500 / sp; vy *= 1500 / sp }
                let onFloor = b[i].y >= SK.floor - b[i].r - 0.5
                vx *= (onFloor ? 1.0 : 0.995) * damp; vy *= 0.995 * damp   // no air drag to speak of (the fall is a clean parabola)
                b[i].vx = vx; b[i].vy = vy
                fastest = max(fastest, vx * vx + vy * vy)
            }
            if !pairs.isEmpty {
                for (i, j) in pairs where b[i].alive && b[j].alive {
                    b[i].alive = false; b[j].alive = false
                    if b[i].tag == 1 { tagX = b[i].x } else if b[j].tag == 1 { tagX = b[j].x }
                    let k = b[i].t + 1
                    created.append(k)
                    if k < SK.types {
                        var n = Body(t: k, x: (b[i].x + b[j].x) / 2, y: (b[i].y + b[j].y) / 2)
                        n.vx = (b[i].vx + b[j].vx) / 2; n.vy = (b[i].vy + b[j].vy) / 2
                        n.fresh = true
                        b.append(n)
                    }
                }
                b.removeAll { !$0.alive }
                order = Array(b.indices)
                quiet = 0
            }
            if let me = b.first(where: { $0.tag == 1 }) { tagX = me.x }
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
        v -= k.fill * pow(max(0, fill - k.fill0), 2)                                      // the closer to the line the worse
        v -= k.count * Double(b.count)                                                 // fewer fruits = more room
        for f in b where f.t <= 2 { v -= k.small }   // small ones strewn about the jar block it (3.37, Atom's screenshot)
        var bigT = -1, bigI = 0
        for i in b.indices where b[i].t > bigT { bigT = b[i].t; bigI = i }
        for i in b.indices {
            for j in (i + 1)..<b.count {
                let dx = b[j].x - b[i].x, dy = b[j].y - b[i].y
                let d = (dx * dx + dy * dy).squareRoot(), rs = b[i].r + b[j].r
                if b[i].t == b[j].t {
                    // two of a kind close together: one more fruit could join them
                    if d < rs * 1.35 { v += k.pair * made(b[i].t + 1) * (1.35 - d / rs) / 0.35 }   // (0.6, 3.36: set up chains)
                } else if d < rs + 3 {
                    // neighbours one size apart: a chain waiting to happen (big next to the next-smaller)
                    if k.chain != 0 && abs(b[i].t - b[j].t) == 1 { v += k.chain * made(min(b[i].t, b[j].t) + 1) }
                    // a small fruit buried under a much bigger one is hard to reach
                    let (lo, hi) = b[i].y > b[j].y ? (i, j) : (j, i)
                    let gap = b[hi].t - b[lo].t
                    // (1.5, 3.40 — Atom: small fruits ended up buried along the floor under big ones, wasting room)
                    if gap >= 2 && b[hi].y < b[lo].y - b[lo].r * 0.3 { v -= k.bury * Double(gap) }
                }
            }
        }
        // keep the biggest fruit low and against a wall
        let f = b[bigI]
        let dWall = min(f.x - f.r - SK.left, SK.right - f.x - f.r)
        v += k.wall * made(bigT) * max(0, 1 - dWall / 300)
        return (v, fill)
    }

    private static func xs(_ t: Int, _ n: Int) -> [Double] {
        let rg = SK.dropRange(t), lo = rg.lo + 1, hi = rg.hi - 1   // only where Will can carry it (3.36)
        return (0..<n).map { lo + (hi - lo) * Double($0) / Double(n - 1) }
    }

    struct Try { var x: Double; var jar: [Body]; var created: [Int]; var v1: Double; var fill: Double; var land: (Double, Double)?; var travel: Double }

    static func drop(_ base: [Body], _ t: Int, _ x: Double, inflate: Double = 1) -> Try {
        var b = base
        var me = Body(t: t, x: x, y: SK.dropY, tag: 1)
        me.fresh = true
        b.append(me)
        if inflate != 1 { for i in b.indices { b[i].r *= inflate; b[i].im = 1 / (b[i].r * b[i].r) } }
        var created: [Int] = []
        var end = x
        simulate(&b, created: &created, tagX: &end)
        let e = eval(b)
        let gain = created.reduce(0.0) { $0 + made($1) }
        let landed = b.first { $0.tag == 1 }
        // a long roll is where the game's physics and ours part ways: prefer drops that land where they fall
        let travel = abs(end - x)
        // a chain (it bounces off one and rolls down into a merge, then that merges again) is worth more than its merges
        // one by one — Atom: the big combos are where the points are (3.35). A roll that ends in a merge isn't penalised.
        let combo = created.count >= 2 ? gain * k.combo * Double(created.count - 1) : 0
        let rollCost = created.isEmpty ? k.roll * travel / 100 : 0
        return Try(x: x, jar: b, created: created, v1: gain + combo + e.v - rollCost, fill: e.fill, land: landed.map { ($0.x, $0.y) }, travel: travel)
    }

    /// Best drop for the held fruit. `cancel` is checked between simulations.
    func think(_ st: SK.State, ms: Int, cancel: () -> Bool) -> Result? {
        guard st.held >= 0 else { return nil }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(200, ms)) * 1_000_000
        func late() -> Bool { DispatchTime.now().uptimeNanoseconds > deadline || cancel() }
        // the jar as read, settled (small reading errors would otherwise make fruits jump on the first drop)
        var base = st.fruits.map { Body(t: $0.t, x: $0.x, y: $0.y) }
        var none: [Int] = []
        SuikaEngine.simulate(&base, created: &none, merge: false, maxT: 1.5, damp: 0.6)
        for i in base.indices { base[i].vx = 0; base[i].vy = 0 }

        // 1. this drop alone, across the jar
        let pos = SuikaEngine.xs(st.held, 41)
        // every drop on its own core (3.35: one after another it took over a second on a full jar)
        var slots = [Try?](repeating: nil, count: pos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: pos.count) { k in
            if cancel() { return }
            let t = SuikaEngine.drop(base, st.held, pos[k])
            lock.lock(); slots[k] = t; lock.unlock()
        }
        if cancel() { return nil }
        var tries = slots.compactMap { $0 }
        if tries.count != pos.count { return nil }
        // 3.39 (Atom: a fruit sent through a small gap stuck at its mouth — the game's fruits collide a little bigger than
        // ours there). Every drop that merges is tried again with all fruits 6 % bigger; if it then merges less, the
        // bigger-fruit outcome is the one that counts. Gaps that really fit still win.
        var tight = [Try?](repeating: nil, count: tries.count)
        DispatchQueue.concurrentPerform(iterations: tries.count) { k in
            if tries[k].created.isEmpty || cancel() { return }
            let t = SuikaEngine.drop(base, st.held, pos[k], inflate: 1.06)
            lock.lock(); tight[k] = t; lock.unlock()
        }
        for k in tries.indices {
            if let t = tight[k], t.created.count < tries[k].created.count || t.created.max() ?? -1 < tries[k].created.max() ?? -1 {
                var w = tries[k]; w.v1 = min(w.v1, t.v1); w.created = t.created; tries[k] = w
            }
        }
        // a spot is only as good as its neighbours: you can't drop to the exact pixel
        func robust(_ k: Int, _ v: Double) -> Double {
            var r = v
            // ±2 steps (~±45 px): Atom drops by eye, not to the pixel (3.37)
            for (n, w) in [(k - 2, 0.3), (k - 1, 0.5), (k + 1, 0.5), (k + 2, 0.3)] where n >= 0 && n < tries.count { r += w * min(0, tries[n].v1 - tries[k].v1) }
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
            let pos2 = SuikaEngine.xs(st.next, 21)
            var done: [Int] = []
            let top = Array(order.prefix(10))
            var res = [(Double, Double)?](repeating: nil, count: top.count)
            DispatchQueue.concurrentPerform(iterations: top.count) { n in
                if late() { return }
                let k = top[n]
                var b2 = tries[k].jar
                for i in b2.indices { b2[i].tag = 0 }
                var bestV = -Double.infinity, bestX = 0.0
                for x in pos2 {
                    let t2 = SuikaEngine.drop(b2, st.next, x)
                    if t2.v1 > bestV { bestV = t2.v1; bestX = x }
                }
                lock.lock(); res[n] = (bestV, bestX); lock.unlock()
            }
            for (n, k) in top.enumerated() {
                guard let (bestV, bestX) = res[n] else { continue }
                let gain1 = tries[k].created.reduce(0.0) { $0 + SuikaEngine.made($1) }
                total[k] = gain1 + SuikaEngine.k.ahead * bestV + (1 - SuikaEngine.k.ahead) * tries[k].v1
                nextX[k] = bestX
                done.append(k)
            }
            if done.count == min(10, tries.count) { depth = 2 }
            // only spots looked at twice compete, so the second look decides
            if let b = done.max(by: { robust($0, total[$0]) < robust($1, total[$1]) }) { best = b }
        }
        let w = tries[best]
        return Result(x: w.x, merges: w.created, nextX: nextX[best], value: total[best], fill: w.fill,
                      land: w.land.map { (x: $0.0, y: $0.1) },
                      after: w.jar.map { SK.Fruit(t: $0.t, x: $0.x, y: $0.y) }, depth: depth)
    }
}
