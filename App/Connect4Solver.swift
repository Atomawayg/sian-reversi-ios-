import Foundation

/// Perfect-play solver for 7×6 four-in-a-row (bitboards, null-window negamax with a transposition
/// table and threat-based move ordering — the classic approach that solved the game).
/// Bit layout: column c uses bits c*7 … c*7+5 (row 0 = bottom); bit c*7+6 is a sentinel.
/// Score convention (from the side to move): 0 draw, +n = win with n stones to spare, −n = loss.
final class Connect4Solver {
    static let W = 7, H = 6, H1 = 7, SIZE = 42
    static let MIN = -(SIZE / 2) + 3, MAX = (SIZE + 1) / 2 - 3
    private static let bottom: UInt64 = { var b: UInt64 = 0; for c in 0..<W { b |= 1 << UInt64(c * H1) }; return b }()
    private static let board: UInt64 = bottom &* ((1 << UInt64(H)) - 1)
    private static let order = [3, 2, 4, 1, 5, 0, 6]

    struct Pos { var cur: UInt64 = 0; var mask: UInt64 = 0; var moves = 0 }

    // transposition table: full key + small value (upper/lower bound encoding as in the classic solver)
    private static let TTN = 4_194_301   // prime
    private var tKey: UnsafeMutablePointer<UInt64>
    private var tVal: UnsafeMutablePointer<Int8>
    private var nodes = 0, deadline: UInt64 = 0
    private(set) var timedOut = false

    init() {
        tKey = .allocate(capacity: Connect4Solver.TTN); tKey.initialize(repeating: 0, count: Connect4Solver.TTN)
        tVal = .allocate(capacity: Connect4Solver.TTN); tVal.initialize(repeating: 0, count: Connect4Solver.TTN)
    }
    deinit { tKey.deallocate(); tVal.deallocate() }

    // MARK: bit tricks
    @inline(__always) static func colMask(_ c: Int) -> UInt64 { ((1 << UInt64(H)) - 1) << UInt64(c * H1) }
    @inline(__always) static func topCol(_ c: Int) -> UInt64 { 1 << UInt64(H - 1 + c * H1) }
    @inline(__always) static func winning(_ p: UInt64, _ mask: UInt64) -> UInt64 {
        var r = (p << 1) & (p << 2) & (p << 3)
        for s in [UInt64(H1), UInt64(H), UInt64(H + 2)] {
            var q = (p << s) & (p << (2 * s))
            r |= q & (p << (3 * s)); r |= q & (p >> s)
            q = (p >> s) & (p >> (2 * s))
            r |= q & (p << s); r |= q & (p >> (3 * s))
        }
        return r & (board ^ mask)
    }
    @inline(__always) static func possible(_ x: Pos) -> UInt64 { (x.mask &+ bottom) & board }
    @inline(__always) static func canWinNext(_ x: Pos) -> Bool { winning(x.cur, x.mask) & possible(x) != 0 }
    @inline(__always) static func play(_ x: Pos, _ move: UInt64) -> Pos {
        Pos(cur: x.cur ^ x.mask, mask: x.mask | move, moves: x.moves + 1)
    }
    @inline(__always) static func nonLosing(_ x: Pos) -> UInt64 {
        var pm = possible(x)
        let opp = winning(x.cur ^ x.mask, x.mask)
        let forced = pm & opp
        if forced != 0 {
            if forced & (forced - 1) != 0 { return 0 }   // two threats: lost
            pm = forced
        }
        return pm & ~(opp >> 1)                          // never play under an opponent threat
    }

    // MARK: search
    private struct Stop: Error {}

