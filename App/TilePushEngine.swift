import Foundation

/// Tile Push: which column to push the tile in hand into.
/// Rules (Atom, 30 Oct): the tile goes in at the top of a column, the column slides down one and its bottom tile pops out
/// into the middle. Yours (a face or the joker): you place it next. Not yours: it goes to the opponent and your turn ends.
/// A tile may only go on a face-down tile, the same face or the joker (the joker goes anywhere). A column all of one face
/// (joker = any) is done;
/// all columns done wins. The map is 3×3, 4×4 or 5 wide × 4 high: each player has one picture per column, as many of each
/// as there are rows; one joker in the game.
struct TPResult {
    var col = -1                 // from the left, -1 none possible
    var value = 0.0
    var keep = 0.0               // chance you place again after this push
    var popped = -1              // the bottom tile that pops out: -1 face down, else its TP code
    var completes = false        // this push finishes the column
    var win = false
}

/// Knobs of the search, so the simulator (Tools/TPSim) can try variants against each other.
struct TPTune {
    var run3: [Double] = [0, 4, 15, 100]              // value of a column's top run, 3 rows
    var run4: [Double] = [0, 3, 9, 20, 100]           // 4 rows
    var run5: [Double] = [0, 2, 5, 11, 22, 100]       // 5 rows
    var lowBonus = 0.5, bottomBonus = 1.5             // a tile of yours below the run (pops back to you later)
    var dupShare = 0.3                                 // a second column building the same picture
    var holdBonus = 4.0                                // still holding a tile of yours when the search stops
    var nowhere = 5.0                                  // holding a tile with nowhere to put it
    var spin = 6.0                                     // pushing a finished column round for nothing
    var depth = 5
    var nodeCap = 15000
    var giftWeight = 4.0                               // per tile of the opponent's run a popped tile of theirs extends
    var giftFinish = 40.0                              // … or when it finishes one of their columns
}

final class TilePushEngine {
    var tune = TPTune()
    typealias Grid = [Int]       // W×H cells, row-major, top row first
    /// map size (set by think; the search runs on one queue)
    static var W = 4, H = 4

    static func top(_ g: Grid, _ c: Int) -> Int { g[c] }
    static func isMine(_ v: Int) -> Bool { v >= 3 && v <= 7 }
    static func isUnknown(_ v: Int) -> Bool { v >= 8 }
    static func colCells(_ g: Grid, _ c: Int) -> [Int] { (0..<H).map { g[$0 * W + c] } }

    /// the face a column is built of and how many tiles from the top already fit it
    static func prefix(_ col: [Int]) -> (face: Int, len: Int) {
        var face = -1, len = 0
        for v in col {
            if v == 2 { len += 1; continue }
            if isMine(v) && (face < 0 || face == v) { face = v; len += 1; continue }
            break
        }
        return (face, len)
    }
    static func done(_ g: Grid, _ c: Int) -> Bool { prefix(colCells(g, c)).len == H }

    /// A finished column can still be pushed into (Atom, 30 Oct 14:20): 3 coffees + joker, push a coffee → 4 coffees and
    /// the joker pops back to you (you keep playing and can use it on another column).
    static func allowed(_ g: Grid, _ c: Int, _ t: Int) -> Bool {
        let tp = g[c]
        return tp == 0 || tp == 2 || t == 2 || tp == t
    }

    /// push t into column c: the new grid and the tile that pops out
    static func push(_ g: Grid, _ c: Int, _ t: Int) -> (Grid, Int) {
        var n = g
        let out = g[(H - 1) * W + c]
        for r in stride(from: H - 1, to: 0, by: -1) { n[r * W + c] = g[(r - 1) * W + c] }
        n[c] = t
        return (n, out)
    }

    /// How good your map is. Finished columns count most; a column's top run of one face counts more the longer it is.
    /// Two columns building the same face can't both finish (four of each), so only the better one counts in full.
    func eval(_ g: Grid) -> Double {
        let W = Self.W, H = Self.H
        // run length → value; the full column is worth most whatever the height
        let runValue: [Double] = H == 3 ? tune.run3 : (H == 4 ? tune.run4 : tune.run5)
        var byFace: [Int: [Double]] = [:]
        var total = 0.0, doneN = 0
        for c in 0..<W {
            let col = Self.colCells(g, c)
            let p = Self.prefix(col)
            if p.len == H { doneN += 1 }
            // a tile of yours lower down pops out to you later (a free extra move): small bonus
            for r in p.len..<H where col[r] == 2 || Self.isMine(col[r]) { total += r == H - 1 ? tune.bottomBonus : tune.lowBonus }
            if p.face < 0 { total += runValue[p.len] }
            else { byFace[p.face, default: []].append(runValue[p.len]) }
        }
        for (_, vs) in byFace {
            let s = vs.sorted(by: >)
            total += s[0] + s.dropFirst().reduce(0) { $0 + $1 * tune.dupShare }
        }
        if doneN == W { total += 10000 }
        return total
    }

