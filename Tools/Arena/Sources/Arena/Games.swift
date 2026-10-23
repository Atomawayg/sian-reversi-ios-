import Foundation

// MARK: connect-K
/// cells: row-major from the top, 1 = player to move, 2 = other. Returns a column.
typealias CnPlayer = (_ cells: [Int], _ cols: Int, _ rows: Int, _ K: Int) -> Int

func cnOldStyle(_ make: (Int, Int, Int) -> ConnectEngineLike, _ cells: [Int], _ cols: Int, _ rows: Int, _ K: Int, _ ms: Int) -> Int {
    let e = make(cols, rows, K)
    for c in 0..<cols {
        var r = rows - 1
        while r >= 0 { let v = cells[r * cols + c]; if v == 0 { break }; e.playMove(c, v == 1 ? 1 : -1); r -= 1 }
    }
    return e.bestMove(ms)
}

protocol ConnectEngineLike: AnyObject { func playMove(_ c: Int, _ p: Int); func bestMove(_ ms: Int) -> Int }
extension ConnectEngine: ConnectEngineLike {
    func playMove(_ c: Int, _ p: Int) { play(c, p) }
    func bestMove(_ ms: Int) -> Int { search(1, ms: ms).best }
}
extension ConnectEngineV0: ConnectEngineLike {
    func playMove(_ c: Int, _ p: Int) { play(c, p) }
    func bestMove(_ ms: Int) -> Int { search(1, ms: ms).best }
}

func makeCnA(_ ms: Int) -> CnPlayer {
    let solver = Connect4Solver()
    return { cells, cols, rows, K in
        if K == 4 && cols == 7 && rows == 6 && cells.filter({ $0 != 0 }).count >= 10, let a = solver.best(cells: cells, ms: ms * 6 / 10) { return a.col }
        return cnOldStyle({ ConnectEngine(W: $0, H: $1, K: $2) }, cells, cols, rows, K, K == 4 && cols == 7 ? ms * 4 / 10 : ms)
    }
}
func makeCnB(_ ms: Int) -> CnPlayer {
    return { cells, cols, rows, K in cnOldStyle({ ConnectEngineV0(W: $0, H: $1, K: $2) }, cells, cols, rows, K, ms) }
}

/// +1 first player wins, -1 second, 0 draw
func cnGame(_ first: CnPlayer, _ second: CnPlayer, cols: Int, rows: Int, K: Int, opening: [Int]) -> Int {
    var b = [Int](repeating: 0, count: cols * rows)   // absolute: 1 first, 2 second
    var ht = [Int](repeating: 0, count: cols)
    func drop(_ c: Int, _ p: Int) -> Bool {
        let r = rows - 1 - ht[c]; b[r * cols + c] = p; ht[c] += 1
        for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            var n = 1
            for s in [1, -1] {
                var cc = c + dc * s, rr = r + dr * s
                while cc >= 0 && cc < cols && rr >= 0 && rr < rows && b[rr * cols + cc] == p { n += 1; cc += dc * s; rr += dr * s }
            }
            if n >= K { return true }
        }
        return false
    }
    var turn = 1
    for c in opening { if drop(c, turn) { return turn == 1 ? 1 : -1 }; turn = 3 - turn }
    while ht.contains(where: { $0 < rows }) {
        let rel = b.map { $0 == 0 ? 0 : ($0 == turn ? 1 : 2) }
        var c = (turn == 1 ? first : second)(rel, cols, rows, K)
        if c < 0 || c >= cols || ht[c] >= rows { c = ht.firstIndex { $0 < rows }! }   // illegal → first legal
        if drop(c, turn) { return turn == 1 ? 1 : -1 }
        turn = 3 - turn
    }
    return 0
}

// MARK: reversi
protocol ReversiLike: AnyObject { func bestSquare(_ cells: [Int], me: Int, ms: Int) -> Int }   // -1 = pass
private func padded(_ cells: [Int]) -> [Int8] {
    var b = [Int8](repeating: 3, count: 100)
    for r in 0..<8 { for c in 0..<8 { b[(r + 1) * 10 + c + 1] = Int8(cells[r * 8 + c]) } }
    return b
}
private func unpad(_ i: Int) -> Int { i > 0 ? (i / 10 - 1) * 8 + (i % 10 - 1) : -1 }
extension Engine: ReversiLike {
    func bestSquare(_ cells: [Int], me: Int, ms: Int) -> Int { unpad(think(padded(cells), me: Int8(me), timeMs: ms, exactMs: ms * 2).best) }
}
extension EngineV0: ReversiLike {
    func bestSquare(_ cells: [Int], me: Int, ms: Int) -> Int { unpad(think(padded(cells), me: Int8(me), timeMs: ms, exactMs: ms * 2).best) }
}

/// +1 black(first) wins, -1 white, 0 draw
func rvGame(_ black: ReversiLike, _ white: ReversiLike, opening: [Int], ms: Int) -> Int {
    var b = opening, turn = 1, passes = 0
    while passes < 2 {
        let succ = ReversiRules.successors(b, colour: turn)
        if succ.isEmpty { passes += 1; turn = 3 - turn; continue }
        passes = 0
        let sq = (turn == 1 ? black : white).bestSquare(b, me: turn, ms: ms)
        var next = succ[0]
        if sq >= 0 { if let n = succ.first(where: { $0[sq] == turn && b[sq] == 0 }) { next = n } }
        b = next; turn = 3 - turn
    }
    let d = b.filter { $0 == 1 }.count - b.filter { $0 == 2 }.count
    return d > 0 ? 1 : (d < 0 ? -1 : 0)
}

func extraGames(_ game: String, pairs: Int, ms: Int, result: inout (a: Int, b: Int, d: Int)) {
    switch game {
    case "connect4", "connect5":
        let (cols, rows, K) = game == "connect4" ? (7, 6, 4) : (9, 7, 5)
        result = runPairs(pairs) { i in
            var rng = Rng(s: 0xD1B54A32D192ED03 &+ UInt64(i) &* 0x9E3779B97F4A7C15)
            let open = (0..<(1 + rng.int(3))).map { _ in rng.int(cols) }
            let a = makeCnA(ms), b = makeCnB(ms)
            let g1 = cnGame(a, b, cols: cols, rows: rows, K: K, opening: open)
            let g2 = cnGame(b, a, cols: cols, rows: rows, K: K, opening: open)
            return (g1 == 1 ? .a : (g1 == -1 ? .b : .draw), g2 == -1 ? .a : (g2 == 1 ? .b : .draw))
        }
    case "reversi":
        result = runPairs(pairs) { i in
            var rng = Rng(s: 0xA0761D6478BD642F &+ UInt64(i) &* 0xE7037ED1A0B428DB)
            var b = [Int](repeating: 0, count: 64)
            b[27] = 2; b[36] = 2; b[28] = 1; b[35] = 1
            var turn = 1
            for _ in 0..<(4 + 2 * rng.int(3)) {
                let s = ReversiRules.successors(b, colour: turn); if s.isEmpty { break }
                b = s[rng.int(s.count)]; turn = 3 - turn
            }
            if turn != 1 { let s = ReversiRules.successors(b, colour: 2); if !s.isEmpty { b = s[rng.int(s.count)] } }
            let a = Engine(), o = EngineV0()
            let g1 = rvGame(a, o, opening: b, ms: ms), g2 = rvGame(o, a, opening: b, ms: ms)
            return (g1 == 1 ? .a : (g1 == -1 ? .b : .draw), g2 == -1 ? .a : (g2 == 1 ? .b : .draw))
        }
    default:
        print("unknown game \(game)")
    }
}
