import Foundation

/// Jackaroo engine with WePlay's card rules.
/// Seats 0..3 (3 = you, 1 = partner). Stone position: -1 home, 0..75 track (absolute), 100+k lane slot k (0..3).
/// Stones move clockwise; seat s starts at track 19*s and enters its lane from track 19*s-2.
struct JKMove {
    enum Kind { case place, fwd, a1, a11, back, any5, split, swap, force, discard }
    var card: Int
    var rank: String
    var kind: Kind
    var steps = 0
    var moves: [(seat: Int, idx: Int, from: Int, to: Int)] = []
    var after: [[Int]] = []
    var score = 0.0
    var captures: [Int] = []   // seats whose stones get sent home
}

enum JackarooEngine {
    static let T = 76
    static func start(_ s: Int) -> Int { 19 * s }
    /// distance travelled from the seat's start: 0…74 on the way round, -1 just behind the start
    static func dist(_ s: Int, _ t: Int) -> Int {
        let d = ((t - start(s)) % T + T) % T
        return d == 75 ? -1 : d
    }
    static let cardCost: [String: Double] = ["K": 8, "A": 7, "J": 5, "7": 3, "5": 3, "4": 2, "10": 1]

    static func ownerAt(_ st: [[Int]], _ pos: Int) -> (Int, Int)? {
        for s in 0..<4 { for i in 0..<st[s].count where st[s][i] == pos { return (s, i) } }
        return nil
    }
    static func isProtected(_ st: [[Int]], _ pos: Int) -> Bool {
        if let o = ownerAt(st, pos) { return pos == start(o.0) }
        return false
    }

    static func fwdDest(_ st: [[Int]], _ s: Int, _ i: Int, _ n: Int) -> Int? {
        let p = st[s][i]
        if p < 0 { return nil }
        if p >= 100 {
            let k = p - 100
            if k + n > 3 { return nil }
            var j = k + 1
            while j <= k + n { if st[s].contains(100 + j) { return nil }; j += 1 }
            return 100 + k + n
        }
        let d = dist(s, p)
        var overshoot = false
        for step in 1...n {
            let dd = d + step
            if dd > 74 {
                let k = dd - 75
                if k > 3 { overshoot = true; break }
                if st[s].contains(100 + k) { return nil }
                if step == n { return 100 + k }
                continue
            }
            let pos = ((start(s) + dd) % T + T) % T
            if isProtected(st, pos) { return nil }
            if step == n {
                if let o = ownerAt(st, pos), o.0 == s { return nil }
                return pos
            }
        }
        if overshoot { // the lane is too short for this card: keep circling the track
            for step in 1...n { if isProtected(st, (p + step) % T) { return nil } }
            let pos = (p + n) % T
            if let o = ownerAt(st, pos), o.0 == s { return nil }
            return pos
        }
        return nil
    }

    static func backDest(_ st: [[Int]], _ s: Int, _ i: Int, _ n: Int) -> Int? {
        let p = st[s][i]
        if p < 0 || p >= 100 { return nil }
        for step in 1...n { if isProtected(st, ((p - step) % T + T) % T) { return nil } }
        let pos = ((p - n) % T + T) % T
        if let o = ownerAt(st, pos), o.0 == s { return nil }
        return pos
    }

    static func apply(_ st: [[Int]], _ s: Int, _ i: Int, _ dest: Int) -> ([[Int]], Int?) {
        var n = st
        var cap: Int? = nil
        if dest >= 0 && dest < T, let o = ownerAt(n, dest), !(o.0 == s && o.1 == i) { n[o.0][o.1] = -1; cap = o.0 }
        n[s][i] = dest
        return (n, cap)
    }

