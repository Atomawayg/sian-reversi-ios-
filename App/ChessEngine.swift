import Foundation

/// Chess engine for Plato chess (standard rules).
/// 10×12 mailbox board; pieces: 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king; positive = white, negative = black.
/// Search: iterative deepening PVS with a transposition table, quiescence (captures), null move,
/// late-move reductions, killer/history ordering, check extension. Evaluation: tapered piece-square tables.
struct ChessMove: Equatable {
    var from: Int       // 0…63, a8 = 0, h1 = 63
    var to: Int
    var promo: Int = 0  // 2…5 when a pawn promotes
}

final class ChessEngine {
    // MARK: board representation
    private var b = [Int8](repeating: 7, count: 120)   // 7 = off board
    private var side: Int8 = 1                          // 1 white, -1 black
    private var castle = 0                              // 1 K, 2 Q, 4 k, 8 q
    private var ep = 0                                  // mailbox square that can be taken en passant, 0 = none
    private var kingSq = [0, 0]                         // [white, black]
    private var hash: UInt64 = 0
    private var ply = 0

    private static func mb(_ i: Int) -> Int { 21 + (i / 8) * 10 + i % 8 }        // 0…63 → mailbox
    private static func sq64(_ m: Int) -> Int { (m / 10 - 2) * 8 + m % 10 - 1 }
    private static let N = -10, S = 10, E = 1, W = -1
    private static let knightD = [-21, -19, -12, -8, 8, 12, 19, 21]
    private static let bishopD = [-11, -9, 9, 11]
    private static let rookD = [-10, -1, 1, 10]
    private static let kingD = [-11, -10, -9, -1, 1, 9, 10, 11]

    // Zobrist
    private var zp = [UInt64](repeating: 0, count: 13 * 120)
    private var zSide: UInt64 = 0
    private var zCastle = [UInt64](repeating: 0, count: 16)
    private var zEp = [UInt64](repeating: 0, count: 120)

    init() {
        var s: UInt64 = 0x9E3779B97F4A7C15
        func r() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
        for i in 0..<zp.count { zp[i] = r() }
        zSide = r()
        for i in 0..<16 { zCastle[i] = r() }
        for i in 0..<120 { zEp[i] = r() }
    }
    @inline(__always) private func zIdx(_ p: Int8, _ m: Int) -> Int { (Int(p) + 6) * 120 + m }

    /// cells: 64 values a8…h1 (0 empty, 1…6 white P N B R Q K, 7…12 black); whiteToMove; castling "KQkq" bits; epSquare 0…63 or -1
    func setPosition(_ cells: [Int], whiteToMove: Bool, castling: Int, epSquare: Int) {
        b = [Int8](repeating: 7, count: 120)
        for i in 0..<64 {
            let v = cells[i]
            let m = ChessEngine.mb(i)
            b[m] = v == 0 ? 0 : (v <= 6 ? Int8(v) : -Int8(v - 6))
            if b[m] == 6 { kingSq[0] = m } else if b[m] == -6 { kingSq[1] = m }
        }
        side = whiteToMove ? 1 : -1
        castle = castling
        ep = epSquare >= 0 ? ChessEngine.mb(epSquare) : 0
        rehash()
    }

    private func rehash() {
        hash = 0
        for m in 21..<99 where b[m] != 0 && b[m] != 7 { hash ^= zp[zIdx(b[m], m)] }
        if side == -1 { hash ^= zSide }
        hash ^= zCastle[castle]
        if ep != 0 { hash ^= zEp[ep] }
    }

