import Foundation

/// WePlay Tile Push: your map at the bottom, the opponent's at the top, the tile to place in the middle.
/// Maps seen: 3×3, 4×4, 5 wide × 4 high, 5×5. Calibrated on Atom's 1180×2556 recordings and screenshots (30 Oct). Each player gets random pictures each game, so pictures are grouped
/// by comparing them with each other and learnt as yours / theirs while you play. Cells: see TP.
extension BoardReader {
    /// Where everything is. Your map's top-left corner and the opponent's bottom-right stay put; tiles are 152.6 px apart
    /// across (125.3 on a 5×5 map, where everything is drawn smaller) and 1.1186 times that down. (Only these two spacings: with
/// any spacing allowed, a 5×5 map fits a 6×6 one of smaller tiles just as well.)
    struct TPLayout { var cols: Int; var rows: Int; var k: Double; var mine: [(Double, Double)]; var opp: [(Double, Double)]; var hand: (Double, Double, Double) }

    static func tpIsTile(_ p: (Double, Double, Double)) -> Bool {
        (p.0 > 200 && p.0 - p.1 > 70 && p.2 < 120) || (p.0 > 225 && p.1 > 225 && p.2 > 220)
    }
    /// bounding box of the tiles in an area: columns / rows where at least 30 % of the samples are tile
    static func tpBox(_ s: Sampler, _ X0: Double, _ X1: Double, _ Y0: Double, _ Y1: Double, white: Bool = false) -> (x0: Double, x1: Double, y0: Double, y1: Double)? {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        let nx = Int((X1 - X0) / 3), ny = Int((Y1 - Y0) / 3)
        var colHits = [Int](repeating: 0, count: nx), rowHits = [Int](repeating: 0, count: ny)
        for j in stride(from: 0, to: ny, by: 2) {
            for i in 0..<nx {
                let p = s.get(min(s.w - 1, Int((X0 + Double(i) * 3) * sx)), min(s.h - 1, Int((Y0 + Double(j) * 3) * sy)))
                let hit = white ? (p.0 > 225 && p.1 > 225 && p.2 > 220) : tpIsTile(p)
                if hit { colHits[i] += 1; rowHits[j] += 1 }
            }
        }
        let cx = (0..<nx).filter { Double(colHits[$0]) > 0.3 * Double((ny + 1) / 2) }
        let ry = stride(from: 0, to: ny, by: 2).filter { Double(rowHits[$0]) > 0.3 * Double(nx) }
        guard let a = cx.first, let b = cx.last, let c = ry.first, let d = ry.last else { return nil }
        return (X0 + Double(a) * 3, X0 + Double(b) * 3, Y0 + Double(c) * 3, Y0 + Double(d) * 3)
    }