    /// what a face-down tile can be: (code, chance). H of each of your W pictures, 1 joker, the rest is the opponent's.
    static func odds(_ g: Grid, opp: Grid, hand: Int) -> [(Int, Double)] {
        var seen: [Int: Int] = [:]
        var hidden = 0, jokerSeen = false
        for v in g + opp + (hand == 0 ? [] : [hand]) {
            if v == 0 { hidden += 1 } else if v == 2 { jokerSeen = true } else if isMine(v) { seen[v, default: 0] += 1 }
        }
        guard hidden > 0 else { return [(1, 1)] }
        var out: [(Int, Double)] = []
        var mineLeft = 0.0
        for (f, k) in seen.sorted(by: { $0.key < $1.key }) where k < H { out.append((f, Double(H - k))); mineLeft += Double(H - k) }
        // faces not seen yet: a new code each (only "different from the others" matters)
        let unseen = max(0, W - seen.count)
        var nextCode = (seen.keys.max() ?? 2) + 1
        for _ in 0..<unseen where nextCode <= 7 { out.append((nextCode, Double(H))); mineLeft += Double(H); nextCode += 1 }
        if !jokerSeen { out.append((2, 1)); mineLeft += 1 }
        let hid = Double(hidden)
        let scale = mineLeft > hid ? hid / mineLeft : 1
        var res = out.map { ($0.0, $0.1 * scale / hid) }
        let food = max(0, 1 - res.reduce(0) { $0 + $1.1 })
        if food > 0 { res.append((1, food)) }
        return res
    }

    private var nodes = 0

    /// expected value of holding tile t on map g with `depth` pushes left
    private func hold(_ g: Grid, _ t: Int, _ opp: Grid, _ depth: Int, _ p: Double) -> Double {
        nodes += 1
        var best = -Double.infinity
        for c in 0..<Self.W where Self.allowed(g, c, t) {
            best = max(best, after(g, c, t, opp, depth, p))
        }
        if best == -.infinity { return eval(g) - tune.nowhere }   // nowhere to put it
        return best
    }

    private func after(_ g: Grid, _ c: Int, _ t: Int, _ opp: Grid, _ depth: Int, _ p: Double) -> Double {
        let (n, out) = Self.push(g, c, t)
        var base = eval(n)
        // pushing a finished column round and round gets nowhere (only worth it to win the joker back)
        if Self.done(g, c) && out != 2 { base -= tune.spin }
        if base >= 10000 { return base + Double(depth) }      // won: sooner is better
        if out == 1 { return base }                            // turn over
        if Self.isUnknown(out) {                               // a picture not known yet: yours or theirs, even odds
            return 0.5 * base + 0.5 * (depth <= 1 ? base + tune.holdBonus : hold(n, out, opp, depth - 1, p * 0.5))
        }
        if depth <= 1 || p < 0.02 || nodes > tune.nodeCap {
            if out == 0 { return base + tune.holdBonus * Self.mineChance(n, opp) }
            return base + tune.holdBonus                       // still yours to place
        }
        if out == 0 {
            var e = 0.0
            for (v, q) in Self.odds(n, opp: opp, hand: 0) where q > 0 {
                e += q * (v == 1 ? base : hold(n, v, opp, depth - 1, p * q))
            }
            return e
        }
        return hold(n, out, opp, depth - 1, p)
    }

    static func mineChance(_ g: Grid, _ opp: Grid) -> Double {
        odds(g, opp: opp, hand: 0).filter { $0.0 != 1 }.reduce(0) { $0 + $1.1 }
    }

    /// gift: per column, what its bottom tile would hand the opponent if it popped (their run on it + 1, 0 nothing; TP.gift)
    func think(mine g: Grid, opp: Grid, hand t: Int, cols: Int = 4, rows: Int = 4, depth: Int? = nil, gift: [Int] = []) -> TPResult {
        let depth = depth ?? tune.depth
        Self.W = cols; Self.H = rows
        var r = TPResult()
        guard g.count == cols * rows else { return r }
        guard t == 2 || Self.isMine(t) else { return r }
        var best = -Double.infinity
        for c in 0..<Self.W where Self.allowed(g, c, t) {
            nodes = 0
            var v = after(g, c, t, opp, depth, 1)
            // handing the opponent a picture that tops one of their columns helps them
            if c < gift.count, gift[c] > 0, g[(rows - 1) * cols + c] == 1 {
                let run = gift[c] - 1
                v -= run >= rows - 1 ? tune.giftFinish : tune.giftWeight * Double(run)
            }
            if v > best + 1e-9 {
                best = v; r.col = c; r.value = v
                let (n, out) = Self.push(g, c, t)
                r.popped = out == 0 ? -1 : out
                r.keep = out == 0 ? Self.mineChance(n, opp) : (out == 1 ? 0 : (Self.isUnknown(out) ? 0.5 : 1))
                r.completes = Self.done(n, c)
                r.win = (0..<Self.W).allSatisfy { Self.done(n, $0) }
            }
        }
        return r
    }
}
