import Foundation

/// English checkers (Plato "Checkers"): 8×8, men move and capture forward only, captures are compulsory,
/// multi-jumps continue, a man that reaches the far row is crowned and the move ends, kings step one square
/// in any diagonal direction (and capture the same way).
/// Board: 64 cells row-major from the top. +1 / +2 = your man / king (you play from the bottom, moving up),
/// −1 / −2 = opponent. Search: iterative-deepening alpha-beta, transposition table, capture quiescence.
struct DraughtsMove: Equatable { var path: [Int]; var caps: [Int] }

final class DraughtsEngine {
    private var b = [Int8](repeating: 0, count: 64)
    private var hash: UInt64 = 0
    private var z = [UInt64](repeating: 0, count: 5 * 64)
    private var zSide: UInt64 = 0
    private var sideToMove: Int8 = 1

    init() {
        var s: UInt64 = 0xD1B54A32D192ED03
        func r() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
        for i in 0..<z.count { z[i] = r() }
        zSide = r()
    }
    @inline(__always) private func zi(_ p: Int8, _ i: Int) -> Int { (Int(p) + 2) * 64 + i }

    func set(_ cells: [Int], meToMove: Bool = true) {
        for i in 0..<64 { b[i] = Int8(cells[i]) }
        sideToMove = meToMove ? 1 : -1
        hash = 0
        for i in 0..<64 where b[i] != 0 { hash ^= z[zi(b[i], i)] }
        if sideToMove == -1 { hash ^= zSide }
    }

    // MARK: moves
    private static let dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    private func gen(_ s: Int8) -> [DraughtsMove] {
        var caps: [DraughtsMove] = []
        for i in 0..<64 where b[i] * s > 0 {
            var path = [i], taken: [Int] = []
            jumps(i, b[i], s, &path, &taken, &caps)
        }
        if !caps.isEmpty { return caps }
        var out: [DraughtsMove] = []
        for i in 0..<64 where b[i] * s > 0 {
            let r = i / 8, c = i % 8, king = abs(Int(b[i])) == 2
            for (dr, dc) in DraughtsEngine.dirs {
                if !king && dr != -Int(s) { continue }      // men only forward (you: up = −1)
                let rr = r + dr, cc = c + dc
                if rr < 0 || rr > 7 || cc < 0 || cc > 7 || b[rr * 8 + cc] != 0 { continue }
                out.append(DraughtsMove(path: [i, rr * 8 + cc], caps: []))
            }
        }
        return out
    }
    private func jumps(_ at: Int, _ piece: Int8, _ s: Int8, _ path: inout [Int], _ taken: inout [Int], _ out: inout [DraughtsMove]) {
        let r = at / 8, c = at % 8, king = abs(Int(piece)) == 2
        var any = false
        for (dr, dc) in DraughtsEngine.dirs {
            if !king && dr != -Int(s) { continue }
            let mr = r + dr, mc = c + dc, lr = r + 2 * dr, lc = c + 2 * dc
            if lr < 0 || lr > 7 || lc < 0 || lc > 7 { continue }
            let mid = mr * 8 + mc, land = lr * 8 + lc
            if b[mid] * s >= 0 || taken.contains(mid) { continue }
            if b[land] != 0 && land != path[0] { continue }
            any = true
            path.append(land); taken.append(mid)
            let crowned = !king && lr == (s == 1 ? 0 : 7)
            if crowned { out.append(DraughtsMove(path: path, caps: taken)) }   // crowning ends the move
            else { jumps(land, piece, s, &path, &taken, &out) }
            path.removeLast(); taken.removeLast()
        }
        if !any && !taken.isEmpty { out.append(DraughtsMove(path: path, caps: taken)) }
    }

    private struct Undo { var from: Int; var to: Int; var piece: Int8; var caps: [(Int, Int8)]; var hash: UInt64 }
    private func make(_ m: DraughtsMove) -> Undo {
        let from = m.path[0], to = m.path[m.path.count - 1], p = b[from]
        var u = Undo(from: from, to: to, piece: p, caps: [], hash: hash)
        hash ^= z[zi(p, from)]
        b[from] = 0
        for c in m.caps { u.caps.append((c, b[c])); hash ^= z[zi(b[c], c)]; b[c] = 0 }
        var np = p
        if abs(Int(p)) == 1 && to / 8 == (p > 0 ? 0 : 7) { np = p * 2 }
        b[to] = np; hash ^= z[zi(np, to)]
        sideToMove = -sideToMove; hash ^= zSide
        return u
    }
    private func unmake(_ u: Undo) {
        b[u.to] = 0
        for (c, v) in u.caps { b[c] = v }
        b[u.from] = u.piece
        sideToMove = -sideToMove
        hash = u.hash
    }

    func perft(_ d: Int) -> Int {
        if d == 0 { return 1 }
        let ms = gen(sideToMove)
        if d == 1 { return ms.count }
        var n = 0
        for m in ms { let u = make(m); n += perft(d - 1); unmake(u) }
        return n
    }