    private func negamax(_ x: Pos, _ alphaIn: Int, _ betaIn: Int) throws -> Int {
        nodes += 1
        if nodes & 8191 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { throw Stop() }
        let S = Connect4Solver.SIZE, MIN = Connect4Solver.MIN, MAX = Connect4Solver.MAX
        let next = Connect4Solver.nonLosing(x)
        if next == 0 { return -(S - x.moves) / 2 }
        if x.moves >= S - 2 { return 0 }
        var alpha = alphaIn, beta = betaIn
        let lo = -(S - 2 - x.moves) / 2
        if alpha < lo { alpha = lo; if alpha >= beta { return alpha } }
        var hi = (S - 1 - x.moves) / 2
        let key = x.cur &+ x.mask
        let ti = Int(key % UInt64(Connect4Solver.TTN))
        if tKey[ti] == key {
            let v = Int(tVal[ti])
            if v > MAX - MIN + 1 {
                let l = v + 2 * MIN - MAX - 2
                if alpha < l { alpha = l; if alpha >= beta { return alpha } }
            } else {
                hi = v + MIN - 1
            }
        }
        if beta > hi { beta = hi; if alpha >= beta { return beta } }
        // order: moves that create the most new threats first, centre columns breaking ties
        var mv: [(m: UInt64, s: Int)] = []
        mv.reserveCapacity(7)
        for c in Connect4Solver.order.reversed() {
            let m = next & Connect4Solver.colMask(c)
            if m == 0 { continue }
            let s = Connect4Solver.winning(x.cur | m, x.mask).nonzeroBitCount
            var i = mv.count
            mv.append((m, s))
            while i > 0 && mv[i - 1].s >= s { mv.swapAt(i, i - 1); i -= 1 }
        }
        for k in stride(from: mv.count - 1, through: 0, by: -1) {
            let s = -(try negamax(Connect4Solver.play(x, mv[k].m), -beta, -alpha))
            if s >= beta {
                tKey[ti] = key; tVal[ti] = Int8(s + MAX - 2 * MIN + 2)
                return s
            }
            if s > alpha { alpha = s }
        }
        tKey[ti] = key; tVal[ti] = Int8(alpha - MIN + 1)
        return alpha
    }

    /// Exact score of a position (side to move), or throws on timeout.
    private func solve(_ x: Pos) throws -> Int {
        let S = Connect4Solver.SIZE
        if Connect4Solver.canWinNext(x) { return (S + 1 - x.moves) / 2 }
        var lo = -(S - x.moves) / 2, hi = (S + 1 - x.moves) / 2
        while lo < hi {
            var med = lo + (hi - lo) / 2
            if med <= 0 && lo / 2 < med { med = lo / 2 } else if med >= 0 && hi / 2 > med { med = hi / 2 }
            let r = try negamax(x, med, med + 1)
            if r <= med { hi = r } else { lo = r }
        }
        return lo
    }

    struct Answer { var col: Int; var score: Int; var scores: [Int: Int] }

    /// cells: row-major from the top (rows × 7), 1 = side to move, 2 = opponent.
    /// Returns nil when the position can't be solved within `ms`.
    func best(cells: [Int], ms: Int) -> Answer? {
        let W = Connect4Solver.W, H = Connect4Solver.H
        guard cells.count == W * H else { return nil }
        var x = Pos()
        for c in 0..<W { for r in 0..<H {
            let v = cells[(H - 1 - r) * W + c]
            if v == 0 { continue }
            let bit: UInt64 = 1 << UInt64(c * Connect4Solver.H1 + r)
            x.mask |= bit; if v == 1 { x.cur |= bit }; x.moves += 1
        } }
        deadline = DispatchTime.now().uptimeNanoseconds + UInt64(ms) * 1_000_000
        timedOut = false; nodes = 0
        let S = Connect4Solver.SIZE
        var scores: [Int: Int] = [:]
        do {
            for c in Connect4Solver.order where x.mask & Connect4Solver.topCol(c) == 0 {
                let m = (x.mask &+ Connect4Solver.bottom) & Connect4Solver.colMask(c)
                if Connect4Solver.winning(x.cur, x.mask) & m != 0 { scores[c] = (S + 1 - x.moves) / 2; continue }
                scores[c] = -(try solve(Connect4Solver.play(x, m)))
            }
        } catch { timedOut = true; return nil }
        guard let top = scores.values.max() else { return nil }
        let col = Connect4Solver.order.first { scores[$0] == top }!
        return Answer(col: col, score: top, scores: scores)
    }
}
