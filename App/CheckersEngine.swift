import Foundation

/// Thai checkers (หมากฮอส) engine — Swift port of เซียนฮอส engine v3:
/// bitboards, tuned evaluation, PVS + LMR, endgame tablebase.
/// Side +1 = you (bottom, men move up). Board: 32 playable squares, s = row*4 + k, row 0 = top.
struct CheckersMove { var from: Int; var to: Int; var caps: UInt32; var promo: Bool }
struct CheckersResult {
    var best: CheckersMove?
    var score = 0
    var depth = 0
    var tb: Int? = nil
    var instant: String? = nil
    var trap = 0   // replies that look fine to the opponent but lose
}

final class CheckersEngine {
    // geometry
    private var S64 = [Int](), IDX = [Int](repeating: -1, count: 64)
    private var ROW = [Int](repeating: 0, count: 32), COL = [Int](repeating: 0, count: 32)
    private var NB = [[Int]](repeating: [Int](repeating: -1, count: 32), count: 4)
    private var BIT = [UInt32](repeating: 0, count: 32)
    private var ROWM = [UInt32](repeating: 0, count: 8)
    private var CENTER: UInt32 = 0, EDGE: UInt32 = 0, MAIND: UInt32 = 0, DBLD: UInt32 = 0
    private var CONEU = [UInt32](repeating: 0, count: 32), CONED = [UInt32](repeating: 0, count: 32)
    private static let DIRS = [(-1, -1), (-1, 1), (1, -1), (1, 1)]

    // state: 0 W men (side +1), 1 W kings, 2 B men (side -1), 3 B kings
    private var P = [UInt32](repeating: 0, count: 4)
    private var H: UInt64 = 0
    private var Z = [UInt64](repeating: 0, count: 128)
    private var ZS: UInt64 = 0

    // move buffers
    private static let MAXPLY = 128, MAXM = 128
    private var MF = [Int](repeating: 0, count: 128 * 128)
    private var MT = [Int](repeating: 0, count: 128 * 128)
    private var MC = [UInt32](repeating: 0, count: 128 * 128)
    private var MP = [Bool](repeating: false, count: 128 * 128)
    private var MO = [Int](repeating: 0, count: 128 * 128)
    private var MN = [Int](repeating: 0, count: 128)
    private var gbase = 0, gcnt = 0, gfrom = 0, gopp: UInt32 = 0, gocc: UInt32 = 0, gpromo = 0

    var kingRule = 0 // 0: follow-up captures adjacent only (WePlay), 1: not same direction, 2: any

    // tuned weights (from self-play), same as the web app
    private let W: [Double] = [210, 9, 12, 44, 23, -50, 31.5, 1, -2, 6, -45, 310, -25, 8]
    private var F = [Double](repeating: 0, count: 14)

    // tablebase
    private var TB: [Int: [UInt8]] = [:]

    // search
    static let MATE = 100000
    private let INF = 1_000_000_000
    private static let TTS = 1 << 20
    private var tk = [UInt64](repeating: 0, count: CheckersEngine.TTS)
    private var tsc = [Int32](repeating: 0, count: CheckersEngine.TTS)
    private var tdep = [Int8](repeating: -2, count: CheckersEngine.TTS)
    private var tfl = [Int8](repeating: 0, count: CheckersEngine.TTS)
    private var tmv = [Int32](repeating: 0, count: CheckersEngine.TTS)
    private var K1 = [Int32](repeating: 0, count: 128), K2 = [Int32](repeating: 0, count: 128)
    private var HIST = [Int](repeating: 0, count: 1024)
    private var nodes = 0
    private var deadline: UInt64 = 0
    private var stop = false
    private var SV = [UInt32](repeating: 0, count: 128 * 4)
    private var SVH = [UInt64](repeating: 0, count: 128)