    // MARK: attacks
    func attacked(_ m: Int, by s: Int8) -> Bool {
        // pawns
        if s == 1 { if b[m + 9] == 1 || b[m + 11] == 1 { return true } }
        else { if b[m - 9] == -1 || b[m - 11] == -1 { return true } }
        for d in ChessEngine.knightD where b[m + d] == 2 * s { return true }
        for d in ChessEngine.kingD where b[m + d] == 6 * s { return true }
        for d in ChessEngine.bishopD {
            var t = m + d
            while b[t] == 0 { t += d }
            if b[t] == 3 * s || b[t] == 5 * s { return true }
        }
        for d in ChessEngine.rookD {
            var t = m + d
            while b[t] == 0 { t += d }
            if b[t] == 4 * s || b[t] == 5 * s { return true }
        }
        return false
    }
    @inline(__always) private func inCheck(_ s: Int8) -> Bool { attacked(kingSq[s == 1 ? 0 : 1], by: -s) }

    // MARK: moves
    struct M { var from: Int; var to: Int; var promo: Int8; var cap: Int8; var flag: UInt8; var score: Int32 }   // flag 1 ep, 2 castle, 3 double push
    private func gen(_ out: inout [M], capturesOnly: Bool) {
        out.removeAll(keepingCapacity: true)
        let s = side
        for m in 21..<99 {
            let p = b[m]
            if p == 0 || p == 7 || (p > 0) != (s > 0) { continue }
            let a = abs(Int(p))
            switch a {
            case 1:
                let fwd = s == 1 ? -10 : 10
                let startRow = s == 1 ? 8 : 3, promoRow = s == 1 ? 2 : 9
                let t = m + fwd
                if b[t] == 0 {
                    if t / 10 == promoRow { for pr in [5, 4, 3, 2] { out.append(M(from: m, to: t, promo: Int8(pr) * s, cap: 0, flag: 0, score: 0)) } }
                    else if !capturesOnly {
                        out.append(M(from: m, to: t, promo: 0, cap: 0, flag: 0, score: 0))
                        if m / 10 == startRow && b[t + fwd] == 0 { out.append(M(from: m, to: t + fwd, promo: 0, cap: 0, flag: 3, score: 0)) }
                    }
                }
                for d in [fwd - 1, fwd + 1] {
                    let t = m + d, q = b[t]
                    if q != 0 && q != 7 && (q > 0) != (s > 0) {
                        if t / 10 == promoRow { for pr in [5, 4, 3, 2] { out.append(M(from: m, to: t, promo: Int8(pr) * s, cap: q, flag: 0, score: 0)) } }
                        else { out.append(M(from: m, to: t, promo: 0, cap: q, flag: 0, score: 0)) }
                    } else if t == ep && ep != 0 {
                        out.append(M(from: m, to: t, promo: 0, cap: -s, flag: 1, score: 0))
                    }
                }
            case 2, 6:
                for d in (a == 2 ? ChessEngine.knightD : ChessEngine.kingD) {
                    let t = m + d, q = b[t]
                    if q == 7 { continue }
                    if q == 0 { if !capturesOnly { out.append(M(from: m, to: t, promo: 0, cap: 0, flag: 0, score: 0)) } }
                    else if (q > 0) != (s > 0) { out.append(M(from: m, to: t, promo: 0, cap: q, flag: 0, score: 0)) }
                }
                if a == 6 && !capturesOnly { genCastles(&out, m) }
            default:
                let dirs = a == 3 ? ChessEngine.bishopD : (a == 4 ? ChessEngine.rookD : ChessEngine.kingD)
                for d in dirs {
                    var t = m + d
                    while b[t] == 0 { if !capturesOnly { out.append(M(from: m, to: t, promo: 0, cap: 0, flag: 0, score: 0)) }; t += d }
                    let q = b[t]
                    if q != 7 && (q > 0) != (s > 0) { out.append(M(from: m, to: t, promo: 0, cap: q, flag: 0, score: 0)) }
                }
            }
        }
    }
    private func genCastles(_ out: inout [M], _ m: Int) {
        if side == 1 && m == 95 {
            if castle & 1 != 0 && b[96] == 0 && b[97] == 0 && b[98] == 4 && !attacked(95, by: -1) && !attacked(96, by: -1) && !attacked(97, by: -1) {
                out.append(M(from: 95, to: 97, promo: 0, cap: 0, flag: 2, score: 0)) }
            if castle & 2 != 0 && b[94] == 0 && b[93] == 0 && b[92] == 0 && b[91] == 4 && !attacked(95, by: -1) && !attacked(94, by: -1) && !attacked(93, by: -1) {
                out.append(M(from: 95, to: 93, promo: 0, cap: 0, flag: 2, score: 0)) }
        } else if side == -1 && m == 25 {
            if castle & 4 != 0 && b[26] == 0 && b[27] == 0 && b[28] == -4 && !attacked(25, by: 1) && !attacked(26, by: 1) && !attacked(27, by: 1) {
                out.append(M(from: 25, to: 27, promo: 0, cap: 0, flag: 2, score: 0)) }
            if castle & 8 != 0 && b[24] == 0 && b[23] == 0 && b[22] == 0 && b[21] == -4 && !attacked(25, by: 1) && !attacked(24, by: 1) && !attacked(23, by: 1) {
                out.append(M(from: 25, to: 23, promo: 0, cap: 0, flag: 2, score: 0)) }
        }
    }

