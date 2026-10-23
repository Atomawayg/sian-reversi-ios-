import Foundation

/// Game rules used only to sanity-check what the screen reader saw (kept apart from the AI engines,
/// so checking never touches their search state). The move generators are deliberately a little
/// generous — a board is rejected only when no real move could have produced it.

// MARK: หมากฮอส
/// Board: 64 cells, row 0 at the top. +1/+2 = your man/king (bottom, men move up),
/// -1/-2 = opponent man/king (top, men move down).
enum CheckersRules {
    private static let dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    @inline(__always) private static func on(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 8 && c >= 0 && c < 8 }

    /// Every board `side` (+1 or -1) can reach in one move, captures and quiet moves alike.
    static func successors(_ b: [Int], side: Int) -> [[Int]] {
        var out: [[Int]] = []
        for i in 0..<64 where b[i] * side > 0 {
            let r = i / 8, c = i % 8, king = abs(b[i]) == 2
            var start = b; start[i] = 0
            if king { kingCaptures(start, from: i, piece: b[i], side: side, r: r, c: c, caps: [], out: &out) }
            else { manCaptures(start, from: i, piece: b[i], side: side, r: r, c: c, caps: [], out: &out) }
            // quiet moves
            if king {
                for (dr, dc) in dirs {
                    var rr = r + dr, cc = c + dc
                    while on(rr, cc) && b[rr * 8 + cc] == 0 {
                        var n = start; n[rr * 8 + cc] = b[i]; out.append(n)
                        rr += dr; cc += dc
                    }
                }
            } else {
                let fwd = side == 1 ? -1 : 1
                for dc in [-1, 1] where on(r + fwd, c + dc) && b[(r + fwd) * 8 + c + dc] == 0 {
                    var n = start; n[(r + fwd) * 8 + c + dc] = promote(b[i], row: r + fwd, side: side); out.append(n)
                }
            }
        }
        return out
    }

    private static func promote(_ piece: Int, row: Int, side: Int) -> Int {
        if abs(piece) == 1 && row == (side == 1 ? 0 : 7) { return 2 * side }
        return piece
    }

    private static func finish(_ b: [Int], at: Int, piece: Int, caps: [Int], out: inout [[Int]]) {
        var n = b
        for s in caps { n[s] = 0 }
        n[at] = piece
        out.append(n)
    }

    private static func manCaptures(_ b: [Int], from: Int, piece: Int, side: Int, r: Int, c: Int, caps: [Int], out: inout [[Int]]) {
        let fwd = side == 1 ? -1 : 1
        var found = false
        for dc in [-1, 1] {
            let r1 = r + fwd, c1 = c + dc, r2 = r + 2 * fwd, c2 = c + 2 * dc
            guard on(r2, c2) else { continue }
            let mid = r1 * 8 + c1, land = r2 * 8 + c2
            guard b[mid] * side < 0, !caps.contains(mid), b[land] == 0 else { continue }
            found = true
            let p = promote(piece, row: r2, side: side)
            if p != piece { finish(b, at: land, piece: p, caps: caps + [mid], out: &out) }   // promotion ends the move
            else { manCaptures(b, from: land, piece: piece, side: side, r: r2, c: c2, caps: caps + [mid], out: &out) }
        }
        if !found && !caps.isEmpty { finish(b, at: from, piece: piece, caps: caps, out: &out) }
    }

    private static func kingCaptures(_ b: [Int], from: Int, piece: Int, side: Int, r: Int, c: Int, caps: [Int], out: inout [[Int]]) {
        var found = false
        for (dr, dc) in dirs {
            var rr = r + dr, cc = c + dc
            while on(rr, cc) && b[rr * 8 + cc] == 0 { rr += dr; cc += dc }
            guard on(rr, cc) else { continue }
            let hit = rr * 8 + cc
            guard b[hit] * side < 0, !caps.contains(hit) else { continue }
            var lr = rr + dr, lc = cc + dc
            while on(lr, lc) && b[lr * 8 + lc] == 0 {   // any landing square behind it (generous)
                found = true
                kingCaptures(b, from: lr * 8 + lc, piece: piece, side: side, r: lr, c: lc, caps: caps + [hit], out: &out)
                lr += dr; lc += dc
            }
        }
        if !found && !caps.isEmpty { finish(b, at: from, piece: piece, caps: caps, out: &out) }
    }
}

