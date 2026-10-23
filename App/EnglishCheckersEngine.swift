import Foundation

/// English checkers (Plato): men move and capture forward only, kings move/capture one square in any
/// diagonal, captures are mandatory and multi-jumps must be finished, a man reaching the far row is
/// crowned and the move ends. Board: 64 cells, row 0 at the top; +1/+2 = your man/king (bottom, moving
/// up), -1/-2 = opponent. Search: iterative deepening alpha-beta with a transposition table.
struct ECMove: Equatable { var path: [Int]; var caps: [Int] }   // squares 0…63

struct ECResult { var best: ECMove? = nil; var score = 0; var depth = 0; var legal = 0 }

final class EnglishCheckersEngine {
    static let WIN = 100000
    var b = [Int](repeating: 0, count: 64)
    var side = 1

    private static let dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    @inline(__always) private static func on(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 8 && c >= 0 && c < 8 }

    func setup(_ board: [Int], side s: Int) { b = board; side = s }

    // MARK: moves
    func moves() -> [ECMove] {
        var caps: [ECMove] = []
        for i in 0..<64 where b[i] * side > 0 { jumps(from: i, piece: b[i], path: [i], caps: [], out: &caps) }
        if !caps.isEmpty { return caps }
        var out: [ECMove] = []
        for i in 0..<64 where b[i] * side > 0 {
            let r = i / 8, c = i % 8, king = abs(b[i]) == 2
            for (dr, dc) in EnglishCheckersEngine.dirs {
                if !king && dr != -side { continue }       // side +1 moves up (dr = -1)
                let rr = r + dr, cc = c + dc
                if EnglishCheckersEngine.on(rr, cc) && b[rr * 8 + cc] == 0 { out.append(ECMove(path: [i, rr * 8 + cc], caps: [])) }
            }
        }
        return out
    }

    private func jumps(from i: Int, piece: Int, path: [Int], caps: [Int], out: inout [ECMove]) {
        let r = i / 8, c = i % 8, king = abs(piece) == 2
        var found = false
        for (dr, dc) in EnglishCheckersEngine.dirs {
            if !king && dr != -side { continue }
            let mr = r + dr, mc = c + dc, lr = r + 2 * dr, lc = c + 2 * dc
            guard EnglishCheckersEngine.on(lr, lc) else { continue }
            let mid = mr * 8 + mc, land = lr * 8 + lc
            guard b[mid] * side < 0, !caps.contains(mid), b[land] == 0 || land == path[0] else { continue }
            found = true
            let crowned = !king && lr == (side == 1 ? 0 : 7)
            if crowned { out.append(ECMove(path: path + [land], caps: caps + [mid])) }
            else {
                // temporarily lift the piece so the path can't land on its own start square twice incorrectly
                jumps(from: land, piece: piece, path: path + [land], caps: caps + [mid], out: &out)
            }
        }
        if !found && !caps.isEmpty { out.append(ECMove(path: path, caps: caps)) }
    }

    func make(_ m: ECMove) -> (Int, [Int]) {
        let from = m.path[0], to = m.path[m.path.count - 1]
        let p = b[from]
        let saved = m.caps.map { b[$0] }
        b[from] = 0
        for s in m.caps { b[s] = 0 }
        var np = p
        if abs(p) == 1 && to / 8 == (side == 1 ? 0 : 7) { np = 2 * side }
        b[to] = np
        side = -side
        return (p, saved)
    }
    func unmake(_ m: ECMove, _ u: (Int, [Int])) {
        side = -side
        let from = m.path[0], to = m.path[m.path.count - 1]
        b[to] = 0
        b[from] = u.0
        for (k, s) in m.caps.enumerated() { b[s] = u.1[k] }
    }

    func perft(_ d: Int) -> Int {
        if d == 0 { return 1 }
        var n = 0
        for m in moves() { let u = make(m); n += perft(d - 1); unmake(m, u) }
        return n
    }

    // MARK: evaluation (side to move's view)
    func evaluate() -> Int {
        var s = 0, men = [0, 0], kings = [0, 0]
        for i in 0..<64 where b[i] != 0 {
            let v = b[i], me = v > 0 ? 1 : -1, r = i / 8, c = i % 8
            let k = me == 1 ? 0 : 1
            if abs(v) == 1 {
                men[k] += 1
                let adv = me == 1 ? 7 - r : r          // rows advanced
                s += me * (100 + adv * 3)
                if (me == 1 && r == 7) || (me == -1 && r == 0) { s += me * 8 }      // back-row guard
                if c >= 2 && c <= 5 && r >= 2 && r <= 5 { s += me * 4 }
            } else {
                kings[k] += 1
                s += me * 150
                let cd = abs(Double(c) - 3.5) + abs(Double(r) - 3.5)
                s += me * Int(10 - 2 * cd)
            }
        }
        // ahead in material: trade down
        let mat0 = men[0] * 100 + kings[0] * 150, mat1 = men[1] * 100 + kings[1] * 150
        if mat0 != mat1 && mat0 + mat1 > 0 { s += (mat0 - mat1) * 300 / (mat0 + mat1) / 3 }
        return side * s
    }