    private struct Undo { var castle: Int; var ep: Int; var hash: UInt64; var cap: Int8 }
    private static let castleMask: [Int] = {
        var m = [Int](repeating: 15, count: 120)
        m[95] = 15 & ~3; m[98] = 15 & ~1; m[91] = 15 & ~2
        m[25] = 15 & ~12; m[28] = 15 & ~4; m[21] = 15 & ~8
        return m
    }()

    /// returns false (and undoes) when the move leaves the own king in check
    @discardableResult
    private func make(_ mv: M, _ u: inout Undo) -> Bool {
        u = Undo(castle: castle, ep: ep, hash: hash, cap: mv.cap)
        let p = b[mv.from]
        hash ^= zCastle[castle]
        if ep != 0 { hash ^= zEp[ep] }
        hash ^= zp[zIdx(p, mv.from)]
        if mv.flag == 1 {
            let cs = mv.to + (side == 1 ? 10 : -10)
            hash ^= zp[zIdx(b[cs], cs)]; b[cs] = 0
        } else if mv.cap != 0 { hash ^= zp[zIdx(mv.cap, mv.to)] }
        b[mv.from] = 0
        let np = mv.promo != 0 ? mv.promo : p
        b[mv.to] = np
        hash ^= zp[zIdx(np, mv.to)]
        if abs(Int(p)) == 6 { kingSq[side == 1 ? 0 : 1] = mv.to }
        if mv.flag == 2 {
            let (rf, rt) = mv.to > mv.from ? (mv.from + 3, mv.from + 1) : (mv.from - 4, mv.from - 1)
            let r = b[rf]; b[rf] = 0; b[rt] = r
            hash ^= zp[zIdx(r, rf)] ^ zp[zIdx(r, rt)]
        }
        castle &= ChessEngine.castleMask[mv.from] & ChessEngine.castleMask[mv.to]
        ep = mv.flag == 3 ? (mv.from + mv.to) / 2 : 0
        hash ^= zCastle[castle]
        if ep != 0 { hash ^= zEp[ep] }
        let mover = side
        side = -side; hash ^= zSide
        ply += 1
        if attacked(kingSq[mover == 1 ? 0 : 1], by: side) { unmake(mv, u); return false }
        return true
    }
    private func unmake(_ mv: M, _ u: Undo) {
        side = -side; ply -= 1
        let np = b[mv.to]
        let p: Int8 = mv.promo != 0 ? side : np
        b[mv.from] = p
        b[mv.to] = mv.flag == 1 ? 0 : u.cap
        if mv.flag == 1 { b[mv.to + (side == 1 ? 10 : -10)] = -side }
        if abs(Int(p)) == 6 { kingSq[side == 1 ? 0 : 1] = mv.from }
        if mv.flag == 2 {
            let (rf, rt) = mv.to > mv.from ? (mv.from + 3, mv.from + 1) : (mv.from - 4, mv.from - 1)
            b[rf] = b[rt]; b[rt] = 0
        }
        castle = u.castle; ep = u.ep; hash = u.hash
    }
    private func makeNull(_ u: inout Undo) {
        u = Undo(castle: castle, ep: ep, hash: hash, cap: 0)
        if ep != 0 { hash ^= zEp[ep] }
        ep = 0; side = -side; hash ^= zSide; ply += 1
    }
    private func unmakeNull(_ u: Undo) { side = -side; ply -= 1; ep = u.ep; hash = u.hash }

