import Foundation

/// Connect-K engine (เรียง 4 / เรียง 5) — Swift port of เซียน 4 in a Row:
/// window counting eval with odd/even threat parity, alpha-beta + TT, trap mode when lost.
/// p = 1 is you, p = -1 is the opponent. Cell index x = col * H + row, row 0 = bottom.
struct ConnectResult { var best = -1; var score = 0; var depth = 0; var exact = false; var trap = 0 }

final class ConnectEngine {
    let W: Int, H: Int, K: Int, N: Int
    private var b: [Int8]
    private(set) var ht: [Int]
    private var wins: [[Int]]
    private var cellW: [[Int]]
    private var cY: [Int8], cR: [Int8]
    private let WT: [Int]
    private var evalY = 0
    private(set) var played = 0
    private var Z: [UInt64]
    private var h: UInt64 = 0
    private let order: [Int]
    static let WIN = 100000
    private let BIG = Int.max / 4

    private struct TTE { var d: Int; var s: Int; var f: Int; var m: Int; var x: Bool }
    private var TT: [UInt64: TTE] = [:]
    private var nodes = 0, deadline: UInt64 = 0, stop = false, cut = false

    init(W: Int, H: Int, K: Int) {
        self.W = W; self.H = H; self.K = K; N = W * H
        b = [Int8](repeating: 0, count: W * H); ht = [Int](repeating: 0, count: W)
        var cw = [[Int]](repeating: [], count: W * H)
        var ws: [[Int]] = []
        let dirs = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for c in 0..<W { for r in 0..<H { for (dc, dr) in dirs {
            let ec = c + dc * (K - 1), er = r + dr * (K - 1)
            if ec < 0 || ec >= W || er < 0 || er >= H { continue }
            var cells: [Int] = []
            for i in 0..<K { cells.append((c + dc * i) * H + (r + dr * i)) }
            let id = ws.count; ws.append(cells)
            for x in cells { cw[x].append(id) }
        } } }
        wins = ws; cellW = cw
        cY = [Int8](repeating: 0, count: ws.count); cR = [Int8](repeating: 0, count: ws.count)
        WT = K == 4 ? [0, 1, 6, 40, 0] : [0, 1, 4, 24, 150, 0]
        var seed: UInt64 = 0x2545F4914F6CDD1D
        var z = [UInt64](repeating: 0, count: W * H * 2)
        for i in 0..<z.count { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; z[i] = seed }
        Z = z
        let mid = Double(W - 1) / 2
        order = (0..<W).sorted { (abs(Double($0) - mid), $0) < (abs(Double($1) - mid), $1) }
    }

    @inline(__always) private func contrib(_ w: Int) -> Int {
        let y = Int(cY[w]), r = Int(cR[w])
        if y > 0 && r > 0 { return 0 }
        return y > 0 ? WT[y] : (r > 0 ? -WT[r] : 0)
    }
    @discardableResult
    func play(_ c: Int, _ p: Int) -> Bool {
        let x = c * H + ht[c]
        b[x] = Int8(p); ht[c] += 1; played += 1
        h ^= Z[x * 2 + (p > 0 ? 0 : 1)]
        var won = false
        for w in cellW[x] {
            evalY -= contrib(w)
            if p > 0 { cY[w] += 1; if Int(cY[w]) == K { won = true } } else { cR[w] += 1; if Int(cR[w]) == K { won = true } }
            evalY += contrib(w)
        }
        return won
    }
    func undo(_ c: Int) {
        ht[c] -= 1
        let x = c * H + ht[c], p = Int(b[x])
        b[x] = 0; played -= 1
        h ^= Z[x * 2 + (p > 0 ? 0 : 1)]
        for w in cellW[x] {
            evalY -= contrib(w)
            if p > 0 { cY[w] -= 1 } else { cR[w] -= 1 }
            evalY += contrib(w)
        }
    }
    func winsNow(_ c: Int, _ p: Int) -> Bool {
        if ht[c] >= H { return false }
        let x = c * H + ht[c]
        for w in cellW[x] {
            let mine = Int(p > 0 ? cY[w] : cR[w]), theirs = Int(p > 0 ? cR[w] : cY[w])
            if mine == K - 1 && theirs == 0 { return true }
        }
        return false
    }

    private func leafEval(_ p: Int) -> Int {
        var s = evalY
        let first = played % 2 == 0 ? p : -p
        for w in 0..<wins.count {
            let y = Int(cY[w]), r = Int(cR[w])
            var owner = 0
            if y == K - 1 && r == 0 { owner = 1 } else if r == K - 1 && y == 0 { owner = -1 } else { continue }
            var e = -1
            for x in wins[w] where b[x] == 0 { e = x; break }
            let row = e % H
            let good = owner == first ? row % 2 == 0 : row % 2 == 1
            s += owner * (20 + (good ? 30 : 0))
        }
        return p * s
    }
    private func ordered(_ p: Int, _ first: [Int]) -> [Int] {
        var safe: [Int] = [], bad: [Int] = []
        for c in first {
            if ht[c] >= H { continue }
            var isBad = false
            if ht[c] + 1 < H { play(c, p); isBad = winsNow(c, -p); undo(c) }
            if isBad { bad.append(c) } else { safe.append(c) }
        }
        return safe + bad
    }