    init() {
        for r in 0..<8 { for c in 0..<8 where (r + c) & 1 == 1 { IDX[r * 8 + c] = S64.count; S64.append(r * 8 + c) } }
        for s in 0..<32 { ROW[s] = S64[s] >> 3; COL[s] = S64[s] & 7; BIT[s] = UInt32(1) << UInt32(s) }
        for d in 0..<4 { for s in 0..<32 {
            let r = ROW[s] + CheckersEngine.DIRS[d].0, c = COL[s] + CheckersEngine.DIRS[d].1
            NB[d][s] = (r >= 0 && r < 8 && c >= 0 && c < 8) ? IDX[r * 8 + c] : -1
        } }
        for s in 0..<32 {
            ROWM[ROW[s]] |= BIT[s]
            let r = ROW[s], c = COL[s]
            if c >= 2 && c <= 5 { CENTER |= BIT[s] }
            if c == 0 || c == 7 { EDGE |= BIT[s] }
            if r + c == 7 { MAIND |= BIT[s] }
            if r - c == 1 || c - r == 1 { DBLD |= BIT[s] }
        }
        for s in 0..<32 { for t in 0..<32 {
            let dr = ROW[s] - ROW[t], dc = abs(COL[s] - COL[t])
            if dr > 0 && dc <= dr { CONEU[s] |= BIT[t] }
            if -dr > 0 && dc <= -dr { CONED[s] |= BIT[t] }
        } }
        var seed: UInt64 = 0x1F2E3D4C5B6A7988
        func rnd() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
        for i in 0..<128 { Z[i] = rnd() }
        ZS = rnd()
    }

    @inline(__always) private func pc(_ x: UInt32) -> Int { x.nonzeroBitCount }
    @inline(__always) private func lsb(_ x: UInt32) -> Int { x.trailingZeroBitCount }
    @inline(__always) private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    // MARK: tablebase
    func loadTB(_ data: Data) {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        guard b.count > 2 else { return }
        var o = 0
        let n = u16(o); o += 2
        for _ in 0..<n {
            guard o + 6 <= b.count else { break }
            let k = u16(o); o += 2
            let len = u32(o); o += 4
            guard o + len <= b.count else { break }
            TB[k] = Array(b[o..<(o + len)]); o += len
        }
    }
    private func tbProbe(_ side: Int) -> Int {
        if TB.isEmpty || kingRule != 0 { return -1 }
        let own = side == 1 ? [P[0], P[1]] : [P[2], P[3]]
        let opp = side == 1 ? [P[2], P[3]] : [P[0], P[1]]
        let n0 = pc(own[0]), n1 = pc(own[1]), n2 = pc(opp[0]), n3 = pc(opp[1])
        let n = n0 + n1 + n2 + n3
        if !(n <= 3 || (n == 4 && n0 == 0 && n2 == 0)) { return -1 }
        guard let arr = TB[n0 * 1000 + n1 * 100 + n2 * 10 + n3] else { return -1 }
        var idx = 0, mul = 1
        for m in [own[0], own[1], opp[0], opp[1]] {
            if side == 1 {
                var x = m
                while x != 0 { let s = lsb(x); x &= x - 1; idx += s * mul; mul *= 32 }
            } else {
                var s = 31
                while s >= 0 { if m & BIT[s] != 0 { idx += (31 - s) * mul; mul *= 32 }; s -= 1 }
            }
        }
        return idx < arr.count ? Int(arr[idx]) : -1
    }

    // MARK: state
    private func rehash(_ side: Int) {
        H = side == 1 ? ZS : 0
        for t in 0..<4 { var x = P[t]; while x != 0 { let s = lsb(x); x &= x - 1; H ^= Z[t * 32 + s] } }
    }
    /// b: 32 values — 1 your man, 2 your king, -1 opponent man, -2 opponent king
    private func setFrom32(_ b: [Int], _ side: Int) {
        P = [0, 0, 0, 0]
        for s in 0..<32 {
            switch b[s] { case 1: P[0] |= BIT[s]; case 2: P[1] |= BIT[s]; case -1: P[2] |= BIT[s]; case -2: P[3] |= BIT[s]; default: break }
        }
        rehash(side)
    }