    static func generate(_ st: [[Int]], hand: [String], me: Int = 3) -> [JKMove] {
        let partner = (me + 2) % 4
        let ctrl = st[me].contains(where: { $0 < 100 }) ? me : partner
        var out: [JKMove] = []
        for (ci, c) in hand.enumerated() {
            func fw(_ n: Int, _ kind: JKMove.Kind) {
                for i in 0..<4 {
                    guard let d = fwdDest(st, ctrl, i, n) else { continue }
                    let (a, cap) = apply(st, ctrl, i, d)
                    out.append(JKMove(card: ci, rank: c, kind: kind, steps: n, moves: [(ctrl, i, st[ctrl][i], d)], after: a, captures: cap.map { [$0] } ?? []))
                }
            }
            if c == "K" || c == "A", let i = st[ctrl].firstIndex(of: -1) {
                let sp = start(ctrl)
                if !(ownerAt(st, sp).map { $0.0 == ctrl } ?? false) {
                    let (a, cap) = apply(st, ctrl, i, sp)
                    out.append(JKMove(card: ci, rank: c, kind: .place, moves: [(ctrl, i, -1, sp)], after: a, captures: cap.map { [$0] } ?? []))
                }
            }
            switch c {
            case "A": fw(1, .a1); fw(11, .a11)
            case "Q": fw(12, .fwd)
            case "2", "3", "6", "8", "9": fw(Int(c)!, .fwd)
            case "10":
                fw(10, .fwd)
                out.append(JKMove(card: ci, rank: c, kind: .force, after: st))
            case "4":
                for i in 0..<4 {
                    guard let d = backDest(st, ctrl, i, 4) else { continue }
                    let (a, cap) = apply(st, ctrl, i, d)
                    out.append(JKMove(card: ci, rank: c, kind: .back, steps: 4, moves: [(ctrl, i, st[ctrl][i], d)], after: a, captures: cap.map { [$0] } ?? []))
                }
            case "5":
                for s in 0..<4 { for i in 0..<4 where st[s][i] >= 0 {
                    guard let d = fwdDest(st, s, i, 5) else { continue }
                    let (a, cap) = apply(st, s, i, d)
                    out.append(JKMove(card: ci, rank: c, kind: .any5, steps: 5, moves: [(s, i, st[s][i], d)], after: a, captures: cap.map { [$0] } ?? []))
                } }
            case "7":
                fw(7, .fwd)
                for i in 0..<4 { for j in 0..<4 where i != j {
                    for a in 1...6 {
                        guard let d1 = fwdDest(st, ctrl, i, a) else { continue }
                        let (s1, c1) = apply(st, ctrl, i, d1)
                        if s1[ctrl][j] < 0 { continue }
                        guard let d2 = fwdDest(s1, ctrl, j, 7 - a) else { continue }
                        let (s2, c2) = apply(s1, ctrl, j, d2)
                        out.append(JKMove(card: ci, rank: c, kind: .split, steps: a,
                                          moves: [(ctrl, i, st[ctrl][i], d1), (ctrl, j, s1[ctrl][j], d2)], after: s2,
                                          captures: [c1, c2].compactMap { $0 }))
                    }
                } }
            case "J":
                for i in 0..<4 {
                    let p = st[ctrl][i]
                    if !(p >= 0 && p < T) || p == start(ctrl) { continue }
                    for s in 0..<4 where s != ctrl { for j in 0..<4 {
                        let q = st[s][j]
                        if !(q >= 0 && q < T) || q == start(s) { continue }
                        var n = st; n[ctrl][i] = q; n[s][j] = p
                        out.append(JKMove(card: ci, rank: c, kind: .swap, moves: [(ctrl, i, p, q), (s, j, q, p)], after: n))
                    } }
                }
            default: break
            }
        }
        return out
    }

    static func stoneValue(_ s: Int, _ p: Int) -> Double {
        if p < 0 { return 0 }
        if p >= 100 { return 100 + 4 * Double(p - 100) }
        return 12 + Double(dist(s, p))
    }

    static func evaluate(_ st: [[Int]], me: Int = 3) -> Double {
        let team: Set<Int> = [me, (me + 2) % 4]
        var sc = 0.0
        for s in 0..<4 {
            let sign: Double = team.contains(s) ? 1 : -1
            for p in st[s] { sc += sign * stoneValue(s, p) }
            if st[s].contains(start(s)) { sc += sign * 3 }
            // danger: stones the other team could hit on their next turn
            for p in st[s] {
                if !(p >= 0 && p < T) || p == start(s) { continue }
                var risk = 0.0
                for q in 0..<4 where team.contains(q) != team.contains(s) {
                    let w = q == (s + 3) % 4 ? 1.0 : 0.6   // the player right after s moves first
                    for qp in st[q] where qp >= 0 && qp < T {
                        let gap = ((p - qp) % T + T) % T
                        if gap >= 1 && gap <= 12 && dist(q, qp) + gap <= 74 { risk = max(risk, w * (gap == 4 || gap == 7 ? 0.3 : 0.45)) }
                        if ((qp - p) % T + T) % T == 4 { risk = max(risk, w * 0.3) }
                    }
                    if st[q].contains(-1) && p == start(q) { risk = max(risk, w * 0.5) }
                }
                sc -= sign * risk * stoneValue(s, p)
            }
        }
        return sc
    }

    static func best(_ st: [[Int]], hand: [String], me: Int = 3) -> JKMove? {
        if hand.isEmpty { return nil }
        var ms = generate(st, hand: hand, me: me)
        if ms.isEmpty {
            let ci = hand.indices.min { (cardCost[hand[$0]] ?? 0) < (cardCost[hand[$1]] ?? 0) }!
            return JKMove(card: ci, rank: hand[ci], kind: .discard)
        }
        let base = evaluate(st, me: me)
        for k in 0..<ms.count {
            if ms[k].kind == .force { ms[k].score = 6 - (cardCost["10"] ?? 0); continue }
            ms[k].score = evaluate(ms[k].after, me: me) - base - (cardCost[ms[k].rank] ?? 0)
        }
        return ms.max { $0.score < $1.score }
    }
}