    // MARK: perft (testing)
    func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var moves: [M] = []; gen(&moves, capturesOnly: false)
        var n = 0, u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
        for mv in moves { if make(mv, &u) { n += perft(depth - 1); unmake(mv, u) } }
        return n
    }

    // MARK: evaluation (tapered piece-square tables, white's view; a8 = 0)
    private static let value = [0, 100, 320, 330, 500, 900, 0]
    private static let phaseW = [0, 0, 1, 1, 2, 4, 0]
    private static let pstPawn = [0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, 0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0]
    private static let pstPawnEg = [0, 0, 0, 0, 0, 0, 0, 0, 80, 80, 80, 80, 80, 80, 80, 80, 50, 50, 50, 50, 50, 50, 50, 50, 30, 30, 30, 30, 30, 30, 30, 30, 15, 15, 15, 15, 15, 15, 15, 15, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    private static let pstKnight = [-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50]
    private static let pstBishop = [-20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20]
    private static let pstRook = [0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0]
    private static let pstQueen = [-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5, 0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20]
    private static let pstKingMg = [-30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20]
    private static let pstKingEg = [-50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50]

    private func evaluate() -> Int {
        var mg = 0, eg = 0, phase = 0
        var bishops = [0, 0]
        var pawnFiles = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2)
        for m in 21..<99 {
            let p = b[m]
            if p == 0 || p == 7 { continue }
            let a = abs(Int(p)), white = p > 0
            let i = ChessEngine.sq64(m)
            let k = white ? i : (7 - i / 8) * 8 + i % 8      // mirror for black
            let sgn = white ? 1 : -1
            phase += ChessEngine.phaseW[a]
            var pm = ChessEngine.value[a], pe = ChessEngine.value[a]
            switch a {
            case 1: pm += ChessEngine.pstPawn[k]; pe += ChessEngine.pstPawnEg[k]; pawnFiles[white ? 0 : 1][i % 8] += 1
            case 2: pm += ChessEngine.pstKnight[k]; pe += ChessEngine.pstKnight[k]
            case 3: pm += ChessEngine.pstBishop[k]; pe += ChessEngine.pstBishop[k]; bishops[white ? 0 : 1] += 1
            case 4: pm += ChessEngine.pstRook[k]; pe += ChessEngine.pstRook[k]
            case 5: pm += ChessEngine.pstQueen[k]; pe += ChessEngine.pstQueen[k]
            default: pm += ChessEngine.pstKingMg[k]; pe += ChessEngine.pstKingEg[k]
            }
            mg += sgn * pm; eg += sgn * pe
        }
        // bishop pair, doubled / isolated pawns
        for s in 0..<2 {
            let sgn = s == 0 ? 1 : -1
            if bishops[s] >= 2 { mg += sgn * 30; eg += sgn * 50 }
            for f in 0..<8 where pawnFiles[s][f] > 0 {
                if pawnFiles[s][f] > 1 { mg -= sgn * 12 * (pawnFiles[s][f] - 1); eg -= sgn * 20 * (pawnFiles[s][f] - 1) }
                let iso = (f == 0 || pawnFiles[s][f - 1] == 0) && (f == 7 || pawnFiles[s][f + 1] == 0)
                if iso { mg -= sgn * 10; eg -= sgn * 15 }
            }
        }
        let ph = min(24, phase)
        let score = (mg * ph + eg * (24 - ph)) / 24
        return (side == 1 ? score : -score) + 10      // small tempo bonus
    }

    // MARK: search
    static let MATE = 30000
    private static let TTS = 1 << 20
    private var ttKey = [UInt64](repeating: 0, count: ChessEngine.TTS)
    private var ttVal = [Int32](repeating: 0, count: ChessEngine.TTS)
    private var ttDepth = [Int8](repeating: -1, count: ChessEngine.TTS)
    private var ttFlag = [UInt8](repeating: 0, count: ChessEngine.TTS)
    private var ttMove = [Int32](repeating: 0, count: ChessEngine.TTS)
    private var killers = [[Int32]](repeating: [0, 0], count: 128)
    private var history = [Int32](repeating: 0, count: 120 * 120)
    private var nodes = 0, deadline: UInt64 = 0, stopped = false
    private var moveBuf = [[M]](repeating: [], count: 130)
    private var repStack: [UInt64] = []

    @inline(__always) private func key(_ m: M) -> Int32 { Int32(m.from | m.to << 7 | Int(abs(Int(m.promo))) << 14) }

    private func score(_ ms: inout [M], tt: Int32) {
        for i in ms.indices {
            let k = key(ms[i])
            if k == tt { ms[i].score = 1 << 30; continue }
            if ms[i].cap != 0 || ms[i].promo != 0 {
                ms[i].score = (1 << 24) + Int32(ChessEngine.value[abs(Int(ms[i].cap))] * 16 - ChessEngine.value[abs(Int(b[ms[i].from]))] / 10) + Int32(abs(Int(ms[i].promo)) * 1000)
            } else if k == killers[ply][0] { ms[i].score = 1 << 22 }
            else if k == killers[ply][1] { ms[i].score = (1 << 22) - 1 }
            else { ms[i].score = min(history[ms[i].from * 120 + ms[i].to], (1 << 21)) }
        }
    }
    @inline(__always) private func pick(_ ms: inout [M], _ start: Int) {
        var bi = start
        for j in (start + 1)..<ms.count where ms[j].score > ms[bi].score { bi = j }
        if bi != start { ms.swapAt(start, bi) }
    }

    private func quiesce(_ alphaIn: Int, _ beta: Int) -> Int {
        nodes += 1
        if nodes & 4095 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { stopped = true }
        if stopped { return 0 }
        let stand = evaluate()
        if stand >= beta { return stand }
        var alpha = max(alphaIn, stand)
        if ply >= 120 { return stand }
        var ms = moveBuf[ply]; gen(&ms, capturesOnly: true); score(&ms, tt: 0)
        var u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
        for i in ms.indices {
            pick(&ms, i)
            let mv = ms[i]
            if stand + ChessEngine.value[abs(Int(mv.cap))] + 200 < alpha && mv.promo == 0 { continue }   // delta pruning
            if !make(mv, &u) { continue }
            let v = -quiesce(-beta, -alpha)
            unmake(mv, u)
            if stopped { return 0 }
            if v >= beta { moveBuf[ply] = ms; return v }
            if v > alpha { alpha = v }
        }
        moveBuf[ply] = ms
        return alpha
    }

    private func nonPawnMaterial(_ s: Int8) -> Bool {
        for m in 21..<99 { let p = b[m]; if p != 7 && p != 0 && (p > 0) == (s > 0) && abs(Int(p)) >= 2 && abs(Int(p)) <= 5 { return true } }
        return false
    }

    private func search(_ depthIn: Int, _ alphaIn: Int, _ betaIn: Int, pv: Bool, nullOK: Bool) -> Int {
        if stopped { return 0 }
        var alpha = alphaIn, beta = betaIn
        let check = inCheck(side)
        let depth = check ? depthIn + 1 : depthIn
        if depth <= 0 { return quiesce(alpha, beta) }
        nodes += 1
        if nodes & 4095 == 0 && DispatchTime.now().uptimeNanoseconds > deadline { stopped = true; return 0 }
        if ply > 0 {
            // repetition: treat as a draw
            var i = repStack.count - 3          // the last entry is this position; same side to move every 2 plies
            while i >= 0 { if repStack[i] == hash { return 0 }; i -= 2 }
            alpha = max(alpha, -ChessEngine.MATE + ply); beta = min(beta, ChessEngine.MATE - ply - 1)
            if alpha >= beta { return alpha }
        }
        if ply >= 120 { return evaluate() }
        let ti = Int(hash & UInt64(ChessEngine.TTS - 1))
        var ttm: Int32 = 0
        if ttKey[ti] == hash {
            ttm = ttMove[ti]
            if !pv && Int(ttDepth[ti]) >= depth {
                var v = Int(ttVal[ti])
                if v > ChessEngine.MATE - 200 { v -= ply } else if v < -ChessEngine.MATE + 200 { v += ply }
                let f = ttFlag[ti]
                if f == 0 || (f == 1 && v >= beta) || (f == 2 && v <= alpha) { return v }
            }
        }
        // null move
        if nullOK && !pv && !check && depth >= 3 && nonPawnMaterial(side) && evaluate() >= beta {
            var u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
            makeNull(&u); repStack.append(hash)
            let r = depth >= 7 ? 3 : 2
            let v = -search(depth - 1 - r, -beta, -beta + 1, pv: false, nullOK: false)
            repStack.removeLast(); unmakeNull(u)
            if stopped { return 0 }
            if v >= beta { return v >= ChessEngine.MATE - 200 ? beta : v }
        }
        var ms = moveBuf[ply]; gen(&ms, capturesOnly: false); score(&ms, tt: ttm)
        var best = -ChessEngine.MATE - 1, bestKey: Int32 = 0, legal = 0
        let a0 = alpha
        var u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
        for i in ms.indices {
            pick(&ms, i)
            let mv = ms[i]
            if !make(mv, &u) { continue }
            legal += 1
            repStack.append(hash)
            let quiet = mv.cap == 0 && mv.promo == 0
            var v: Int
            if legal == 1 {
                v = -search(depth - 1, -beta, -alpha, pv: pv, nullOK: true)
            } else {
                var r = 0
                if depth >= 3 && legal > 3 && quiet && !check && !inCheck(side) {
                    r = 1 + (legal > 8 ? 1 : 0) + (depth > 6 ? 1 : 0)
                    if pv { r -= 1 }
                }
                v = -search(depth - 1 - r, -alpha - 1, -alpha, pv: false, nullOK: true)
                if !stopped && v > alpha && r > 0 { v = -search(depth - 1, -alpha - 1, -alpha, pv: false, nullOK: true) }
                if !stopped && v > alpha && v < beta { v = -search(depth - 1, -beta, -alpha, pv: true, nullOK: true) }
            }
            repStack.removeLast()
            unmake(mv, u)
            if stopped { moveBuf[ply] = ms; return 0 }
            if v > best { best = v; bestKey = key(mv) }
            if v > alpha {
                alpha = v
                if v >= beta {
                    if quiet {
                        if killers[ply][0] != key(mv) { killers[ply][1] = killers[ply][0]; killers[ply][0] = key(mv) }
                        history[mv.from * 120 + mv.to] += Int32(depth * depth)
                    }
                    break
                }
            }
        }
        moveBuf[ply] = ms
        if legal == 0 { return check ? -ChessEngine.MATE + ply : 0 }
        var sv = best
        if sv > ChessEngine.MATE - 200 { sv += ply } else if sv < -ChessEngine.MATE + 200 { sv -= ply }
        ttKey[ti] = hash; ttVal[ti] = Int32(sv); ttDepth[ti] = Int8(min(100, depth)); ttMove[ti] = bestKey
        ttFlag[ti] = best <= a0 ? 2 : (best >= beta ? 1 : 0)
        return best
    }

    struct Result { var best: ChessMove?; var score = 0; var depth = 0; var mateIn: Int? = nil }

    /// Best move for the side to move, thinking up to `ms` milliseconds.
    func think(ms: Int) -> Result {
        let t0 = DispatchTime.now().uptimeNanoseconds
        deadline = t0 + UInt64(ms) * 1_000_000
        stopped = false; nodes = 0; ply = 0
        for i in 0..<history.count { history[i] /= 8 }
        for i in 0..<killers.count { killers[i] = [0, 0] }
        repStack = [hash]
        var root: [M] = []; gen(&root, capturesOnly: false)
        var legalRoot: [M] = []
        var u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
        for mv in root { if make(mv, &u) { unmake(mv, u); legalRoot.append(mv) } }
        var res = Result()
        guard !legalRoot.isEmpty else { return res }
        func toMove(_ m: M) -> ChessMove { ChessMove(from: ChessEngine.sq64(m.from), to: ChessEngine.sq64(m.to), promo: abs(Int(m.promo))) }
        res.best = toMove(legalRoot[0])
        if legalRoot.count == 1 { return res }
        var order = legalRoot
        var prevScore = 0
        for d in 1...64 {
            var alpha = -ChessEngine.MATE - 1, beta = ChessEngine.MATE + 1
            if d >= 5 { alpha = prevScore - 40; beta = prevScore + 40 }
            var bestHere: M? = nil, bestV = -ChessEngine.MATE - 1
            while true {
                bestHere = nil; bestV = -ChessEngine.MATE - 1
                var a = alpha
                var scored: [(M, Int)] = []
                for (i, mv) in order.enumerated() {
                    if !make(mv, &u) { continue }
                    repStack.append(hash)
                    var v: Int
                    if i == 0 { v = -search(d - 1, -beta, -a, pv: true, nullOK: true) }
                    else {
                        v = -search(d - 1, -a - 1, -a, pv: false, nullOK: true)
                        if !stopped && v > a && v < beta { v = -search(d - 1, -beta, -a, pv: true, nullOK: true) }
                    }
                    repStack.removeLast(); unmake(mv, u)
                    if stopped { break }
                    scored.append((mv, v))
                    if v > bestV { bestV = v; bestHere = mv }
                    if v > a { a = v }
                    if v >= beta { break }
                }
                if stopped { break }
                if bestV <= alpha && alpha > -ChessEngine.MATE - 1 { alpha = -ChessEngine.MATE - 1; continue }   // fail low: widen
                if bestV >= beta && beta < ChessEngine.MATE + 1 { beta = ChessEngine.MATE + 1; continue }        // fail high: widen
                // reorder: best first, then by score
                let rest = order.filter { m in !scored.contains { $0.0.from == m.from && $0.0.to == m.to && $0.0.promo == m.promo } }
                order = scored.sorted { $0.1 > $1.1 }.map { $0.0 } + rest
                break
            }
            if stopped {
                if let bh = bestHere, bestV > prevScore - 30 { res.best = toMove(bh) }   // a move that already beat the old choice
                break
            }
            if let bh = bestHere { res.best = toMove(bh); res.score = bestV; res.depth = d; prevScore = bestV }
            if abs(bestV) > ChessEngine.MATE - 200 {
                res.mateIn = bestV > 0 ? (ChessEngine.MATE - bestV + 1) / 2 : -(ChessEngine.MATE + bestV) / 2
                break
            }
            let el = DispatchTime.now().uptimeNanoseconds - t0
            if Double(el) > Double(ms) * 1_000_000 * 0.45 { break }   // the next depth would not finish
        }
        return res
    }

    /// Is the side to move in check / checkmated / stalemated?
    func status() -> (check: Bool, legalMoves: Int) {
        var root: [M] = []; gen(&root, capturesOnly: false)
        var n = 0, u = Undo(castle: 0, ep: 0, hash: 0, cap: 0)
        for mv in root { if make(mv, &u) { unmake(mv, u); n += 1 } }
        return (inCheck(side), n)
    }
}
