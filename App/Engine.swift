import Foundation

/// Reversi search engine (port of the web app's engine).
/// Board is 10x10 padded: 0 empty, 1 black, 2 white, 3 wall/hole.
struct ThinkResult {
    var best: Int = -1
    var score: Int = 0
    var depth: Int = 0
    var exact = false
    var scores: [Int: Int] = [:]
}

final class Engine {
    private static let DIRS: [Int] = [-11, -10, -9, -1, 1, 9, 10, 11]
    private let B = UnsafeMutablePointer<Int8>.allocate(capacity: 100)
    private let NEXT = UnsafeMutablePointer<Int>.allocate(capacity: 100)
    private let PREV = UnsafeMutablePointer<Int>.allocate(capacity: 100)
    private let stack = UnsafeMutablePointer<Int>.allocate(capacity: 4096)
    private var sp = 0
    private var W = [Int](repeating: 0, count: 100)
    private var isCorner = [Bool](repeating: false, count: 100)
    private var corners: [Int] = []
    private var cadj: [(c: Int, a: Int, p: Int)] = []
    private var nodes = 0
    private var deadline: UInt64 = 0
    private var aborted = false
    private var killer = [Int](repeating: 0, count: 100)

    // Zobrist + transposition table
    private var Z = [UInt64](repeating: 0, count: 300)
    private var hash: UInt64 = 0
    private static let TTS = 1 << 18
    private var tKey = [UInt64](repeating: 0, count: Engine.TTS)
    private var tS = [Int32](repeating: 0, count: Engine.TTS)
    private var tD = [Int8](repeating: -1, count: Engine.TTS)
    private var tF = [Int8](repeating: 0, count: Engine.TTS)
    private var tM = [Int8](repeating: 0, count: Engine.TTS)

