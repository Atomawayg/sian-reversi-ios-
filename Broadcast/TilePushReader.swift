import Foundation

/// WePlay Tile Push (4×4): your map at the bottom, the opponent's at the top, the tile to place in the middle.
/// Calibrated on Atom's 1180×2556 recording (30 Oct). Each player gets four random pictures per game, so pictures are
/// grouped by comparing them with each other and learnt as yours / theirs while you play. Cells: see TP.
extension BoardReader {
    static let tpCols: [Double] = [417, 570, 722, 874]
    static let tpRows: [Double] = [1608, 1779, 1950, 2120]
    static let tpOppCols: [Double] = [306, 459, 612, 764]
    static let tpOppRows: [Double] = [417, 588, 759, 930]
    static let tpCentre = (x: 591.0, y: 1258.0)

    private static func tpSand(_ p: (Double, Double, Double)) -> Bool {
        p.0 > 230 && p.1 > 185 && p.1 < 228 && p.2 > 110 && p.2 < 175
    }

    /// One tile: 0 face down, 1 a picture (with its 26×26 colour sample, centred on the picture), 2 the joker,
    /// -1 not a resting tile (moving, covered, flashing).
    static func tpTile(_ s: Sampler, _ x: Double, _ y: Double) -> (kind: Int, sig: [Float]) {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        func px(_ X: Double, _ Y: Double) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int(X * sx))), min(s.h - 1, max(0, Int(Y * sy))))
        }
        var n = 0.0, orange = 0.0, white = 0.0, blue = 0.0
        var dy = -54.0
        while dy <= 54 {
            var dx = -54.0
            while dx <= 54 {
                let p = px(x + dx, y + dy)
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
                let p = px(x + dx, y + dy)
                if !(p.0 > 215 && p.1 > 210 && p.2 > 200) { m += 1; x0 = min(x0, dx); x1 = max(x1, dx); y0 = min(y0, dy); y1 = max(y1, dy) }
                dx += 2
            }
            dy += 2
        }
        if m < 30 { return (-1, []) }
        let cx = x + (x0 + x1) / 2, cy = y + (y0 + y1) / 2
        var sig = [Float](repeating: 0, count: tpSide * tpSide * 3)
        for j in 0..<tpSide { for i in 0..<tpSide {
            let p = px(cx - 52 + Double(i * 4), cy - 52 + Double(j * 4))
            let k = (j * tpSide + i) * 3
            sig[k] = Float(p.0); sig[k + 1] = Float(p.1); sig[k + 2] = Float(p.2)
        } }
        return (1, sig)
    }

    static let tpSide = 26
    /// how different two pictures are: mean colour difference, letting one slide a sample (4 px) each way
    static func tpDist(_ a: [Float], _ b: [Float]) -> Float {
        let S = tpSide
        func d(_ ox: Int, _ oy: Int) -> Float {
            var t: Float = 0, n = 0
            for j in max(0, oy)..<(S + min(0, oy)) {
                for i in max(0, ox)..<(S + min(0, ox)) {
                    let ka = (j * S + i) * 3, kb = ((j - oy) * S + (i - ox)) * 3
                    t += abs(a[ka] - b[kb]) + abs(a[ka + 1] - b[kb + 1]) + abs(a[ka + 2] - b[kb + 2])
                    n += 3
                }
            }
            return t / Float(max(1, n))
        }
        var best = d(0, 0)
        if best > 40 { return best }
        for oy in -1...1 { for ox in -1...1 where ox != 0 || oy != 0 { best = min(best, d(ox, oy)) } }
        return best
    }
    /// same picture below this (measured on Atom's recording: same ≤ 14, different ≥ 29)
    static let tpSame: Float = 20

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
        if all.filter({ $0 == 1 }).count >= 4 { return 2 }          // your four are known: the rest is theirs
        if all.filter({ $0 == 2 }).count >= 4 && tpLib.count == 8 { return 1 }
        return 0
    }

    static func looksLikeTilePush(_ s: Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        let sand = [(1100.0, 1250.0), (590, 1100), (100, 1000)].filter { tpSand(s.avg($0.0 * sx, $0.1 * sy, 3 * sx)) }.count
        guard sand >= 2 else { return false }
        var tiles = 0
        for y in tpRows { for x in tpCols {
            let p = s.avg((x - 50) * sx, (y - 50) * sy, 3 * sx)   // the tile's top-left corner: orange back or white face
            if (p.0 > 200 && p.0 - p.1 > 70 && p.2 < 120) || (p.0 > 220 && p.1 > 220 && p.2 > 215) { tiles += 1 }
        } }
        return tiles >= 13
    }

    static func readTilePush(_ s: Sampler) -> BoardMessage {
        let bad = BoardMessage(valid: false, cells: [], me: 0, myTurn: false)
        let now = Date().timeIntervalSince1970
        if now - tpLastSeen > 60 { tpReset() }
        tpLastSeen = now
        if tpBanner(s) { return bad }
        var pts: [(Double, Double)] = []
        for y in tpRows { for x in tpCols { pts.append((x, y)) } }
        for y in tpOppRows { for x in tpOppCols { pts.append((x, y)) } }
        pts.append(tpCentre)
        var tiles: [(kind: Int, sig: [Float])] = []
        for (k, p) in pts.enumerated() {
            let t = tpTile(s, p.0, p.1)
            if t.kind < 0 && k < 16 { return bad }   // your map mid-animation
            tiles.append(t)
        }
        // a new game starts face down
        if tiles.prefix(32).filter({ $0.kind == 0 }).count >= 28 { tpReset() }
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
        guard key == tpPrevKey else { return bad }
        var lib: [Int] = []
        for r in reps {
            var best = -1, bd: Float = .infinity
            for (i, p) in tpLib.enumerated() { let d = tpDist(r, p.sig); if d < bd { bd = d; best = i } }
            if best >= 0 && bd < tpSame { tpLib[best].sig = r; lib.append(best) }
            else { tpLib.append(TPPicture(sig: r)); lib.append(tpLib.count - 1) }
        }
        if tpLib.count > 12 { tpReset(); return bad }     // something went wrong: start over
        // whose turn: the seconds countdown on an avatar (you bottom left, the opponent top right)
        let tm = tpTimer(s, 157, 1907), to = tpTimer(s, 1024, 525)
        let turn = tm > 0.03 && tm > to + 0.02 ? 1 : (to > 0.03 && to > tm + 0.02 ? 2 : 0)
        let hand = local[32] >= 0 ? lib[local[32]] : -1
        if hand >= 0 && turn != 0 {
            tpObs = tpObs.turn == turn && tpObs.pic == hand ? (turn, hand, tpObs.n + 1) : (turn, hand, 1)
            if tpObs.n >= 2 { if turn == 1 { tpLib[hand].mine += 1 } else { tpLib[hand].opp += 1 } }
        } else { tpObs = (0, -1, 0) }
        // codes: yours 3…6, not known yet 7…13, the opponent's 1
        let owner = (0..<tpLib.count).map(tpOwner)
        let mineList = (0..<tpLib.count).filter { owner[$0] == 1 }, unknown = (0..<tpLib.count).filter { owner[$0] == 0 }
        var cells: [Int] = []
        for (t, l) in zip(tiles, local) {
            if t.kind < 0 { cells.append(1); continue }
            if t.kind != 1 { cells.append(t.kind); continue }
            let i = lib[l]
            if let m = mineList.firstIndex(of: i), m < 4 { cells.append(3 + m) }
            else if let u = unknown.firstIndex(of: i), u < 7 { cells.append(7 + u) }
            else { cells.append(1) }
        }
        let h = cells[32]
        return BoardMessage(valid: true, game: .tilePush, cells: cells, me: 1, myTurn: turn == 1 && (h == 2 || (h >= 3 && h <= 6)))
    }
}