    // MARK: move generation
    private func emit(_ t: Int, _ caps: UInt32, _ promo: Bool) {
        for i in gbase..<(gbase + gcnt) where MF[i] == gfrom && MT[i] == t && MC[i] == caps { return }
        if gcnt >= CheckersEngine.MAXM { return }
        let i = gbase + gcnt
        MF[i] = gfrom; MT[i] = t; MC[i] = caps; MP[i] = promo; gcnt += 1
    }
    private func manCaps(_ s: Int, _ caps: UInt32, _ d0: Int, _ d1: Int) {
        var found = false
        for k in 0..<2 {
            let d = k == 1 ? d1 : d0
            let n1 = NB[d][s]; if n1 < 0 { continue }
            let b1 = BIT[n1]
            if gopp & b1 == 0 || caps & b1 != 0 { continue }
            let n2 = NB[d][n1]; if n2 < 0 || gocc & BIT[n2] != 0 { continue }
            found = true
            let nc = caps | b1
            if ROW[n2] == gpromo { emit(n2, nc, true) } else { manCaps(n2, nc, d0, d1) }
        }
        if !found && caps != 0 { emit(s, caps, false) }
    }
    private func kingCaps(_ s: Int, _ caps: UInt32, _ ld: Int) {
        var found = false
        for d in 0..<4 {
            if caps != 0 && kingRule == 1 && d == ld { continue }
            let nb = NB[d]
            var t = nb[s]
            if !(caps != 0 && kingRule == 0) { while t >= 0 && gocc & BIT[t] == 0 { t = nb[t] } }
            if t < 0 { continue }
            let bt = BIT[t]
            if gopp & bt == 0 || caps & bt != 0 { continue }
            let land = nb[t]; if land < 0 || gocc & BIT[land] != 0 { continue }
            found = true
            kingCaps(land, caps | bt, d)
        }
        if !found && caps != 0 { emit(s, caps, false) }
    }
    @discardableResult
    private func gen(_ side: Int, _ ply: Int) -> Int {
        gbase = ply * CheckersEngine.MAXM; gcnt = 0
        let men = side == 1 ? P[0] : P[2], kings = side == 1 ? P[1] : P[3]
        gopp = side == 1 ? (P[2] | P[3]) : (P[0] | P[1])
        let all = P[0] | P[1] | P[2] | P[3]
        let d0 = side == 1 ? 0 : 2, d1 = side == 1 ? 1 : 3
        gpromo = side == 1 ? 0 : 7
        var x = men
        while x != 0 {
            let s = lsb(x); x &= x - 1
            for k in 0..<2 {
                let d = k == 1 ? d1 : d0
                let n1 = NB[d][s]; if n1 < 0 || gopp & BIT[n1] == 0 { continue }
                let n2 = NB[d][n1]; if n2 < 0 || all & BIT[n2] != 0 { continue }
                gfrom = s; gocc = all & ~BIT[s]; manCaps(s, 0, d0, d1); break
            }
        }
        x = kings
        while x != 0 {
            let s = lsb(x); x &= x - 1
            gfrom = s; gocc = all & ~BIT[s]
            var can = false
            for d in 0..<4 where !can {
                let nb = NB[d]; var t = nb[s]
                while t >= 0 && all & BIT[t] == 0 { t = nb[t] }
                if t >= 0 && gopp & BIT[t] != 0 { let l = nb[t]; if l >= 0 && all & BIT[l] == 0 { can = true } }
            }
            if can { kingCaps(s, 0, -1) }
        }
        if gcnt > 0 { MN[ply] = gcnt; return gcnt }
        x = men
        while x != 0 {
            let s = lsb(x); x &= x - 1
            for k in 0..<2 {
                let t = NB[k == 1 ? d1 : d0][s]
                if t >= 0 && all & BIT[t] == 0 {
                    let i = gbase + gcnt; gcnt += 1
                    MF[i] = s; MT[i] = t; MC[i] = 0; MP[i] = ROW[t] == gpromo
                }
            }
        }
        x = kings
        while x != 0 {
            let s = lsb(x); x &= x - 1
            for d in 0..<4 {
                let nb = NB[d]; var t = nb[s]
                while t >= 0 && all & BIT[t] == 0 {
                    let i = gbase + gcnt; gcnt += 1
                    MF[i] = s; MT[i] = t; MC[i] = 0; MP[i] = false
                    t = nb[t]
                }
            }
        }
        MN[ply] = gcnt
        return gcnt
    }

