import Foundation

enum BoardReader {
    struct Sampler {
        let w: Int, h: Int
        let get: (Int, Int) -> (Double, Double, Double)
        func avg(_ cx: Double, _ cy: Double, _ rad: Double) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            let x0 = max(0, Int(cx - rad)), x1 = min(w - 1, Int(cx + rad)), y0 = max(0, Int(cy - rad)), y1 = min(h - 1, Int(cy + rad))
            let step = max(1, Int(rad / 4))
            var y = y0
            while y <= y1 { var x = x0; while x <= x1 { let p = get(x, y); r += p.0; g += p.1; b += p.2; n += 1; x += step }; y += step }
            return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
        }
    }
}
func out(_ s: String) { print(s); fflush(stdout) }

func fen(_ f: String) -> ([Int], Bool, Int, Int) {
    let parts = f.split(separator: " ").map(String.init)
    var cells: [Int] = []
    let map: [Character: Int] = ["P": 1, "N": 2, "B": 3, "R": 4, "Q": 5, "K": 6, "p": 7, "n": 8, "b": 9, "r": 10, "q": 11, "k": 12]
    for ch in parts[0] where ch != "/" { if let d = ch.wholeNumberValue { cells += [Int](repeating: 0, count: d) } else { cells.append(map[ch]!) } }
    var c = 0
    if parts.count > 2 { for ch in parts[2] { switch ch { case "K": c |= 1; case "Q": c |= 2; case "k": c |= 4; case "q": c |= 8; default: break } } }
    var ep = -1
    if parts.count > 3 && parts[3] != "-" { let a = Array(parts[3]); ep = (8 - Int(String(a[1]))!) * 8 + Int(a[0].asciiValue! - 97) }
    return (cells, parts[1] == "w", c, ep)
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
if mode == "hos" {
    let e = CheckersEngine()
    e.loadTB(FileManager.default.contents(atPath: "App/Resources/hos-tb.bin")!)
    var dark: [Int] = []; for i in 0..<64 where (i / 8 + i % 8) % 2 == 1 { dark.append(i) }
    var rng: UInt64 = 12345
    func r(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
    func apply(_ b: [Int], _ m: CheckersMove, _ side: Int) -> [Int] {
        var n = b
        let p = e.path(of: m, board: b, side: side)
        let f = p[0], t = p[p.count - 1]
        for c in e.capsSquares(m) { n[c] = 0 }
        var v = n[f]; n[f] = 0
        if v == 1 && t / 8 == 0 { v = 2 }; if v == -1 && t / 8 == 7 { v = -2 }
        n[t] = v
        return n
    }
    var starts: [[Int]] = []
    while starts.count < 150 {
        var b = [Int](repeating: 0, count: 64)
        var used = Set<Int>(); var ok = true
        for v in [2, 1, -2] {
            var sq = dark[r(32)]; var tries = 0
            while used.contains(sq) || (v == 1 && sq / 8 <= 1) { sq = dark[r(32)]; tries += 1; if tries > 50 { ok = false; break } }
            used.insert(sq); b[sq] = v
        }
        if !ok { continue }
        let res = e.search(b, side: 1, maxMs: 100)
        if res.instant == "tb" { starts.append(b) }
    }
    for random in [false, true] { for tie in [true] {
        e.humanTieBreak = tie
        var wins = 0, plies = 0
        var seed: UInt64 = 777
        for st in starts {
            var b = st, won = false
            for mv in 0..<8 {
                e.countLeft = 8 - mv
                guard let m = e.search(b, side: 1, maxMs: 100).best else { break }
                b = apply(b, m, 1)
                let ms = e.moves(b, side: -1)
                if !b.contains(where: { $0 < 0 }) || ms.isEmpty { won = true; plies += mv + 1; break }
                var om: CheckersMove
                if random { seed = seed &* 6364136223846793005 &+ 1442695040888963407; om = ms[Int((seed >> 33) % UInt64(ms.count))] }
                else { e.countLeft = 0; om = e.search(b, side: -1, maxMs: 100).best ?? ms[0] }
                b = apply(b, om, -1)
                if !b.contains(where: { $0 > 0 }) { break }
            }
            if won { wins += 1 }
        }
        out("K+man v K, opponent \(random ? "random" : "perfect"), average-tiebreak \(tie): won within 8 moves \(wins)/\(starts.count), avg moves \(wins > 0 ? Double(plies) / Double(wins) : 0)")
    } }
    exit(0)
}
if mode == "perft" || mode == "all" {
    let tests: [(String, Int, Int)] = [
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -", 4, 197281),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -", 5, 4865609),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 3, 97862),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 4, 4085603),
        ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -", 5, 674624),
        ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq -", 4, 422333),
        ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ -", 3, 62379),
    ]
    for (f, d, want) in tests {
        let e = ChessEngine(); let (c, w, cs, ep) = fen(f); e.setPosition(c, whiteToMove: w, castling: cs, epSquare: ep)
        let t0 = Date(); let n = e.perft(d)
        out("chess perft \(d) \(n == want ? "OK" : "WRONG \(n) want \(want)") \(String(format: "%.1fs", Date().timeIntervalSince(t0)))  \(f)")
    }
    var start = [Int](repeating: 0, count: 64)
    for i in 0..<64 where (i / 8 + i % 8) % 2 == 1 { if i / 8 <= 2 { start[i] = -1 } else if i / 8 >= 5 { start[i] = 1 } }
    let want = [7, 49, 302, 1469, 7361, 36768, 179740, 845931]
    var s = "checkers perft:"
    for d in 1...8 { let e = DraughtsEngine(); e.set(start); let n = e.perft(d); s += " \(d):\(n == want[d - 1] ? "OK" : "WRONG \(n)")" }
    out(s)
}
if mode == "search" || mode == "all" {
    let names = ["", "P", "N", "B", "R", "Q", "K"]
    for (label, f) in [("mate in 1 (Rd8#)", "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - -"), ("mate in 2", "r1bq2r1/b4pk1/p1pp1p2/1p2pP2/1P2P1PB/3P4/1PPQ2P1/R3K2R w - -"),
                       ("start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"), ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -"),
                       ("hanging queen (Nxd5? no: take the queen)", "rnb1kbnr/pppp1ppp/8/4p3/3q4/2N5/PPPPPPPP/R1BQKBNR w KQkq -")] {
        let e = ChessEngine(); let (c, w, cs, ep) = fen(f); e.setPosition(c, whiteToMove: w, castling: cs, epSquare: ep)
        let r = e.think(ms: 3000)
        if let m = r.best { out("chess \(label): \(names[c[m.from] > 6 ? c[m.from] - 6 : c[m.from]])\(GameModelSq(m.from))-\(GameModelSq(m.to)) score \(r.score) depth \(r.depth) mate \(r.mateIn.map(String.init) ?? "-")") }
    }
    var start = [Int](repeating: 0, count: 64)
    for i in 0..<64 where (i / 8 + i % 8) % 2 == 1 { if i / 8 <= 2 { start[i] = -1 } else if i / 8 >= 5 { start[i] = 1 } }
    let d = DraughtsEngine(); d.set(start); let r = d.think(ms: 2000)
    out("checkers start: \(r.best?.path ?? []) score \(r.score) depth \(r.depth)")
}
func GameModelSq(_ i: Int) -> String { "\(Array("abcdefgh")[i % 8])\(8 - i / 8)" }