    init() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<300 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            Z[i] = seed
        }
        for i in 0..<100 { B[i] = 3; NEXT[i] = 0; PREV[i] = 0 }
    }
    deinit { B.deallocate(); NEXT.deallocate(); PREV.deallocate(); stack.deallocate() }

    @inline(__always) private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func idx(_ r: Int, _ c: Int) -> Int { (r + 1) * 10 + c + 1 }

    private func setup(_ cells: [Int8]) {
        for i in 0..<100 { B[i] = cells[i] }
        corners = []; cadj = []
        for i in 0..<100 { W[i] = 0; isCorner[i] = false }
        for r in 0..<8 { for c in 0..<8 {
            let s = Engine.idx(r, c); if B[s] == 3 { continue }
            var open = 0
            for k in 0..<4 { let d = Engine.DIRS[k]; if B[s + d] != 3 && B[s - d] != 3 { open += 1 } }
            W[s] = open == 1 ? 10 : 0
            if open == 0 { corners.append(s); isCorner[s] = true }
        } }
        for r in 0..<8 { for c in 0..<8 {
            let s = Engine.idx(r, c); if B[s] == 3 { continue }
            var nearEdge = false
            for d in Engine.DIRS where B[s + d] == 3 { nearEdge = true }
            if !nearEdge {
                for d in Engine.DIRS { let n = s + d; if B[n] != 3 && W[n] == 10 { W[s] = -3; break } }
            }
        } }
        for cn in corners {
            for d in Engine.DIRS {
                let a = cn + d
                if B[a] == 3 || isCorner[a] { continue }
                let diag = (d == 11 || d == -11 || d == 9 || d == -9)
                cadj.append((cn, a, diag ? 45 : 18))
            }
        }
        var last = 0
        for r in 0..<8 { for c in 0..<8 {
            let s = Engine.idx(r, c)
            if B[s] == 0 { NEXT[last] = s; PREV[s] = last; last = s }
        } }
        NEXT[last] = 0; PREV[0] = last
        hash = 0
        for q in 0..<100 where B[q] == 1 || B[q] == 2 { hash ^= Z[q * 3 + Int(B[q])] }
    }

    @inline(__always) private func canMove(_ s: Int, _ me: Int8, _ opp: Int8) -> Bool {
        for d in Engine.DIRS {
            var x = s + d
            if B[x] != opp { continue }
            x += d
            while B[x] == opp { x += d }
            if B[x] == me { return true }
        }
        return false
    }

    private func make(_ s: Int, _ me: Int8, _ opp: Int8) -> Int {
        var n = 0
        let zm = Int(me), zo = Int(opp)
        for d in Engine.DIRS {
            var x = s + d
            if B[x] != opp { continue }
            x += d
            while B[x] == opp { x += d }
            if B[x] != me { continue }
            x = s + d
            while B[x] == opp {
                B[x] = me; stack[sp] = x; sp += 1
                hash ^= Z[x * 3 + zo] ^ Z[x * 3 + zm]
                x += d; n += 1
            }
        }
        if n > 0 {
            B[s] = me; hash ^= Z[s * 3 + zm]
            NEXT[PREV[s]] = NEXT[s]; PREV[NEXT[s]] = PREV[s]
        }
        return n
    }

    private func unmake(_ s: Int, _ n: Int, _ me: Int8, _ opp: Int8) {
        let zm = Int(me), zo = Int(opp)
        B[s] = 0; hash ^= Z[s * 3 + zm]
        NEXT[PREV[s]] = s; PREV[NEXT[s]] = s
        for _ in 0..<n {
            sp -= 1
            let x = stack[sp]
            B[x] = opp
            hash ^= Z[x * 3 + zo] ^ Z[x * 3 + zm]
        }
    }

    private func mobility(_ me: Int8, _ opp: Int8) -> Int {
        var c = 0
        var s = NEXT[0]
        while s != 0 { if canMove(s, me, opp) { c += 1 }; s = NEXT[s] }
        return c
    }
    private func countEmpty() -> Int { var c = 0; var s = NEXT[0]; while s != 0 { c += 1; s = NEXT[s] }; return c }
    private func discDiff(_ me: Int8) -> Int {
        var d = 0
        for i in 11..<89 { let v = B[i]; if v == me { d += 1 } else if v == 3 - me { d -= 1 } }
        return d
    }
    private func terminal(_ me: Int8) -> Int {
        let dd = discDiff(me)
        return dd > 0 ? 20000 + dd : (dd < 0 ? -20000 + dd : 0)
    }

    private func evaluate(_ me: Int8, _ opp: Int8) -> Int {
        var pos = 0, front = 0
        for i in 11..<89 {
            let v = B[i]; if v != 1 && v != 2 { continue }
            var f = 0
            for d in Engine.DIRS where B[i + d] == 0 { f = 1; break }
            if v == me { pos += W[i]; front -= f } else { pos -= W[i]; front += f }
        }
        var corner = 0
        for c in corners { let cv = B[c]; if cv == me { corner += 1 } else if cv == opp { corner -= 1 } }
        for t in cadj where B[t.c] == 0 {
            let av = B[t.a]
            if av == me { pos -= t.p } else if av == opp { pos += t.p }
        }
        let mm = mobility(me, opp), om = mobility(opp, me)
        if mm == 0 && om == 0 { return terminal(me) }
        let e = countEmpty()
        let mobW = e > 40 ? 9 : (e > 20 ? 7 : 5)
        var score = 110 * corner + pos + mobW * (mm - om) + 3 * front
        if mm == 0 { score -= 30 }
        if om == 0 { score += 30 }
        if e < 12 { score += 4 * discDiff(me) }
        return score
    }

    private func negamax(_ depth: Int, _ alphaIn: Int, _ beta: Int, _ me: Int8, _ opp: Int8, _ passed: Bool) -> Int {
        nodes += 1
        if nodes & 2047 == 0 && now() > deadline { aborted = true }
        if aborted { return 0 }
        if depth <= 0 { return evaluate(me, opp) }
        var alpha = alphaIn
        let key = hash ^ (me == 1 ? 0x5BD1E9955BD1E995 : 0)
        let ti = Int(key & UInt64(Engine.TTS - 1))
        var ttMove = 0
        if tKey[ti] == key && tD[ti] >= 0 {
            ttMove = Int(tM[ti])
            if Int(tD[ti]) >= depth {
                let ts = Int(tS[ti]), tf = tF[ti]
                if tf == 0 { return ts }
                if tf == 1 && ts >= beta { return ts }
                if tf == 2 && ts <= alpha { return ts }
            }
        }
        var moves: [Int] = []
        moves.reserveCapacity(16)
        var s = NEXT[0]
        while s != 0 { if canMove(s, me, opp) { moves.append(s) }; s = NEXT[s] }
        if moves.isEmpty {
            if passed { return terminal(me) }
            return -negamax(depth - 1, -beta, -alpha, opp, me, true)
        }
        var keys = [Int](repeating: 0, count: moves.count)
        for i in 0..<moves.count {
            let m = moves[i]
            var sc = W[m] * 4 + killer[m]
            if isCorner[m] { sc += 500 }
            for t in cadj where t.a == m && B[t.c] == 0 { sc -= t.p * 3 }
            if m == ttMove { sc += 100000 }
            if depth >= 4 { let n0 = make(m, me, opp); sc -= 12 * mobility(opp, me); unmake(m, n0, me, opp) }
            keys[i] = sc
        }
        let a0 = alpha
        var best = Int.min / 2, bestM = moves[0]
        for a in 0..<moves.count {
            var bi = a
            for b2 in (a + 1)..<max(a + 1, moves.count) where keys[b2] > keys[bi] { bi = b2 }
            moves.swapAt(a, bi); keys.swapAt(a, bi)
            let mv = moves[a]
            let n = make(mv, me, opp)
            var v: Int
            if a == 0 { v = -negamax(depth - 1, -beta, -alpha, opp, me, false) }
            else {
                v = -negamax(depth - 1, -alpha - 1, -alpha, opp, me, false)
                if v > alpha && v < beta { v = -negamax(depth - 1, -beta, -alpha, opp, me, false) }
            }
            unmake(mv, n, me, opp)
            if aborted { return 0 }
            if v > best { best = v; bestM = mv }
            if v > alpha { alpha = v }
            if alpha >= beta { killer[mv] += depth * depth; break }
        }
        tKey[ti] = key; tS[ti] = Int32(clamping: best); tD[ti] = Int8(min(depth, 120)); tM[ti] = Int8(bestM)
        tF[ti] = best <= a0 ? 2 : (best >= beta ? 1 : 0)
        return best
    }

    private func solve(_ alphaIn: Int, _ beta: Int, _ me: Int8, _ opp: Int8, _ passed: Bool, _ empties: Int) -> Int {
        nodes += 1
        if nodes & 4095 == 0 && now() > deadline { aborted = true }
        if aborted { return 0 }
        if empties == 0 { return discDiff(me) }
        var alpha = alphaIn
        var best = -100, cnt = 0
        if empties > 6 {
            var moves: [Int] = [], keys: [Int] = []
            var s = NEXT[0]
            while s != 0 {
                let n = make(s, me, opp)
                if n > 0 {
                    var k = -mobility(opp, me) * 16 + W[s]
                    if isCorner[s] { k += 40 }
                    unmake(s, n, me, opp); moves.append(s); keys.append(k)
                }
                s = NEXT[s]
            }
            cnt = moves.count
            for a in 0..<cnt {
                var bi = a
                for b2 in (a + 1)..<max(a + 1, cnt) where keys[b2] > keys[bi] { bi = b2 }
                moves.swapAt(a, bi); keys.swapAt(a, bi)
                let mv = moves[a], nn = make(mv, me, opp)
                var v = a == 0 ? -solve(-beta, -alpha, opp, me, false, empties - 1)
                               : -solve(-alpha - 1, -alpha, opp, me, false, empties - 1)
                if a > 0 && v > alpha && v < beta { v = -solve(-beta, -alpha, opp, me, false, empties - 1) }
                unmake(mv, nn, me, opp)
                if aborted { return 0 }
                if v > best { best = v }
                if v > alpha { alpha = v }
                if alpha >= beta { return best }
            }
        } else {
            var s = NEXT[0]
            while s != 0 {
                let nxt = NEXT[s]
                let n = make(s, me, opp)
                if n > 0 {
                    cnt += 1
                    let v = -solve(-beta, -alpha, opp, me, false, empties - 1)
                    unmake(s, n, me, opp)
                    if v > best { best = v }
                    if v > alpha { alpha = v }
                    if alpha >= beta { return best }
                }
                s = nxt
            }
        }
        if cnt == 0 {
            if passed { return discDiff(me) }
            return -solve(-beta, -alpha, opp, me, true, empties)
        }
        return best
    }

    private func rootMoves(_ me: Int8, _ opp: Int8) -> [Int] {
        var m: [Int] = []; var s = NEXT[0]
        while s != 0 { if canMove(s, me, opp) { m.append(s) }; s = NEXT[s] }
        return m
    }

    /// Legal moves for `me` on a 100-cell board.
    func legalMoves(_ cells: [Int8], _ me: Int8) -> [Int] { setup(cells); return rootMoves(me, 3 - me) }

    func think(_ cells: [Int8], me: Int8, timeMs: Int = 1000, exactLimit: Int = 16, exactMs: Int = 3000) -> ThinkResult {
        setup(cells)
        let opp: Int8 = 3 - me
        let t0 = now()
        let moves = rootMoves(me, opp)
        nodes = 0; aborted = false
        var res = ThinkResult()
        if moves.isEmpty { return res }
        res.best = moves[0]
        let empties = countEmpty()
        if moves.count == 1 && empties > exactLimit { res.depth = 1; return res }
        if empties <= exactLimit {
            deadline = t0 + UInt64(exactMs) * 1_000_000; aborted = false
            var scores: [Int: Int] = [:]
            var bestV = -100, bestM = moves[0]
            let ordered = moves.sorted { W[$0] > W[$1] }
            for mv in ordered {
                let n = make(mv, me, opp)
                let v = -solve(-64, 64, opp, me, false, empties - 1)
                unmake(mv, n, me, opp)
                if aborted { break }
                scores[mv] = v
                if v > bestV { bestV = v; bestM = mv }
            }
            if !aborted {
                res.best = bestM; res.score = bestV; res.exact = true; res.scores = scores; res.depth = empties
                // equally good moves: choose the one where the opponent has the most ways to go wrong
                let ties = ordered.filter { scores[$0] == bestV }
                if ties.count > 1 && empties <= 13 {
                    var bestTraps = -1
                    for mv in ties {
                        let n = make(mv, me, opp)
                        var vals: [Int] = []
                        for r in rootMoves(opp, me) {
                            let n2 = make(r, opp, me)
                            vals.append(solve(-64, 64, me, opp, false, empties - 2))   // my result after their reply
                            unmake(r, n2, opp, me)
                            if aborted { break }
                        }
                        unmake(mv, n, me, opp)
                        if aborted { break }
                        let traps = vals.filter { $0 > bestV }.count   // replies that hand me more than I'm owed
                        if traps > bestTraps { bestTraps = traps; res.best = mv }
                    }
                    if aborted { res.best = bestM }
                }
                return res
            }
        }
        let start = now()
        deadline = start + UInt64(timeMs) * 1_000_000; aborted = false
        for k in 0..<100 { killer[k] = 0 }
        var order = moves
        var depth = 1
        var lastIter = 0.0
        while depth <= 60 {
            let itStart = Double(now() - start) / 1_000_000
            var alpha = Int.min / 2
            let beta = Int.max / 2
            var bm = order[0], bs = Int.min / 2
            var done = 0
            for (j, m) in order.enumerated() {
                let nn = make(m, me, opp)
                var val: Int
                if j == 0 { val = -negamax(depth - 1, -beta, -alpha, opp, me, false) }
                else {
                    val = -negamax(depth - 1, -alpha - 1, -alpha, opp, me, false)
                    if val > alpha { val = -negamax(depth - 1, -beta, -alpha, opp, me, false) }
                }
                unmake(m, nn, me, opp)
                if aborted { break }
                done += 1
                if val > bs { bs = val; bm = m }
                if val > alpha { alpha = val }
            }
            if aborted {
                if done > 1 && bm != order[0] && bs > res.score { res.best = bm; res.score = bs }
                break
            }
            res.best = bm; res.score = bs; res.depth = depth
            order.removeAll { $0 == bm }; order.insert(bm, at: 0)
            if abs(bs) >= 19000 || depth >= empties { break }
            // start another iteration only if it is likely to finish (the old rule quit at 55% of the time)
            let el = Double(now() - start) / 1_000_000, it = el - itStart
            let growth = lastIter > 0.5 ? min(8, max(1.5, it / lastIter)) : 3
            if el + it * growth > Double(timeMs) * 0.95 { break }
            lastIter = it
            depth += 1
        }
        return res
    }
}