    private func make(_ i: Int, _ ply: Int) {
        let o = ply * 4
        SV[o] = P[0]; SV[o + 1] = P[1]; SV[o + 2] = P[2]; SV[o + 3] = P[3]; SVH[ply] = H
        let f = MF[i], t = MT[i], caps = MC[i], bf = BIT[f]
        var ty = P[0] & bf != 0 ? 0 : (P[1] & bf != 0 ? 1 : (P[2] & bf != 0 ? 2 : 3))
        P[ty] &= ~bf; H ^= Z[ty * 32 + f]
        var c = caps
        while c != 0 {
            let s = lsb(c); c &= c - 1
            let b = BIT[s]
            for u in 0..<4 where P[u] & b != 0 { P[u] &= ~b; H ^= Z[u * 32 + s]; break }
        }
        if MP[i] { ty = ty == 0 ? 1 : 3 }
        P[ty] |= BIT[t]; H ^= Z[ty * 32 + t] ^ ZS
    }
    private func unmake(_ ply: Int) {
        let o = ply * 4
        P[0] = SV[o]; P[1] = SV[o + 1]; P[2] = SV[o + 2]; P[3] = SV[o + 3]; H = SVH[ply]
    }

    // MARK: evaluation (from side +1's point of view)
    private func evaluate(_ side: Int) -> Int {
        let w = P[0], wk = P[1], b = P[2], bk = P[3], all = w | wk | b | bk
        let nw = pc(w), nb = pc(b), nwk = pc(wk), nbk = pc(bk)
        var advW = 0, advB = 0, qW = 0, qB = 0
        for r in 0..<8 {
            let a = pc(w & ROWM[r]), c = pc(b & ROWM[r])
            advW += a * (7 - r); advB += c * r; qW += a * (7 - r) * (7 - r); qB += c * r * r
        }
        F[0] = Double(nwk - nbk); F[1] = Double(advW - advB); F[2] = Double(qW - qB) / 8
        F[3] = Double((nb > 0 ? pc(w & ROWM[7]) : 0) - (nw > 0 ? pc(b & ROWM[0]) : 0))
        F[4] = Double(pc(w & CENTER) - pc(b & CENTER))
        var rw = 0, rb = 0, raw = 0, rab = 0
        if bk == 0 {
            var x = w & (ROWM[0] | ROWM[1] | ROWM[2] | ROWM[3] | ROWM[4])
            while x != 0 { let s = lsb(x); x &= x - 1; if CONEU[s] & (b | bk) == 0 { rw += 1; raw += 7 - ROW[s] } }
        }
        if wk == 0 {
            var x = b & (ROWM[3] | ROWM[4] | ROWM[5] | ROWM[6] | ROWM[7])
            while x != 0 { let s = lsb(x); x &= x - 1; if CONED[s] & (w | wk) == 0 { rb += 1; rab += ROW[s] } }
        }
        F[5] = Double(rw - rb); F[6] = Double(raw - rab)
        var mobW = 0, mobB = 0, trW = 0, trB = 0
        var x = wk
        while x != 0 {
            let s = lsb(x); x &= x - 1; var m = 0
            for d in 0..<4 { let n = NB[d]; var t = n[s]; while t >= 0 && all & BIT[t] == 0 { m += 1; t = n[t] } }
            mobW += m; if m == 0 { trW += 1 }
        }
        x = bk
        while x != 0 {
            let s = lsb(x); x &= x - 1; var m = 0
            for d in 0..<4 { let n = NB[d]; var t = n[s]; while t >= 0 && all & BIT[t] == 0 { m += 1; t = n[t] } }
            mobB += m; if m == 0 { trB += 1 }
        }
        F[7] = Double(mobW - mobB); F[8] = Double(pc(wk & MAIND) - pc(bk & MAIND)); F[9] = Double(pc(wk & DBLD) - pc(bk & DBLD))
        F[10] = Double(trW - trB)
        let tot = nw + nb + nwk + nbk
        let matd = Double(nw - nb) * 100 + Double(nwk - nbk) * W[0]
        F[11] = matd * Double(24 - tot) / 4000
        F[12] = Double(pc(w & EDGE) - pc(b & EDGE)); F[13] = Double(side)
        var s = Double(nw - nb) * 100
        for i in 0..<14 { s += W[i] * F[i] }
        return Int(s.rounded())
    }

    // MARK: search
    @inline(__always) private func mkey(_ i: Int) -> Int32 {
        Int32(truncatingIfNeeded: MF[i] | (MT[i] << 5)) ^ (Int32(bitPattern: MC[i]) &* 31)
    }
    private func pieces() -> Int { pc(P[0] | P[1] | P[2] | P[3]) }

