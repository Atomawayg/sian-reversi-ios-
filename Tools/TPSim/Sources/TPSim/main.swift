import Foundation

// Usage: TPSim <cols> <rows> <games> <A> <B>
// Strategies: random | greedy | engine | engine:<knob>=<value>,… (knobs of TPTune; depth, nodeCap, holdBonus, …)
// Model of the game (Atom, 30 Oct): each player has `cols` pictures × `rows` copies, plus one joker; all face down in the
// two maps, one tile in hand. You push your tile into the top of a column of your map (only on face down, the same picture
// or the joker; the joker goes anywhere); the bottom tile pops out: yours or the joker → you go on, else the opponent
// holds it. First with every column one picture (joker = any) wins.

let a = CommandLine.arguments
let W = Int(a[1])!, H = Int(a[2])!, games = Int(a[3])!
let specA = a[4], specB = a[5]

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

let JOKER = 1000
/// a tile: picture id (player p owns p*W ..< p*W+W) or JOKER
func owner(_ t: Int) -> Int { t == JOKER ? -1 : t / W }

struct Side { var tiles: [Int]; var up: [Bool] }

/// what player p sees of a map, as engine codes
func view(_ m: Side, _ p: Int) -> [Int] {
    (0..<W * H).map { i in
        guard m.up[i] else { return 0 }
        let t = m.tiles[i]
        if t == JOKER { return 2 }
        return owner(t) == p ? 3 + t % W : 1
    }
}
func code(_ t: Int, _ p: Int) -> Int { t == JOKER ? 2 : (owner(t) == p ? 3 + t % W : 1) }

func complete(_ m: Side, _ p: Int) -> Bool {
    for c in 0..<W {
        var face = -1
        for r in 0..<H {
            let t = m.tiles[r * W + c]
            if !m.up[r * W + c] { return false }
            if t == JOKER { continue }
            if owner(t) != p { return false }
            if face < 0 { face = t } else if face != t { return false }
        }
    }
    return true
}

func allowed(_ m: Side, _ c: Int, _ t: Int) -> Bool {
    if t == JOKER || !m.up[c] { return true }
    let top = m.tiles[c]
    return top == JOKER || top == t
}

typealias Strategy = (_ mine: Side, _ opp: Side, _ hand: Int, _ p: Int, _ rng: inout Rng) -> Int

func makeEngine(_ spec: String) -> Strategy {
    var tune = TPTune()
    if let r = spec.split(separator: ":", maxSplits: 1).dropFirst().first {
        for kv in r.split(separator: ",") {
            let p = kv.split(separator: "="); let k = String(p[0]), v = String(p[1])
            switch k {
            case "depth": tune.depth = Int(v)!
            case "nodeCap": tune.nodeCap = Int(v)!
            case "holdBonus": tune.holdBonus = Double(v)!
            case "lowBonus": tune.lowBonus = Double(v)!
            case "bottomBonus": tune.bottomBonus = Double(v)!
            case "dupShare": tune.dupShare = Double(v)!
            case "spin": tune.spin = Double(v)!
            case "nowhere": tune.nowhere = Double(v)!
            case "run": let xs = v.split(separator: "/").map { Double($0)! }
                if H == 3 { tune.run3 = xs } else if H == 4 { tune.run4 = xs } else { tune.run5 = xs }
            default: fatalError("knob \(k)")
            }
        }
    }
    let e = TilePushEngine(); e.tune = tune
    return { mine, opp, hand, p, _ in
        e.think(mine: view(mine, p), opp: view(opp, p), hand: code(hand, p), cols: W, rows: H).col
    }
}