    static func tpLayout(_ s: Sampler) -> TPLayout? {
        guard let m = tpBox(s, 200, 1100, 1400, 2400) else { return nil }
        let w = m.x1 - m.x0 + 1, h = m.y1 - m.y0 + 1
        var best: (e: Double, c: Int, r: Int, p: Double)? = nil
        for p in [152.6, 125.3] {
            let k = p / 152.6, py = p * 1.1186, lip = 9 * k
            let c = w / p, r = (h - lip) / py
            let C = Int(c.rounded()), R = Int(r.rounded())
            guard C >= 3 && C <= TP.maxSide && R >= 3 && R <= TP.maxSide else { continue }
            let e = abs(c - Double(C)) + abs(r - Double(R))
            if best == nil || e < best!.e { best = (e, C, R, p) }
        }
        guard let b = best, b.e < 0.3 else { return nil }
        let k = b.p / 152.6, py = b.p * 1.1186, lip = 9 * k
        var mine: [(Double, Double)] = [], opp: [(Double, Double)] = []
        for r in 0..<b.r { for c in 0..<b.c { mine.append((m.x0 + b.p * (Double(c) + 0.5), m.y0 + 0.44 * py + py * Double(r))) } }
        guard let o = tpBox(s, 0, 860, 200, 1160) else { return nil }
        for r in 0..<b.r { for c in 0..<b.c {
            opp.append((o.x1 - b.p * (Double(b.c - c) - 0.5), o.y1 - lip - py * Double(b.r - r) + 0.44 * py))
        } }
        // the tile in hand: the white face in the middle (drawn at the map's scale)
        var hand = (590.0, 1258.0, k)
        if let t = tpBox(s, 450, 730, 1120, 1420, white: true) { hand = ((t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2, k) }
        return TPLayout(cols: b.c, rows: b.r, k: k, mine: mine, opp: opp, hand: hand)
    }

    private static func tpSand(_ p: (Double, Double, Double)) -> Bool {
        p.0 > 230 && p.1 > 185 && p.1 < 228 && p.2 > 110 && p.2 < 175
    }

    /// One tile: 0 face down, 1 a picture (with its 26×26 colour sample, centred on the picture), 2 the joker,
    /// -1 not a resting tile (moving, covered, flashing).
    static func tpTile(_ s: Sampler, _ x: Double, _ y: Double, _ k: Double = 1) -> (kind: Int, sig: [Float]) {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        func px(_ X: Double, _ Y: Double) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int(X * sx))), min(s.h - 1, max(0, Int(Y * sy))))
        }
        var n = 0.0, orange = 0.0, white = 0.0, blue = 0.0
        var dy = -54.0
        while dy <= 54 {
            var dx = -54.0
            while dx <= 54 {
                let p = px(x + dx * k, y + dy * k)
                n += 1
                if p.0 > 200 && p.0 - p.1 > 70 && p.2 < 120 { orange += 1 }
                if p.0 > 225 && p.1 > 225 && p.2 > 220 { white += 1 }
                if p.2 > 180 && p.2 - p.0 > 80 { blue += 1 }
                dx += 3
            }
            dy += 3
        }
        if orange / n > 0.6 { return (0, []) }
        if white / n < 0.15 { return (-1, []) }
        if blue / n > 0.12 { return (2, []) }
        // the picture: whatever isn't the white tile face; centre the sample on its bounding box
        var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9, m = 0
        dy = -50
        while dy <= 50 {
            var dx = -50.0
            while dx <= 50 {
                let p = px(x + dx * k, y + dy * k)
                if !(p.0 > 215 && p.1 > 210 && p.2 > 200) { m += 1; x0 = min(x0, dx); x1 = max(x1, dx); y0 = min(y0, dy); y1 = max(y1, dy) }
                dx += 2
            }
            dy += 2
        }
        if m < 30 { return (-1, []) }
        let cx = x + (x0 + x1) / 2 * k, cy = y + (y0 + y1) / 2 * k
        // 8×8 blocks of average colour over the picture (block averages don't mind small shifts, scale or a low-res frame)
        var sig = [Float](repeating: 0, count: tpSide * tpSide * 3)
        let half = 46.0, step = 2 * half / Double(tpSide)
        for j in 0..<tpSide { for i in 0..<tpSide {
            var r = 0.0, g = 0.0, b = 0.0
            for v in 0..<3 { for u in 0..<3 {
                let p = px(cx + (-half + step * (Double(i) + (Double(u) + 0.5) / 3)) * k, cy + (-half + step * (Double(j) + (Double(v) + 0.5) / 3)) * k)
                r += p.0; g += p.1; b += p.2
            } }
            let q = (j * tpSide + i) * 3
            sig[q] = Float(r / 9); sig[q + 1] = Float(g / 9); sig[q + 2] = Float(b / 9)
        } }
        return (1, sig)
    }

    static let tpSide = 8
    /// how different two pictures are: mean colour difference, letting one slide a sample (4 px) each way
    static func tpDist(_ a: [Float], _ b: [Float]) -> Float {
        var t: Float = 0
        for i in 0..<min(a.count, b.count) { t += abs(a[i] - b[i]) }
        return t / Float(max(1, a.count))
    }
    /// same picture below this (Atom's 6×5 clip at 442 px wide: same ≲ 16, different ≳ 30)
    static let tpSame: Float = 24

    /// "YOUR TURN!" banner across the screen (it covers your top row)
    static func tpBanner(_ s: Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var n = 0.0, hit = 0.0
        var y = 1470.0
        while y <= 1550 {
            var x = 150.0
            while x <= 1040 {
                let p = s.get(Int(x * sx), Int(y * sy)); n += 1
                if p.0 > 245 && p.1 > 228 && p.2 < 175 { hit += 1 }
                x += 6
            }
            y += 8
        }
        return hit / n > 0.12
    }

    /// share of white pixels (the seconds countdown) on an avatar
    static func tpTimer(_ s: Sampler, _ cx: Double, _ cy: Double) -> Double {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var n = 0.0, hit = 0.0
        var dy = -70.0
        while dy <= 70 {
            var dx = -70.0
            while dx <= 70 {
                if dx * dx + dy * dy <= 4900 {
                    let p = s.get(Int((cx + dx) * sx), Int((cy + dy) * sy)); n += 1
                    if (p.0 + p.1 + p.2) / 3 > 235 { hit += 1 }
                }
                dx += 3
            }
            dy += 3
        }
        return hit / max(1, n)
    }

    /// The pictures seen this game and who they belong to (votes: in hand on your turn / on the opponent's).
    /// Each player gets four pictures at random each game, so they are learnt while you play.
    struct TPPicture { var sig: [Float]; var mine = 0; var opp = 0 }
    static var tpLib: [TPPicture] = []
    static var tpPrevKey: [Int] = []
    static var tpObs = (turn: 0, pic: -1, n: 0)
    static var tpLastSeen = 0.0
    /// what the last reading did (printed by the clip replay test)
    static var tpDebug = ""
    static var tpKinds = 4               // pictures each player has: one per column
    static var tpShape = 44              // columns × 10 + rows of the map being learnt

    static func tpReset() { tpLib = []; tpObs = (0, -1, 0); tpPrevKey = [] }

    /// whose picture: 1 yours, 2 the opponent's, 0 not known yet
    static func tpOwner(_ i: Int) -> Int {
        func voted(_ k: TPPicture) -> Int {
            if k.mine >= 2 && k.mine > 2 * k.opp { return 1 }
            if k.opp >= 2 && k.opp > 2 * k.mine { return 2 }
            return 0
        }
        let v = voted(tpLib[i])
        if v != 0 { return v }
        let all = tpLib.map(voted)
        if all.filter({ $0 == 1 }).count >= tpKinds { return 2 }          // all yours are known: the rest is theirs
        if all.filter({ $0 == 2 }).count >= tpKinds && tpLib.count == 2 * tpKinds { return 1 }
        return 0
    }

    static func looksLikeTilePush(_ s: Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        let sand = [(1100.0, 1250.0), (590, 1100), (100, 1000)].filter { tpSand(s.avg($0.0 * sx, $0.1 * sy, 3 * sx)) }.count
        guard sand >= 2 else { return false }
        // the banner or a tile animation can hide part of the map: still this game (the reading just waits)
        return tpBanner(s) || tpBox(s, 200, 1100, 1400, 2400) != nil
    }

    static func readTilePush(_ s: Sampler) -> BoardMessage {
        let bad = BoardMessage(valid: false, cells: [], me: 0, myTurn: false)
        let now = Date().timeIntervalSince1970
        if now - tpLastSeen > 60 { tpReset() }
        tpLastSeen = now
        if tpBanner(s) { tpDebug = "banner"; return bad }
        guard let L = tpLayout(s) else { tpDebug = "no layout"; return bad }
        let W = L.cols, H = L.rows
        if W * 10 + H != tpShape { tpReset(); tpShape = W * 10 + H }
        tpKinds = W
        var pts: [(Double, Double, Double)] = L.mine.map { ($0.0, $0.1, L.k) } + L.opp.map { ($0.0, $0.1, L.k) }
        pts.append(L.hand)
        let N = W * H
        var tiles: [(kind: Int, sig: [Float])] = []
        for (k, p) in pts.enumerated() {
            let t = tpTile(s, p.0, p.1, p.2)
            if t.kind < 0 && k < N { tpDebug = "\(W)x\(H) unreadable cell \(k)"; return bad }   // your map mid-animation
            tiles.append(t)
        }
        // a new game starts face down
        if tiles.prefix(2 * N).filter({ $0.kind == 0 }).count >= 2 * N - 4 { tpReset() }
        // same picture within this frame
        var reps: [[Float]] = [], local: [Int] = []
        for t in tiles {
            guard t.kind == 1 else { local.append(-1); continue }
            var best = -1, bd: Float = .infinity
            for (i, r) in reps.enumerated() { let d = tpDist(t.sig, r); if d < bd { bd = d; best = i } }
            if best >= 0 && bd < tpSame { local.append(best) } else { reps.append(t.sig); local.append(reps.count - 1) }
        }
        // only learn from a frame that matches the one before (nothing moving)
        let key = zip(tiles, local).map { $0.0.kind * 100 + $0.1 }
        defer { tpPrevKey = key }
        guard key == tpPrevKey else { tpDebug = "\(W)x\(H) moving"; return bad }
        var lib: [Int] = []
        for r in reps {
            var best = -1, bd: Float = .infinity
            for (i, p) in tpLib.enumerated() { let d = tpDist(r, p.sig); if d < bd { bd = d; best = i } }
            if best >= 0 && bd < tpSame {
                for q in 0..<r.count { tpLib[best].sig[q] = 0.8 * tpLib[best].sig[q] + 0.2 * r[q] }   // slow drift, no jumps
                lib.append(best)
            } else { tpLib.append(TPPicture(sig: r)); lib.append(tpLib.count - 1) }
        }
        // more pictures than the game has: two entries are the same picture read differently — merge the closest pair
        while tpLib.count > 2 * tpKinds {
            var bi = 0, bj = 1, bd: Float = .infinity
            for i in 0..<tpLib.count { for j in (i + 1)..<tpLib.count { let d = tpDist(tpLib[i].sig, tpLib[j].sig); if d < bd { bd = d; bi = i; bj = j } } }
            if bd > 2 * tpSame { break }
            tpLib[bi].mine += tpLib[bj].mine; tpLib[bi].opp += tpLib[bj].opp
            tpLib.remove(at: bj)
            lib = lib.map { $0 == bj ? bi : ($0 > bj ? $0 - 1 : $0) }
        }
        if tpLib.count > 2 * tpKinds + 6 { tpDebug = "\(W)x\(H) too many pictures \(tpLib.count): reset"; tpReset(); return bad }     // something went wrong: start over
        // whose turn: the seconds countdown on an avatar (you bottom left, the opponent top right)
        let tm = tpTimer(s, 157, 1907), to = tpTimer(s, 1024, 525)
        let turn = tm > 0.03 && tm > to + 0.02 ? 1 : (to > 0.03 && to > tm + 0.02 ? 2 : 0)
        let hand = local[2 * N] >= 0 ? lib[local[2 * N]] : -1
        tpDebug = String(format: "%dx%d k%.2f turn %d (me %.3f opp %.3f) hand %d lib %d votes %@", W, H, L.k, turn, tm, to, hand, tpLib.count,
                         tpLib.map { "\($0.mine)/\($0.opp)" }.joined(separator: " "))
        if hand >= 0 && turn != 0 {
            tpObs = tpObs.turn == turn && tpObs.pic == hand ? (turn, hand, tpObs.n + 1) : (turn, hand, 1)
            if tpObs.n >= 2 { if turn == 1 { tpLib[hand].mine += 1 } else { tpLib[hand].opp += 1 } }
        } else { tpObs = (0, -1, 0) }
        // codes: yours 3…8, not known yet 9…13, the opponent's 1
        let owner = (0..<tpLib.count).map(tpOwner)
        let mineList = (0..<tpLib.count).filter { owner[$0] == 1 }, unknown = (0..<tpLib.count).filter { owner[$0] == 0 }
        var codes: [Int] = []
        for (t, l) in zip(tiles, local) {
            if t.kind < 0 { codes.append(1); continue }
            if t.kind != 1 { codes.append(t.kind); continue }
            let i = lib[l]
            if let m = mineList.firstIndex(of: i), m < 6 { codes.append(3 + m) }
            else if let u = unknown.firstIndex(of: i), u < 5 { codes.append(9 + u) }
            else { codes.append(1) }
        }
        // what popping each of your bottom tiles would hand the opponent: a picture of theirs that tops one of their
        // columns → that column's run of it + 1 (0 = nothing useful / not theirs / not known)
        func pic(_ k: Int) -> Int { tiles[k].kind == 1 && local[k] >= 0 ? lib[local[k]] : (tiles[k].kind == 2 ? -2 : -1) }
        var gift = [Int](repeating: 0, count: W)
        for c in 0..<W {
            let b = pic((H - 1) * W + c)
            guard b >= 0, owner[b] == 2 else { continue }
            for oc in 0..<W {
                var run = 0
                for r in 0..<H {
                    let v = pic(N + r * W + oc)
                    if v == b || v == -2 { run += 1 } else { break }
                }
                if run > 0 { gift[c] = max(gift[c], min(run + 1, 13)) }
            }
        }
        let cells = TP.pack(cols: W, rows: H, mine: Array(codes[0..<N]), opp: Array(codes[N..<2 * N]), hand: codes[2 * N], gift: gift)
        let h = codes[2 * N]
        return BoardMessage(valid: true, game: .tilePush, cells: cells, me: 1, myTurn: turn == 1 && (h == 2 || (h >= 3 && h <= 8)))
    }
}