    /// WePlay's count: when one side has exactly 1 king + 1 man and the other a lone king, each side gets 8
    /// more moves, then the game is a draw. Returns the side with the king + man, or 0.
    static let countMoves = 8
    private func countSide() -> Int {
        if pc(P[0]) == 1 && pc(P[1]) == 1 && P[2] == 0 && pc(P[3]) == 1 { return 1 }
        if pc(P[2]) == 1 && pc(P[3]) == 1 && P[0] == 0 && pc(P[1]) == 1 { return -1 }
        return 0
    }
    /// Our moves still allowed under the count at the root (set by the app; 0 = the count is not running,
    /// −1 = ignore the count, for tests).
    var countLeft = 0
    /// Score the count inside the search too (3.43: measured weaker — off; the root still obeys a running count).
    var countInSearch = false

    private func negamax(_ side: Int, _ depth: Int, _ alphaIn: Int, _ betaIn: Int, _ ply: Int) -> Int {
        nodes += 1
        if nodes & 2047 == 0 && now() > deadline { stop = true }
        if stop { return 0 }
        let MATE = CheckersEngine.MATE
        if !TB.isEmpty && ply > 0 && pieces() <= 4 {
            let v = tbProbe(side)
            if v >= 0 {
                if v == 0 { return 0 }
                // entering the counted ending: a win that needs more than 8 of the winner's moves is a draw
                let cs = countInSearch ? countSide() : 0
                if cs != 0 {
                    let winner = v < 128 ? side : -side
                    let movesNeeded = v < 128 ? (v + 1) / 2 : (v - 128) / 2
                    if winner == cs && movesNeeded > CheckersEngine.countMoves { return 0 }
                }
                if v < 128 { return MATE - ply - v }; return -(MATE - ply - (v - 128))
            }
        }
        if ply >= CheckersEngine.MAXPLY - 2 { return side * evaluate(side) }
        let n = gen(side, ply)
        if n == 0 { return -MATE + ply }
        let base = ply * CheckersEngine.MAXM
        let cap = MC[base] != 0
        if depth <= 0 && !cap { return side * evaluate(side) }
        var alpha = alphaIn, beta = betaIn
        if alpha < -MATE + ply { alpha = -MATE + ply }
        if beta > MATE - ply - 1 { beta = MATE - ply - 1 }
        if alpha >= beta { return alpha }
        let ti = Int(H & UInt64(CheckersEngine.TTS - 1))
        var ttm: Int32 = -1
        if tk[ti] == H && tdep[ti] > -2 {
            ttm = tmv[ti]
            if Int(tdep[ti]) >= depth {
                var s = Int(tsc[ti])
                if s > MATE - 1000 { s -= ply } else if s < -MATE + 1000 { s += ply }
                let f = tfl[ti]
                if f == 0 || (f == 1 && s >= beta) || (f == 2 && s <= alpha) { return s }
            }
        }
        for j in 0..<n {
            let i = base + j, k = mkey(i)
            var o = (k == ttm ? 1 << 29 : 0) + pc(MC[i]) * (1 << 22) + (MP[i] ? 1 << 21 : 0)
            o += (k == K1[ply] ? 1 << 20 : (k == K2[ply] ? 1 << 19 : 0))
            o += min(HIST[MF[i] * 32 + MT[i]], (1 << 19) - 1)
            MO[i] = o
        }
        let nd = depth <= 0 ? 0 : (n == 1 ? depth : depth - 1)
        var best = -INF
        var bk: Int32 = 0
        let a0 = alpha
        for j in 0..<n {
            var bi = base + j, bv = MO[bi]
            var q = base + j + 1
            while q < base + n { if MO[q] > bv { bv = MO[q]; bi = q }; q += 1 }
            if bi != base + j {
                let i = base + j
                MF.swapAt(i, bi); MT.swapAt(i, bi); MC.swapAt(i, bi); MP.swapAt(i, bi); MO.swapAt(i, bi)
            }
            let i = base + j
            make(i, ply)
            var s: Int
            if j == 0 { s = -negamax(-side, nd, -beta, -alpha, ply + 1) }
            else {
                let r = (nd >= 3 && j >= 3 && !cap && !MP[i]) ? (j >= 8 ? 2 : 1) : 0
                s = -negamax(-side, nd - r, -alpha - 1, -alpha, ply + 1)
                if !stop && s > alpha && (r > 0 || s < beta) { s = -negamax(-side, nd, -beta, -alpha, ply + 1) }
            }
            unmake(ply)
            if stop { return 0 }
            if s > best { best = s; bk = mkey(i) }
            if s > alpha {
                alpha = s
                if alpha >= beta {
                    if !cap {
                        if K1[ply] != bk { K2[ply] = K1[ply]; K1[ply] = bk }
                        HIST[MF[i] * 32 + MT[i]] += depth * depth
                    }
                    break
                }
            }
        }
        var ss = best
        if ss > MATE - 1000 { ss += ply } else if ss < -MATE + 1000 { ss -= ply }
        tk[ti] = H; tsc[ti] = Int32(clamping: ss); tdep[ti] = Int8(max(-1, min(100, depth))); tmv[ti] = bk
        tfl[ti] = best <= a0 ? 2 : (best >= beta ? 1 : 0)
        return best
    }