func strategy(_ spec: String) -> Strategy {
    if spec == "random" {
        return { m, _, t, _, rng in
            let ok = (0..<W).filter { allowed(m, $0, t) }
            return ok.isEmpty ? -1 : ok[rng.int(ok.count)]
        }
    }
    if spec == "greedy" {
        // a careful human: the picture's own column; else a face-down column whose bottom is yours; else the leftmost one
        return { m, _, t, p, _ in
            let ok = (0..<W).filter { allowed(m, $0, t) }
            if ok.isEmpty { return -1 }
            if let c = ok.first(where: { m.up[$0] && m.tiles[$0] == t }) { return c }
            let mineBottom = { (c: Int) -> Bool in let i = (H - 1) * W + c; return m.up[i] && (owner(m.tiles[i]) == p || m.tiles[i] == JOKER) }
            if let c = ok.first(where: { !m.up[$0] && mineBottom($0) }) { return c }
            if let c = ok.first(where: { !m.up[$0] }) { return c }
            return ok[0]
        }
    }
    return makeEngine(spec)
}

/// one game: returns the winner (0 / 1) or -1 for a draw (move limit)
func play(_ s: [Strategy], _ seed: UInt64) -> (Int, Int) {
    var rng = Rng(s: seed | 1)
    var deck: [Int] = []
    for p in 0..<2 { for k in 0..<W { for _ in 0..<H { deck.append(p * W + k) } } }
    deck.append(JOKER)
    for i in stride(from: deck.count - 1, to: 0, by: -1) { deck.swapAt(i, rng.int(i + 1)) }
    var maps = [Side(tiles: Array(deck[0..<W * H]), up: [Bool](repeating: false, count: W * H)),
                Side(tiles: Array(deck[W * H..<2 * W * H]), up: [Bool](repeating: false, count: W * H))]
    var hand = deck[2 * W * H]
    var p = hand == JOKER ? rng.int(2) : owner(hand)
    var moves = 0
    while moves < 3000 {
        moves += 1
        var c = s[p](maps[p], maps[1 - p], hand, p, &rng)
        if c < 0 || !allowed(maps[p], c, hand) {
            // nowhere allowed (or a bad answer): the game's behaviour is unknown; take any column
            let ok = (0..<W).filter { allowed(maps[p], $0, hand) }
            c = ok.isEmpty ? rng.int(W) : ok[0]
        }
        var m = maps[p]
        let out = m.tiles[(H - 1) * W + c]
        for r in stride(from: H - 1, to: 0, by: -1) { m.tiles[r * W + c] = m.tiles[(r - 1) * W + c]; m.up[r * W + c] = m.up[(r - 1) * W + c] }
        m.tiles[c] = hand; m.up[c] = true
        maps[p] = m
        if complete(maps[p], p) { return (p, moves) }
        hand = out
        if !(out == JOKER || owner(out) == p) { p = 1 - p }
    }
    return (-1, moves)
}

let strats = [strategy(specA), strategy(specB)]
let lock = NSLock()
var winsA = 0, winsB = 0, draws = 0, totalMoves = 0
let t0 = Date()
DispatchQueue.concurrentPerform(iterations: games) { g in
    // A is player 0 in even games, player 1 in odd ones (same deal for the pair)
    let swap = g % 2 == 1
    let s = swap ? [strategy(specB), strategy(specA)] : [strategy(specA), strategy(specB)]
    let (w, n) = play(s, UInt64(g / 2) &* 0x9E3779B97F4A7C15 &+ 12345)
    lock.lock()
    totalMoves += n
    if w < 0 { draws += 1 } else if (w == 0) != swap { winsA += 1 } else { winsB += 1 }
    lock.unlock()
}
_ = strats
let n = Double(winsA + winsB)
let pct = n > 0 ? Double(winsA) / n * 100 : 0
let se = n > 0 ? (pct * (100 - pct) / n).squareRoot() : 0
print(String(format: "%dx%d %@ vs %@: A %d – B %d – draw %d  A wins %.1f%% ±%.1f  (%.0f moves/game, %.0fs)",
             W, H, specA, specB, winsA, winsB, draws, pct, se, Double(totalMoves) / Double(games), Date().timeIntervalSince(t0)))