    // MARK: search
    private struct TT { var key: UInt64 = 0; var depth: Int8 = -1; var score: Int32 = 0; var flag: UInt8 = 0; var move: Int16 = -1 }
    private static let TTS = 1 << 18
    private var tt = [TT](repeating: TT(), count: EnglishCheckersEngine.TTS)
    private static let Z: [UInt64] = {
        var s: UInt64 = 0x2545F4914F6CDD1D
        return (0..<(64 * 5 + 1)).map { _ in s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    }()
    private func key() -> UInt64 {
        var h: UInt64 = side == 1 ? EnglishCheckersEngine.Z[320] : 0
        for i in 0..<64 where b[i] != 0 { h ^= EnglishCheckersEngine.Z[i * 5 + b[i] + 2] }
        return h
    }
    private var nodes = 0, deadline: UInt64 = 0, stopped = false

    private func search(_ depth: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int) -> Int {
        nodes += 1
        if nodes & 1023 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { stopped = true }
        if stopped { return 0 }
        var ms = moves()
        if ms.isEmpty { return -EnglishCheckersEngine.WIN + ply }
        let forced = !ms[0].caps.isEmpty
        if depth <= 0 && !forced { return evaluate() }
        if ply > 60 { return evaluate() }
        var alpha = alphaIn
        let k = key(), ti = Int(k & UInt64(EnglishCheckersEngine.TTS - 1))
        var ttMove = -1
        if tt[ti].key == k {
            ttMove = Int(tt[ti].move)
            if Int(tt[ti].depth) >= depth {
                let s = Int(tt[ti].score)
                if tt[ti].flag == 0 || (tt[ti].flag == 1 && s >= beta) || (tt[ti].flag == 2 && s <= alpha) { return s }
            }
        }
        if ttMove >= 0 && ttMove < ms.count { ms.swapAt(0, ttMove) }
        let nd = ms.count == 1 ? depth : depth - 1     // single replies don't cost depth
        var best = -EnglishCheckersEngine.WIN * 2, bi = 0
        let a0 = alpha
        for (i, m) in ms.enumerated() {
            let u = make(m)
            var s: Int
            if i == 0 { s = -search(nd, -beta, -alpha, ply + 1) }
            else {
                s = -search(nd, -alpha - 1, -alpha, ply + 1)
                if !stopped && s > alpha && s < beta { s = -search(nd, -beta, -alpha, ply + 1) }
            }
            unmake(m, u)
            if stopped { return 0 }
            if s > best { best = s; bi = i }
            if s > alpha { alpha = s; if alpha >= beta { break } }
        }
        // remember the index in the original order
        var orig = bi
        if ttMove >= 0 && ttMove < ms.count { if bi == 0 { orig = ttMove } else if bi == ttMove { orig = 0 } }
        tt[ti] = TT(key: k, depth: Int8(clamping: depth), score: Int32(best), flag: best <= a0 ? 2 : (best >= beta ? 1 : 0), move: Int16(orig))
        return best
    }

    func think(ms: Int) -> ECResult {
        var res = ECResult()
        let root = moves()
        res.legal = root.count
        if root.isEmpty { return res }
        res.best = root[0]
        if root.count == 1 { return res }
        let t0 = DispatchTime.now().uptimeNanoseconds
        deadline = t0 + UInt64(ms) * 1_000_000; stopped = false; nodes = 0
        var order = Array(root.indices)
        for d in 1...60 {
            var alpha = -EnglishCheckersEngine.WIN * 2, bestI = order[0], bestS = alpha
            var scored: [(Int, Int)] = []
            for (n, i) in order.enumerated() {
                let u = make(root[i])
                var s: Int
                if n == 0 { s = -search(d - 1, -EnglishCheckersEngine.WIN * 2, -alpha, 1) }
                else {
                    s = -search(d - 1, -alpha - 1, -alpha, 1)
                    if !stopped && s > alpha { s = -search(d - 1, -EnglishCheckersEngine.WIN * 2, -alpha, 1) }
                }
                unmake(root[i], u)
                if stopped { break }
                scored.append((i, s))
                if s > bestS { bestS = s; bestI = i }
                if s > alpha { alpha = s }
            }
            if stopped { break }
            res.best = root[bestI]; res.score = bestS; res.depth = d
            scored.sort { $0.1 > $1.1 }
            order = scored.map { $0.0 }
            if abs(bestS) > EnglishCheckersEngine.WIN - 500 { break }
            if DispatchTime.now().uptimeNanoseconds - t0 > UInt64(ms) * 1_000_000 / 2 { break }
        }
        return res
    }
}