    private func findIndex(_ m: CheckersMove) -> Int {
        let n = gen(curSide, 0)
        for j in 0..<n where MF[j] == m.from && MT[j] == m.to && MC[j] == m.caps { return j }
        return -1
    }
    private var curSide = 1

    /// b64: 64 values (1 your man, 2 your king, -1 opp man, -2 opp king). You move up the board.
    func search(_ b64: [Int], side: Int = 1, maxMs: Int = 1000) -> CheckersResult {
        let t0 = now()
        var b32 = [Int](repeating: 0, count: 32)
        for s in 0..<32 { b32[s] = b64[S64[s]] }
        setFrom32(b32, side); curSide = side
        stop = false; nodes = 0
        for i in 0..<HIST.count { HIST[i] = 0 }
        for i in 0..<128 { K1[i] = 0; K2[i] = 0 }
        let n = gen(side, 0)
        var res = CheckersResult()
        if n == 0 { return res }
        var root: [(m: CheckersMove, score: Int)] = []
        for j in 0..<n { root.append((CheckersMove(from: MF[j], to: MT[j], caps: MC[j], promo: MP[j]), 0)) }
        if n == 1 { res.best = root[0].m; res.instant = "only"; return res }
        let MATE = CheckersEngine.MATE
        if !TB.isEmpty && kingRule == 0 && pieces() <= 4 {
            let tv = tbProbe(side)
            if tv >= 0 {
                var trapOf = [Int](repeating: 0, count: root.count), avgOf = [Int](repeating: 0, count: root.count)
                // our moves left under the count (fresh 8 when the counted ending starts now)
                let limit = countLeft < 0 ? 0 : (countSide() == side ? (countLeft > 0 ? countLeft : CheckersEngine.countMoves) : 0)
                for k in 0..<root.count {
                    let i = findIndex(root[k].m)
                    if i < 0 { continue }
                    make(i, 0)
                    let opp = side == 1 ? (P[2] | P[3]) : (P[0] | P[1])
                    var sc: Int
                    if opp == 0 { sc = MATE - 1 } else {
                        let v = tbProbe(-side)
                        sc = v < 0 ? 0 : (v == 0 ? 0 : (v < 128 ? -(MATE - 1 - v) : (MATE - 1 - (v - 128))))
                        // the count is running: a win that takes more of our moves than are left is a draw
                        if limit > 0 && v >= 128 && 1 + (v - 128) / 2 > limit { sc = 0 }
                        // Look at every reply. Won ending: our average remaining distance (a human rarely finds the
                        // longest defence, and WePlay ends the game as a draw after a few moves). Drawn ending: how
                        // many replies lose, so the AI keeps setting the trap that is easiest to fall into.
                        if sc >= 0 {
                            let n2 = gen(-side, 1)
                            var tot = 0, bad = 0
                            for j in 0..<n2 {
                                make(CheckersEngine.MAXM + j, 1)
                                let theirs = side == 1 ? (P[2] | P[3]) : (P[0] | P[1]), mine = side == 1 ? (P[0] | P[1]) : (P[2] | P[3])
                                if theirs == 0 { bad += 1 }
                                else if mine == 0 { tot += 200 }
                                else {
                                    let w = tbProbe(side)
                                    if w > 0 && w < 128 && (limit == 0 || (w + 1) / 2 <= limit - 1) { tot += w; bad += 1 } else { tot += 200 }
                                }
                                unmake(1)
                            }
                            if n2 > 0 { avgOf[k] = tot * 10 / n2; trapOf[k] = bad * 1000 / n2 + bad }
                        }
                    }
                    unmake(0)
                    root[k].score = sc
                }
                var bestK = 0
                for k in root.indices where root[k].score > root[bestK].score { bestK = k }
                let top = root[bestK].score
                if top > 0 && humanTieBreak {
                    // among wins at most 4 plies longer than the fastest, take the one that is fastest on average
                    func cost(_ k: Int) -> Int { avgOf[k] + (top - root[k].score) * 5 }
                    for k in root.indices where root[k].score > 0 && top - root[k].score <= 4 && cost(k) < cost(bestK) { bestK = k }
                } else if top == 0 {
                    for k in root.indices where root[k].score == 0 && trapOf[k] > trapOf[bestK] { bestK = k }
                    if trapOf[bestK] > 0 { res.trap = trapOf[bestK] % 1000 }
                }
                res.best = root[bestK].m; res.score = top; res.tb = top == 0 ? 0 : tv; res.depth = 99; res.instant = "tb"
                return res
            }
        }
        // original iterative deepening (measured: my "smarter" time rules lost ~50 Elo); when trap-picking
        // is on, the main search keeps 15% of the time back for it
        deadline = t0 + UInt64(Double(maxMs) * (trapMode ? 0.85 : 1.0)) * 1_000_000
        var list = root
        var stable = 0
        var prevBest = ""
        for d in 1...64 {
            var alpha = -INF
            var cur: [(m: CheckersMove, score: Int)] = []
            for j in 0..<list.count {
                let x = list[j]
                let i = findIndex(x.m)
                if i < 0 { continue }
                make(i, 0)
                var s: Int
                if j == 0 { s = -negamax(-side, d - 1, -INF, INF, 1) }
                else {
                    s = -negamax(-side, d - 1, -alpha - 1, -alpha, 1)
                    if !stop && s > alpha { s = -negamax(-side, d - 1, -INF, -alpha, 1) }
                }
                unmake(0)
                if stop { break }
                cur.append((x.m, s))
                if s > alpha { alpha = s }
            }
            if stop { break }
            cur.sort { $0.score > $1.score }
            list = cur
            res.best = list[0].m; res.score = list[0].score; res.depth = d
            let key = "\(list[0].m.from)-\(list[0].m.to)-\(list[0].m.caps)"
            stable = key == prevBest ? stable + 1 : 0
            prevBest = key
            let el = Double(now() - t0) / 1_000_000
            if abs(list[0].score) > MATE - 1000 { break }
            if d >= 6 {
                let second = list.count > 1 ? list[1].score : -INF
                let margin = list[0].score - second
                if stable >= 3 && margin >= 150 && el > Double(maxMs) * 0.12 { break }
                if stable >= 5 && el > Double(maxMs) * 0.3 { break }
            }
            if el > Double(maxMs) * 0.5 { break }
        }
        if res.best == nil { res.best = list[0].m }
        if trapMode && abs(res.score) < MATE - 1000 && list.count > 1 && res.depth >= 4 {
            deadline = t0 + UInt64(Double(maxMs) * 0.97) * 1_000_000
            stop = false
            if let t = pickTrap(list, side: side, depth: res.depth) { res.best = t.m; res.trap = t.traps }
        }
        return res
    }