    private func negamax(_ p: Int, _ depth: Int, _ alphaIn: Int, _ betaIn: Int, _ ply: Int) -> Int {
        nodes += 1
        if nodes & 4095 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { stop = true }
        if stop { return 0 }
        let WIN = ConnectEngine.WIN
        if played == N { return 0 }
        for c in order where winsNow(c, p) { return WIN - ply }
        var forced = -1, nThreat = 0
        for c in order where winsNow(c, -p) { nThreat += 1; forced = c }
        if nThreat > 1 { return -(WIN - ply - 1) }
        if played + 1 == N && nThreat == 0 { return 0 }
        if depth <= 0 { cut = true; return leafEval(p) }
        var alpha = alphaIn, beta = betaIn
        let maxS = WIN - ply - 1
        if beta > maxS { beta = maxS; if alpha >= beta { return beta } }
        let k = h
        var ttm = -1
        if let e = TT[k] {
            ttm = e.m
            if e.d >= depth {
                let hit = e.f == 0 || (e.f == 1 && e.s >= beta) || (e.f == 2 && e.s <= alpha)
                if hit { if !e.x { cut = true }; return e.s }
            }
        }
        let moves = forced >= 0 ? [forced] : ordered(p, ttm >= 0 ? [ttm] + order.filter { $0 != ttm } : order)
        var best = -BIG, bm = -1
        let a0 = alpha
        let cutBefore = cut
        cut = false
        for c in moves {
            if ht[c] >= H { continue }
            play(c, p)
            let s = -negamax(-p, depth - 1, -beta, -alpha, ply + 1)
            undo(c)
            if stop { return 0 }
            if s > best { best = s; bm = c }
            if s > alpha { alpha = s }
            if alpha >= beta { break }
        }
        let nodeCut = cut
        cut = cutBefore || nodeCut
        if bm < 0 { return 0 }
        if TT.count > 800_000 { TT.removeAll(keepingCapacity: true) }
        TT[k] = TTE(d: nodeCut ? depth : 999, s: best, f: best <= a0 ? 2 : (best >= beta ? 1 : 0), m: bm, x: !nodeCut)
        return best
    }

    func search(_ p: Int, ms: Int) -> ConnectResult {
        let t0 = DispatchTime.now().uptimeNanoseconds
        deadline = t0 + UInt64(ms) * 1_000_000; stop = false; nodes = 0
        let WIN = ConnectEngine.WIN
        let legal = order.filter { ht[$0] < H }
        if legal.isEmpty { return ConnectResult() }
        for c in legal where winsNow(c, p) { return ConnectResult(best: c, score: WIN - 1, depth: 1, exact: true) }
        if played == 0 { return ConnectResult(best: order[0], score: 0, depth: 0, exact: false) }
        var res: ConnectResult? = nil
        let elapsed = { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000 }
        var d = 1
        while d <= N - played {
            cut = false
            var best = -BIG, bm = -1, alpha = -BIG
            let ro = ordered(p, res != nil ? [res!.best] + legal.filter { $0 != res!.best } : legal)
            for c in ro {
                play(c, p)
                let s = -negamax(-p, d - 1, -BIG, -alpha, 1)
                undo(c)
                if stop { break }
                if s > best { best = s; bm = c }
                if s > alpha { alpha = s }
            }
            if stop { break }
            res = ConnectResult(best: bm, score: best, depth: d, exact: !cut || abs(best) > WIN - 1000)
            if res!.exact { break }
            if elapsed() > Double(ms) * 0.5 { break }
            d += 1
        }
        guard var r = res else { return ConnectResult(best: legal[0], score: 0, depth: 0, exact: false) }
        if r.score > -(WIN - 1000) || legal.count < 2 { return r }
        // trap mode: the position is proven lost — prefer the move that gives the opponent the most ways to go wrong
        stop = false
        deadline = t0 + UInt64(Double(ms) * 0.97) * 1_000_000
        let d2 = max(2, min(r.depth - 2, 12))
        var sc: [Int: Int] = [:]
        for c in legal { play(c, p); sc[c] = -negamax(-p, d2 - 1, -BIG, BIG, 1); undo(c); if stop { return r } }
        let top = legal.map { sc[$0]! }.max()!
        let losing = top < -(WIN - 1000)
        var cands = legal.filter { losing ? sc[$0]! == top : (sc[$0]! >= top - 5 && sc[$0]! > -(WIN - 1000)) }
        if !cands.contains(r.best) && !losing && sc[r.best]! > -(WIN - 1000) { cands.append(r.best) }
        if cands.count < 2 { return r }
        var pick: (c: Int, traps: Int)? = nil
        var bestTraps = 0
        for c in cands {
            play(c, p)
            var traps = 0
            for rr in order where ht[rr] < H {
                if winsNow(rr, -p) { continue }
                play(rr, -p)
                let q = negamax(p, 6, -BIG, BIG, 2)
                undo(rr)
                if stop { undo(c); return r }
                if q > WIN - 1000 { traps += 1 }
            }
            undo(c)
            if c == r.best { bestTraps = traps }
            if pick == nil || traps > pick!.traps || (traps == pick!.traps && c == r.best) { pick = (c, traps) }
        }
        if let pk = pick, pk.c != r.best, pk.traps >= bestTraps + 1 { r.best = pk.c; r.trap = pk.traps; return r }
        r.trap = pick?.traps ?? 0
        return r
    }
}