// MARK: Reversi — cells 0 empty, 1 black, 2 white, 3 hole
enum ReversiRules {
    static func successors(_ b: [Int], colour: Int) -> [[Int]] {
        let opp = 3 - colour
        var out: [[Int]] = []
        for i in 0..<64 where b[i] == 0 {
            let r = i / 8, c = i % 8
            var n = b, any = false
            for dr in -1...1 { for dc in -1...1 where dr != 0 || dc != 0 {
                var rr = r + dr, cc = c + dc, run: [Int] = []
                while rr >= 0 && rr < 8 && cc >= 0 && cc < 8 && b[rr * 8 + cc] == opp { run.append(rr * 8 + cc); rr += dr; cc += dc }
                if !run.isEmpty && rr >= 0 && rr < 8 && cc >= 0 && cc < 8 && b[rr * 8 + cc] == colour {
                    any = true; for s in run { n[s] = colour }
                }
            } }
            if any { n[i] = colour; out.append(n) }
        }
        return out
    }
}

// MARK: เรียง 4 / 5 — cells row 0 at the top, 0 empty, 1 / 2 players
enum ConnectRules {
    static func successors(_ b: [Int], cols: Int, rows: Int, piece: Int) -> [[Int]] {
        var out: [[Int]] = []
        for c in 0..<cols {
            var r = rows - 1
            while r >= 0 && b[r * cols + c] != 0 { r -= 1 }
            if r >= 0 { var n = b; n[r * cols + c] = piece; out.append(n) }
        }
        return out
    }
}

// MARK: tracking
/// Keeps the last board we trust. A new reading is trusted when it is the same board, one or two
/// legal moves (by either player) after it, or when the same reading has stayed on screen for a while
/// (a new game, or moves we missed while the screen was covered).
final class BoardTracker {
    enum Verdict { case same, moved, resynced, suspicious }

    private(set) var trusted: [Int]? = nil
    private var candidate: [Int]? = nil
    private var candidateSince = Date.distantPast
    private let settle: TimeInterval

    init(settle: TimeInterval = 2.5) { self.settle = settle }

    func reset() { trusted = nil; candidate = nil }

    /// `next(board, player)` lists boards reachable in one move by player 0 or 1.
    func check(_ board: [Int], next: ([Int], Int) -> [[Int]]) -> Verdict {
        guard let t = trusted else { return settleCandidate(board, firstSighting: true) }
        if board == t { candidate = nil; return .same }
        for p in 0..<2 {
            let one = next(t, p)
            if one.contains(board) { trusted = board; candidate = nil; return .moved }
            for b1 in one where next(b1, 1 - p).contains(board) { trusted = board; candidate = nil; return .moved }
        }
        return settleCandidate(board, firstSighting: false)
    }

    /// For games where pieces never move or disappear (4/5 in a row): any reading that still contains every
    /// trusted piece is fine, however many moves were missed in between.
    func checkGrowing(_ board: [Int]) -> Verdict {
        guard let t = trusted, t.count == board.count else { return settleCandidate(board, firstSighting: trusted == nil) }
        if board == t { candidate = nil; return .same }
        if board.allSatisfy({ $0 == 0 }) { trusted = board; candidate = nil; return .resynced }   // new game
        if zip(t, board).allSatisfy({ $0 == 0 || $0 == $1 }) { trusted = board; candidate = nil; return .moved }
        return settleCandidate(board, firstSighting: false)
    }

    private func settleCandidate(_ board: [Int], firstSighting: Bool) -> Verdict {
        let now = Date()
        if candidate != board { candidate = board; candidateSince = now }
        // the very first board of a session only has to survive one more burst
        let need = firstSighting ? 0.6 : settle
        if now.timeIntervalSince(candidateSince) >= need { trusted = board; candidate = nil; return .resynced }
        return .suspicious
    }
}