    /// Plays like a strong human: among moves within a hair of the best, prefer the one that leaves the
    /// opponent the most replies that LOOK fine at a glance (2-ply) but actually lose material (deep).
    var trapMode = false   // (3.43: arena — trap picking cost ~30 Elo against the 23 Oct engine; off)
    /// Won table endings: prefer the win that is fastest on average over all replies (off = always the fastest
    /// against perfect defence).
    var humanTieBreak = false
    /// Legal moves (for tests).
    func moves(_ b64: [Int], side: Int) -> [CheckersMove] {
        var b32 = [Int](repeating: 0, count: 32)
        for s in 0..<32 { b32[s] = b64[S64[s]] }
        setFrom32(b32, side); curSide = side
        let n = gen(side, 0)
        return (0..<n).map { CheckersMove(from: MF[$0], to: MT[$0], caps: MC[$0], promo: MP[$0]) }
    }
    private func pickTrap(_ list: [(m: CheckersMove, score: Int)], side: Int, depth: Int) -> (m: CheckersMove, traps: Int)? {
        // Only the first move's score is exact (the others are bounds from a null-window search), so every
        // candidate is re-scored below at the same depth before it may be chosen.
        let cands = Array(list.prefix(4))
        if cands.count < 2 { return nil }
        let deep = max(3, min(depth - 2, 9))
        var counts: [(m: CheckersMove, traps: Int, value: Int)] = []
        for c in cands {
            let i = findIndex(c.m); if i < 0 { continue }
            make(i, 0)
            let n = gen(-side, 1), base = CheckersEngine.MAXM
            var replies: [(Int, UInt32, Int)] = []   // from, caps, to of each reply
            for j in 0..<n { replies.append((MF[base + j], MC[base + j], MT[base + j])) }
            var glance: [Int] = [], real: [Int] = []
            for (f, cp, t) in replies {
                var k = -1
                let n2 = gen(-side, 1)
                for j in 0..<n2 where MF[base + j] == f && MT[base + j] == t && MC[base + j] == cp { k = base + j; break }
                if k < 0 { continue }
                make(k, 1)
                let g = negamax(side, 1, -INF, INF, 2)        // what the opponent sees at a glance (their loss = my gain)
                let r = negamax(side, deep, -INF, INF, 2)     // what really happens
                unmake(1)
                if stop { unmake(0); return nil }
                glance.append(-g); real.append(-r)
            }
            unmake(0)
            guard let gBest = glance.max(), let rBest = real.max() else { continue }
            var traps = 0
            for q in 0..<glance.count where glance[q] >= gBest - 30 && real[q] <= rBest - 120 { traps += 1 }
            counts.append((c.m, traps, -rBest))   // my value = what's left after their best reply
        }
        guard let first = counts.first, first.m.from == list[0].m.from && first.m.to == list[0].m.to && first.m.caps == list[0].m.caps else { return nil }
        let top = counts.map { $0.value }.max()!
        // never give up value: candidates must be as good as the best at this depth (and as good as the main pick)
        let ok = counts.filter { $0.value >= top - 8 && $0.value >= first.value - 8 }
        guard let pick = ok.max(by: { $0.traps < $1.traps }), pick.traps > first.traps else { return nil }
        return (pick.m, pick.traps)
    }

