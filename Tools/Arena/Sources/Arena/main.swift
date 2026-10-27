import Foundation

// Usage: Arena <game> <games> <ms per move>
//   game: checkers | reversi | connect4 | connect5
// Plays the current engine (A) against the baseline (B, the *V0 copies), pairs of games from the
// same random opening with colours swapped, and prints one summary line.

let args = CommandLine.arguments
let game = args.count > 1 ? args[1] : "checkers"
let games = args.count > 2 ? Int(args[2]) ?? 100 : 100
let ms = args.count > 3 ? Int(args[3]) ?? 100 : 100

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

enum Outcome { case a, b, draw }

// MARK: checkers
/// One move: returns the new board, or nil when the side to move has no move (loses).
typealias CkPlayer = (_ board: [Int], _ side: Int) -> [Int]?

func ckApply(_ b: [Int], side: Int, path: [Int], caps: [Int]) -> [Int] {
    var n = b
    let piece = n[path[0]]
    n[path[0]] = 0
    for s in caps { n[s] = 0 }
    let to = path[path.count - 1]
    var p = piece
    if abs(p) == 1 && to / 8 == (side == 1 ? 0 : 7) { p = 2 * side }
    n[to] = p
    return n
}

func ckStart() -> [Int] {
    var b = [Int](repeating: 0, count: 64)
    for r in 0..<8 { for c in 0..<8 where (r + c) & 1 == 1 {
        if r <= 1 { b[r * 8 + c] = -1 } else if r >= 6 { b[r * 8 + c] = 1 }
    } }
    return b
}

var strict = false
func ckGame(_ white: CkPlayer, _ black: CkPlayer, opening: [Int]) -> Int {   // +1 white(bottom) wins, -1 black, 0 draw
    var b = opening, side = 1, plies = 0, quiet = 0
    while plies < 200 {
        let p = side == 1 ? white : black
        guard let nb = p(b, side) else { return -side }
        let before = b.filter { $0 != 0 }.count, after = nb.filter { $0 != 0 }.count
        quiet = after < before ? 0 : quiet + 1
        b = nb; side = -side; plies += 1
        let mine = b.filter { $0 > 0 }.count, theirs = b.filter { $0 < 0 }.count
        if mine == 0 { return -1 }
        if theirs == 0 { return 1 }
        if quiet >= 60 { break }
    }
    // strict (3.43): a game nobody finished is a draw — what Atom sees in WePlay
    if strict { return 0 }
    // adjudicate by material (man 1, king 3) — a clear edge counts as a win
    var m = 0
    for v in b { m += v > 0 ? (v == 2 ? 3 : 1) : (v < 0 ? (v == -2 ? -3 : -1) : 0) }
    return m >= 3 ? 1 : (m <= -3 ? -1 : 0)
}

func ckOpening(_ rng: inout Rng, plies: Int) -> [Int] {
    var b = ckStart(), side = 1
    for _ in 0..<plies {
        let succ = CheckersRules.successors(b, side: side)
        if succ.isEmpty { break }
        b = succ[rng.int(succ.count)]; side = -side
    }
    // keep side-to-move = white(+1): add a ply if odd
    if plies % 2 == 1 { let s = CheckersRules.successors(b, side: -1); if !s.isEmpty { b = s[rng.int(s.count)] } }
    return b
}

func makeCkA(trap: Bool = true, contempt: Int? = nil) -> CkPlayer {
    let e = CheckersEngine()
    e.trapMode = trap
    if let c = contempt { e.contempt = c }
    if let d = try? Data(contentsOf: URL(fileURLWithPath: "hos-tb.bin")) { e.loadTB(d) }
    return { b, side in
        let r = e.search(b, side: side, maxMs: ms)
        guard let m = r.best else { return nil }
        return ckApply(b, side: side, path: e.path(of: m, board: b, side: side), caps: e.capsSquares(m))
    }
}
func makeCkB() -> CkPlayer {
    let e = CheckersEngineV0()
    if let d = try? Data(contentsOf: URL(fileURLWithPath: "hos-tb.bin")) { e.loadTB(d) }
    return { b, side in
        let r = e.search(b, side: side, maxMs: ms)
        guard let m = r.best else { return nil }
        return ckApply(b, side: side, path: e.path(of: m, board: b, side: side), caps: e.capsSquares(m))
    }
}

// MARK: runner
func runPairs(_ pairs: Int, _ one: @escaping (Int) -> (Outcome, Outcome)) -> (a: Int, b: Int, d: Int) {
    let lock = NSLock()
    var a = 0, b = 0, d = 0
    let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    var next = 0
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        while true {
            lock.lock(); let i = next; next += 1; lock.unlock()
            if i >= pairs { return }
            let (x, y) = one(i)
            lock.lock()
            for o in [x, y] { switch o { case .a: a += 1; case .b: b += 1; case .draw: d += 1 } }
            lock.unlock()
        }
    }
    return (a, b, d)
}

func elo(_ a: Int, _ b: Int, _ d: Int) -> String {
    let n = Double(a + b + d); guard n > 0 else { return "n/a" }
    let s = (Double(a) + Double(d) / 2) / n
    if s <= 0.001 { return "-inf" }; if s >= 0.999 { return "+inf" }
    let e = -400 * log10(1 / s - 1)
    // rough 95% error bar
    let v = (Double(a) * pow(1 - s, 2) + Double(b) * pow(s, 2) + Double(d) * pow(0.5 - s, 2)) / n
    let se = sqrt(v / n), lo = max(0.001, s - 1.96 * se), hi = min(0.999, s + 1.96 * se)
    return String(format: "%+.0f (%+.0f…%+.0f)", e, -400 * log10(1 / lo - 1), -400 * log10(1 / hi - 1))
}

let pairs = max(1, games / 2)
var result: (a: Int, b: Int, d: Int) = (0, 0, 0)
let t0 = Date()
switch game {
case "checkers", "checkers-notrap", "checkers-strict", "checkers-strict-c0":
    let trap = game != "checkers-notrap"
    strict = game.hasPrefix("checkers-strict")
    let ct: Int? = game == "checkers-strict-c0" ? 0 : nil
    result = runPairs(pairs) { i in
        var rng = Rng(s: 0x9E3779B97F4A7C15 &+ UInt64(i) &* 0x632BE59BD9B4E019)
        let open = ckOpening(&rng, plies: 2 + rng.int(4))
        let a = makeCkA(trap: trap, contempt: ct), b = makeCkB()
        let g1 = ckGame(a, b, opening: open), g2 = ckGame(b, a, opening: open)
        return (g1 == 1 ? .a : (g1 == -1 ? .b : .draw), g2 == -1 ? .a : (g2 == 1 ? .b : .draw))
    }
default:
    extraGames(game, pairs: pairs, ms: ms, result: &result)
}
let line = "\(game) \(ms)ms: new \(result.a) / old \(result.b) / draw \(result.d) · Elo \(elo(result.a, result.b, result.d)) · \(Int(Date().timeIntervalSince(t0)))s"
print(line)
try? line.write(toFile: "arena-result.txt", atomically: true, encoding: .utf8)
