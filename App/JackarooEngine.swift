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
                if ownerAt(st, sp) == nil {   // WePlay: a new stone needs an empty start square
                    var a = st; a[ctrl][i] = sp
                    out.append(JKMove(card: ci, rank: c, kind: .place, moves: [(ctrl, i, -1, sp)], after: a))
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

    // MARK: look one turn ahead
    static let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    static let pHold = 0.28   // chance an opponent holds at least one card of a given rank

    static func material(_ st: [[Int]], me: Int = 3) -> Double {
        let team: Set<Int> = [me, (me + 2) % 4]
        var sc = 0.0
        for s in 0..<4 {
            let sign: Double = team.contains(s) ? 1 : -1
            for p in st[s] { sc += sign * stoneValue(s, p) }
            if st[s].contains(start(s)) { sc += sign * 3 }
        }
        return sc
    }

    /// Expected loss to my team from opponent q's best reply, when we don't know q's cards.
    static func threat(_ st: [[Int]], from q: Int, me: Int = 3) -> Double {
        let base = material(st, me: me)
        var gains: [Double] = []
        for r in ranks {
            var g = 0.0
            for m in generate(st, hand: [r], me: q) where m.kind != .force {
                g = max(g, base - material(m.after, me: me))
            }
            gains.append(g)
        }
        gains.sort(by: >)
        var e = 0.0, miss = 1.0
        for g in gains where g > 0 { e += g * pHold * miss; miss *= 1 - pHold }
        return e
    }

    static func position(_ st: [[Int]], me: Int = 3) -> Double {
        let next = (me + 3) % 4, later = (me + 1) % 4   // play goes me → next → partner → later
        return material(st, me: me) - threat(st, from: next, me: me) - 0.6 * threat(st, from: later, me: me)
    }

    /// How much a card is worth keeping for later turns (used to choose a discard).
    static func keepValue(_ st: [[Int]], _ c: String, me: Int = 3) -> Double {
        let ctrl = st[me].contains(where: { $0 < 100 }) ? me : (me + 2) % 4
        let mine = st[ctrl]
        let home = mine.filter { $0 < 0 }.count
        let on = mine.filter { $0 >= 0 && $0 < T }
        switch c {
        case "K": return home > 0 ? 10 : 1
        case "A": return home > 0 ? 10 : 4
        case "4": return on.contains { let d = dist(ctrl, $0); return d >= 0 && d <= 6 } ? 5 : 2
        case "5": return 3
        case "J": return on.isEmpty ? 2 : 4
        case "7": return 4
        case "10": return 3
        default:
            let n = c == "Q" ? 12 : (Int(c) ?? 0)
            var v = 1 + Double(n) / 24
            for p in on { let d = dist(ctrl, p); if d + n >= 75 && d + n <= 78 { v += 5 } }
            return v
        }
    }

    /// playable: which cards the game shows white (allowed). Returns the move to make, or a card to discard.
    static func best(_ st: [[Int]], hand: [String], playable: [Bool]? = nil, me: Int = 3) -> JKMove? {
        if hand.isEmpty { return nil }
        let ok = playable ?? Array(repeating: true, count: hand.count)
        var ms: [JKMove] = []
        for (ci, c) in hand.enumerated() where ci < ok.count && ok[ci] {
            for var m in generate(st, hand: [c], me: me) { m.card = ci; ms.append(m) }
        }
        if ms.isEmpty {
            let ci = hand.indices.min { keepValue(st, hand[$0], me: me) < keepValue(st, hand[$1], me: me) }!
            return JKMove(card: ci, rank: hand[ci], kind: .discard)
        }
        let here = position(st, me: me)
        for k in 0..<ms.count {
            if ms[k].kind == .force { ms[k].score = here + 3; continue }
            ms[k].score = position(ms[k].after, me: me) - (cardCost[ms[k].rank] ?? 0)
        }
        return ms.max { $0.score < $1.score }
    }

    // MARK: strongest search: sample the hidden hands and play the next 7 turns out
    struct RNG { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) } }

    /// What a decent player does: the move that is best for their team right now (captures included).
    static func greedy(_ st: [[Int]], _ hand: [String], _ q: Int) -> JKMove? {
        var best: JKMove? = nil
        var bv = -Double.infinity
        for (ci, c) in hand.enumerated() {
            for var m in generate(st, hand: [c], me: q) where m.kind != .force {
                m.card = ci
                let v = material(m.after, me: q)
                if v > bv { bv = v; best = m }
            }
        }
        return best
    }

    static func rollout(_ st: [[Int]], mine: [String], others: [Int: [String]], me: Int, plies: Int) -> Double {
        let order = [(me + 3) % 4, (me + 2) % 4, (me + 1) % 4, me]
        var hands = others
        hands[me] = mine
        var cur = st
        for i in 0..<plies {
            let q = order[i % 4]
            guard var h = hands[q], !h.isEmpty else { continue }
            if let m = greedy(cur, h, q) { h.remove(at: m.card); cur = m.after } else { h.removeFirst() }
            hands[q] = h
        }
        return evaluate(cur, me: me)
    }

    static func stateSeed(_ st: [[Int]], _ hand: [String]) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for row in st { for p in row { h = (h ^ UInt64(bitPattern: Int64(p + 7))) &* 1099511628211 } }
        for c in hand.sorted() { for u in c.utf8 { h = (h ^ UInt64(u)) &* 1099511628211 } }
        return h
    }

    /// Best move found by playing every candidate out against many sampled deals (same deals for every candidate,
    /// seeded by the position, so the same position always gives the same answer).
    static func bestDeep(_ st: [[Int]], hand: [String], playable: [Bool]?, me: Int = 3, samples: Int = 64, plies: Int = 7) -> JKMove? {
        if hand.isEmpty { return nil }
        let ok = playable ?? Array(repeating: true, count: hand.count)
        var cands: [JKMove] = []
        for (ci, c) in hand.enumerated() where ci < ok.count && ok[ci] {
            for var m in generate(st, hand: [c], me: me) where m.kind != .force { m.card = ci; cands.append(m) }
        }
        let forceIdx = hand.indices.first { $0 < ok.count && ok[$0] && hand[$0] == "10" }
        if cands.isEmpty {
            if let fi = forceIdx { return JKMove(card: fi, rank: "10", kind: .force, after: st) }
            let ci = hand.indices.min { (keepValue(st, hand[$0], me: me), $0) < (keepValue(st, hand[$1], me: me), $1) }!
            return JKMove(card: ci, rank: hand[ci], kind: .discard)
        }
        // de-duplicate identical results (e.g. two equal cards)
        var seen = Set<String>()
        cands = cands.filter { m in
            let k = m.rank + ":" + m.after.map { $0.sorted().map(String.init).joined(separator: ",") }.joined(separator: "|")
            return seen.insert(k).inserted
        }
        var rng = RNG(s: stateSeed(st, hand))
        var deck: [String] = []
        for r in ranks { for _ in 0..<4 { deck.append(r) } }
        for c in hand { if let i = deck.firstIndex(of: c) { deck.remove(at: i) } }
        let n = max(1, hand.count - 1)
        var deals: [[Int: [String]]] = []
        for _ in 0..<samples {
            var d = deck
            for i in stride(from: d.count - 1, to: 0, by: -1) { d.swapAt(i, rng.int(i + 1)) }
            var deal: [Int: [String]] = [:]
            for (k, q) in [(me + 3) % 4, (me + 2) % 4, (me + 1) % 4].enumerated() { deal[q] = Array(d[(k * n)..<min(d.count, (k + 1) * n)]) }
            deals.append(deal)
        }
        for k in 0..<cands.count {
            var rest = hand; rest.remove(at: cands[k].card)
            var total = 0.0
            for d in deals { total += rollout(cands[k].after, mine: rest, others: d, me: me, plies: plies) }
            cands[k].score = total / Double(samples) - 0.5 * (cardCost[cands[k].rank] ?? 0)
        }
        // stable order: best score, then the earlier card, then the first generated
        var bestIdx = 0
        for k in 1..<cands.count where cands[k].score > cands[bestIdx].score + 1e-9 { bestIdx = k }
        return cands[bestIdx]
    }
}