    // MARK: full path of a move (for drawing), squares in 0..63
    func path(of m: CheckersMove, board b64: [Int], side: Int = 1) -> [Int] {
        var b = [Int](repeating: 0, count: 32)
        for s in 0..<32 { b[s] = b64[S64[s]] }
        let fw = side == 1 ? [0, 1] : [2, 3], pr = side == 1 ? 0 : 7
        let king = abs(b[m.from]) == 2
        var found: [Int]? = nil
        if m.caps == 0 { return [S64[m.from], S64[m.to]] }
        func rec(_ sq: Int, _ path: inout [Int], _ capt: UInt32, _ ld: Int) {
            if found != nil { return }
            var any = false
            for d in (king ? [0, 1, 2, 3] : fw) {
                if king && capt != 0 && kingRule == 1 && d == ld { continue }
                var ray: [Int] = []; var t = NB[d][sq]; while t >= 0 { ray.append(t); t = NB[d][t] }
                var k = 0
                if king && !(capt != 0 && kingRule == 0) { while k < ray.count && b[ray[k]] == 0 { k += 1 } }
                if k >= ray.count - 1 { continue }
                let v = b[ray[k]]
                if v == 0 || v == 9 || v * side > 0 { continue }
                let land = ray[k + 1]; if b[land] != 0 { continue }
                any = true
                b[ray[k]] = 9; path.append(land)
                let nc = capt | BIT[ray[k]]
                if !king && ROW[land] == pr { if land == m.to && nc == m.caps { found = path } }
                else { rec(land, &path, nc, d) }
                path.removeLast(); b[ray[k]] = v
                if found != nil { return }
            }
            if !any && capt != 0 && sq == m.to && capt == m.caps { found = path }
        }
        let p0 = b[m.from]; b[m.from] = 0
        var p = [m.from]
        rec(m.from, &p, 0, -1)
        b[m.from] = p0
        return (found ?? [m.from, m.to]).map { S64[$0] }
    }

    func capsSquares(_ m: CheckersMove) -> [Int] {
        var out: [Int] = []
        for s in 0..<32 where m.caps & BIT[s] != 0 { out.append(S64[s]) }
        return out
    }
}
