import Foundation

// Usage: SuikaSim <variant> <games> [seed]
// variant: base, or knob=value pairs joined by ',' (e.g. "pair=0.9,chain=0.5")
// The "game" is our own physics with a human-ish drop error; spawns follow the logged distribution.

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "base"
let games = args.count > 2 ? Int(args[2]) ?? 10 : 10
let seed0 = args.count > 3 ? UInt64(args[3]) ?? 1 : 1

if variant != "base" {
    for kv in variant.split(separator: ",") {
        let p = kv.split(separator: "="); guard p.count == 2, let v = Double(p[1]) else { continue }
        switch p[0] {
        case "pair": SuikaEngine.k.pair = v
        case "bury": SuikaEngine.k.bury = v
        case "small": SuikaEngine.k.small = v
        case "count": SuikaEngine.k.count = v
        case "wall": SuikaEngine.k.wall = v
        case "combo": SuikaEngine.k.combo = v
        case "fill": SuikaEngine.k.fill = v
        case "fill0": SuikaEngine.k.fill0 = v
        case "ahead": SuikaEngine.k.ahead = v
        case "chain": SuikaEngine.k.chain = v
        case "roll": SuikaEngine.k.roll = v
        default: print("unknown knob \(p[0])")
        }
    }
}

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gauss() -> Double { let u = max(1e-12, unit()), v = unit(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
}
let spawnW = [108.0, 100, 81, 81, 50]   // held kinds seen in the logs
func spawn(_ r: inout Rng) -> Int {
    var x = r.unit() * spawnW.reduce(0, +)
    for (i, w) in spawnW.enumerated() { if x < w { return i }; x -= w }
    return 0
}

var scores: [Double] = [], biggest: [Int] = [], drops: [Int] = []
let eng = SuikaEngine()
let t0 = Date()
for g in 0..<games {
    var rng = Rng(s: (seed0 &* 1_000_003 &+ UInt64(g) &* 7919) | 1)
    for _ in 0..<5 { _ = rng.next() }
    var jar: [SuikaEngine.Body] = []
    var held = spawn(&rng), next = spawn(&rng)
    var score = 0.0, big = 0, n = 0
    while n < 1500 {
        let st = SK.State(held: held, heldX: 590, next: next, fruits: jar.map { SK.Fruit(t: $0.t, x: $0.x, y: $0.y) })
        guard let r = eng.think(st, ms: 3000, cancel: { false }) else { break }
        let rg = SK.dropRange(held)
        let x = min(max(r.x + 15 * rng.gauss(), rg.lo), rg.hi)   // Atom drops by eye
        var me = SuikaEngine.Body(t: held, x: x, y: SK.dropY, tag: 1); me.fresh = true
        jar.append(me)
        for i in jar.indices { jar[i].fresh = true }   // in the real game anything touching its twin merges
        var made: [Int] = []
        SuikaEngine.simulate(&jar, created: &made, maxT: 4)
        for i in jar.indices { jar[i].tag = 0 }
        for k in made { score += SuikaEngine.made(k); big = max(big, k) }
        n += 1
        let top = jar.map { $0.y - $0.r }.min() ?? SK.floor
        if top < SK.dead { break }
        held = next; next = spawn(&rng)
    }
    scores.append(score); biggest.append(big); drops.append(n)
    print("game \(g): score \(Int(score)) biggest \(big) drops \(n)")
}
let mean = scores.reduce(0, +) / Double(max(1, scores.count))
let sd = (scores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, scores.count - 1))).squareRoot()
let melons = biggest.filter { $0 >= 9 }.count, wm = biggest.filter { $0 >= 10 }.count
print("RESULT \(variant): mean \(Int(mean)) ±\(Int(sd / Double(max(1, scores.count)).squareRoot())) · max \(Int(scores.max() ?? 0)) · melon+ \(melons)/\(games) · watermelon \(wm) · drops \(drops.reduce(0, +) / max(1, drops.count)) · \(Int(Date().timeIntervalSince(t0)))s")