    // MARK: evaluation (from the side to move)
    private func evaluate() -> Int {
        var s = 0, mine = 0, theirs = 0, kingsM = 0, kingsT = 0
        for i in 0..<64 where b[i] != 0 {
            let p = Int(b[i]), r = i / 8, c = i % 8
            let me = p > 0
            var v: Int
            if abs(p) == 1 {
                let adv = me ? 7 - r : r                 // rows advanced
                v = 100 + adv * 3 + (adv >= 5 ? 6 : 0)
                if adv == 0 && (c == 2 || c == 6 || c == 1 || c == 5) { v += 8 }   // back-row guards
                if c == 0 || c == 7 { v -= 4 }
            } else {
                v = 155
                let cd = abs(3.5 - Double(r)) + abs(3.5 - Double(c))
                v += Int(8 - cd * 1.5)
                if me { kingsM += 1 } else { kingsT += 1 }
            }
            if c >= 2 && c <= 5 && r >= 2 && r <= 5 { v += 4 }
            if me { s += v; mine += 1 } else { s -= v; theirs += 1 }
        }
        // when ahead, trade down
        if mine > theirs && theirs > 0 { s += (mine - theirs) * 120 / (theirs + 1) }
        else if theirs > mine && mine > 0 { s -= (theirs - mine) * 120 / (mine + 1) }
        return sideToMove == 1 ? s : -s
    }

    // MARK: search
    static let WIN = 100000
    private var tt: [UInt64: (d: Int, v: Int, f: Int, m: Int)] = [:]
    private var nodes = 0, deadline: UInt64 = 0, stopped = false
    private var ply = 0
    var cancel: (() -> Bool)? = nil

    private func search(_ depth: Int, _ alphaIn: Int, _ beta: Int) -> Int {
        nodes += 1
        if nodes & 2047 == 0 && (DispatchTime.now().uptimeNanoseconds > deadline || (cancel?() ?? false)) { stopped = true }
        if stopped { return 0 }
        var ms = gen(sideToMove)
        if ms.isEmpty { return -DraughtsEngine.WIN + ply }
        let capture = !ms[0].caps.isEmpty
        if depth <= 0 && !capture { return evaluate() }
        if ply > 90 { return evaluate() }
        var alpha = alphaIn
        var ttMove = -1
        if let e = tt[hash] {
            ttMove = e.m
            if e.d >= depth {
                if e.f == 0 || (e.f == 1 && e.v >= beta) || (e.f == 2 && e.v <= alpha) { return e.v }
            }
        }
        if ttMove >= 0 && ttMove < ms.count { ms.swapAt(0, ttMove) }
        let a0 = alpha
        var best = -DraughtsEngine.WIN - 1, bestI = 0
        let nd = ms.count == 1 ? depth : depth - 1     // forced moves don't cost depth
        for (i, m) in ms.enumerated() {
            let u = make(m); ply += 1
            let v = -search(nd, -beta, -alpha)
            ply -= 1; unmake(u)
            if stopped { return 0 }
            if v > best { best = v; bestI = i }
            if v > alpha { alpha = v; if v >= beta { break } }
        }
        let idx = bestI == 0 && ttMove > 0 ? ttMove : (bestI == ttMove ? 0 : bestI)
        if tt.count > 600_000 { tt.removeAll(keepingCapacity: true) }
        tt[hash] = (depth, best, best <= a0 ? 2 : (best >= beta ? 1 : 0), idx)
        return best
    }

    struct Result { var best: DraughtsMove?; var score = 0; var depth = 0 }

    func think(ms: Int, progress: ((Result) -> Void)? = nil) -> Result {
        let t0 = DispatchTime.now().uptimeNanoseconds
        deadline = t0 + UInt64(ms) * 1_000_000
        stopped = false; nodes = 0; ply = 0
        tt.removeAll(keepingCapacity: true)
        var root = gen(sideToMove)
        var res = Result()
        guard !root.isEmpty else { return res }
        res.best = root[0]
        if root.count == 1 { return res }
        var sameBest = 0
        for d in 1...60 {
            var alpha = -DraughtsEngine.WIN - 1, bestV = -DraughtsEngine.WIN - 1, bestI = 0
            var scores: [(Int, Int)] = []
            for (i, m) in root.enumerated() {
                let u = make(m); ply = 1
                let v = -search(d - 1, -DraughtsEngine.WIN - 1, -alpha)
                ply = 0; unmake(u)
                if stopped { break }
                scores.append((i, v))
                if v > bestV { bestV = v; bestI = i }
                if v > alpha { alpha = v }
            }
            if stopped { break }
            sameBest = root[bestI] == res.best ? sameBest + 1 : 0
            res.best = root[bestI]; res.score = bestV; res.depth = d
            progress?(res)
            let order = scores.sorted { $0.1 > $1.1 }.map { root[$0.0] }
            root = order
            if abs(bestV) > DraughtsEngine.WIN - 1000 { break }
            let el = Double(DispatchTime.now().uptimeNanoseconds - t0)
            if el > Double(ms) * 1_000_000 * 0.45 { break }
            if d >= 10 && sameBest >= 6 && el > Double(ms) * 1_000_000 * 0.2 { break }
        }
        return res
    }
}