func loadPPM(_ path: String) -> (Int, Int, [UInt8])? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    let bytes = [UInt8](d)
    var fields: [String] = [], i = 0, cur = ""
    while fields.count < 4 && i < bytes.count {
        let c = bytes[i]; i += 1
        if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { if !cur.isEmpty { fields.append(cur); cur = "" } } else { cur.append(Character(UnicodeScalar(c))) }
    }
    return (Int(fields[1])!, Int(fields[2])!, Array(bytes[i...]))
}
if mode == "read" || mode == "all" {
    let dir = "Tools/PlatoTest/frames"
    for f in (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted() ?? [] {
        guard let (w, h, px) = loadPPM(dir + "/" + f) else { continue }
        let s = BoardReader.Sampler(w: w, h: h) { x, y in let k = (y * w + x) * 3; return (Double(px[k]), Double(px[k + 1]), Double(px[k + 2])) }
        let t0 = Date()
        let ok = PlatoBoardReader.looksLikeBoard(s)
        let m = PlatoBoardReader.read(s)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        guard let m else { out("\(f) board=\(ok) → nil"); continue }
        let sym = m.game == .chess ? Array(".PNBRQKpnbrqk") : Array(".rwRW")
        let rows = (0..<8).map { r in String((0..<8).map { sym[m.cells[r * 8 + $0]] }) }.joined(separator: "/")
        out("\(f) board=\(ok) game=\(m.game) me=\(m.me) turn=\(m.myTurn) \(rows) \(ms)ms")
    }
}
