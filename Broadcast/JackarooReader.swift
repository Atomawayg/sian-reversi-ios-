import Foundation

/// WePlay Jackaroo: stones on every hole, seat colours, and the cards in your hand.
extension BoardReader {
    /// seat colours stay the same for a whole game, so remember them once all four are clear
    static var lockedSeats: [Int]? = nil
    static var digitBase = 1.0

    /// 0 none, 1 green, 2 red, 3 blue, 4 orange
    private static func stoneColour(_ p: (Double, Double, Double), loose: Bool = false) -> Int {
        let r = p.0 / 255, g = p.1 / 255, b = p.2 / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let v = mx, sat = mx > 0 ? (mx - mn) / mx : 0
        if loose { if v < 0.3 || sat < 0.35 { return 0 } } else { if v < 0.6 || sat < 0.45 { return 0 } }
        var h: Double
        if mx == mn { h = 0 }
        else if mx == r { h = 60 * ((g - b) / (mx - mn)) }
        else if mx == g { h = 60 * ((b - r) / (mx - mn) + 2) }
        else { h = 60 * ((r - g) / (mx - mn) + 4) }
        if h < 0 { h += 360 }
        if h >= 75 && h <= 160 { return 1 }
        if h >= 180 && h <= 260 { return 3 }
        if h < 20 || h > 340 { return 2 }
        if h >= 22 && h <= 55 && sat > 0.7 && (loose || v > 0.8) { return 4 }
        return 0
    }

    static func readJackaroo(_ s: Sampler) -> BoardMessage {
        let W = Double(s.w), H = Double(s.h)
        let sx = W / 1180, sy = H / 2556
        var cells = [Int](repeating: 0, count: JK.count)
        func hole(_ p: (Double, Double)) -> Int { stoneColour(s.avg(p.0 * sx, p.1 * sy, 7 * sx)) }
        for t in 0..<76 { cells[JK.track + t] = hole(JKGeo.track[t]) }
        for seat in 0..<4 { for k in 0..<4 {
            cells[JK.lanes + 4 * seat + k] = hole(JKGeo.lanes[seat][k])
            cells[JK.homes + 4 * seat + k] = hole(JKGeo.homes[seat][k])
        } }
        // seat colours: every lane slot, home spot and start square has a ring in its seat's colour
        var seatCol = [Int](repeating: 0, count: 4)
        for seat in 0..<4 {
            var votes = [Int](repeating: 0, count: 5)
            let pts = JKGeo.lanes[seat] + JKGeo.homes[seat] + [JKGeo.track[19 * seat]]
            for c in pts { for rr in [21.0, 23.0, 25.0] { for k in 0..<16 {
                let ang = Double(k) * Double.pi / 8
                let x = Int((c.0 + rr * cos(ang)) * sx), y = Int((c.1 + rr * sin(ang)) * sy)
                if x >= 0 && x < s.w && y >= 0 && y < s.h { votes[stoneColour(s.get(x, y), loose: true)] += 1 }
            } } }
            votes[0] = 0
            if let m = (1...4).max(by: { votes[$0] < votes[$1] }), votes[m] >= 40 { seatCol[seat] = m }
        }
        if Set(seatCol).count == 4 && !seatCol.contains(0) { lockedSeats = seatCol }
        else if let l = lockedSeats { seatCol = l }
        else {
            let missing = (0..<4).filter { seatCol[$0] == 0 }
            let free = (1...4).filter { !seatCol.contains($0) }
            if missing.count == 1 && free.count == 1 { seatCol[missing[0]] = free[0] }
        }
        for seat in 0..<4 { cells[JK.seats + seat] = seatCol[seat] }

        // stones of every colour must add up to 4; otherwise the frame is mid-animation or covered
        var count = [Int](repeating: 0, count: 5)
        for i in 0..<JK.seats { count[cells[i]] += 1 }
        let sane = (1...4).allSatisfy { count[$0] <= 4 } && (1...4).reduce(0) { $0 + count[$1] } >= 8

        // your hand: white cards can be played, grey ones cannot (or it is not your turn)
        let hand = readHand(s)
        for (k, c) in hand.prefix(5).enumerated() { cells[JK.hand + k] = c.rank; cells[JK.playable + k] = c.white ? 1 : 0 }
        // your turn: the countdown digits over your avatar (bottom-left)
        var dig = 0, tot = 0
        var yy = 1520.0
        while yy < 1640 {
            var xx = 90.0
            while xx < 240 {
                let p = s.get(Int(xx * sx), Int(yy * sy))
                if p.0 > 225 && p.1 > 140 && p.1 < 225 && p.2 < 90 { dig += 1 }
                tot += 1; xx += 3
            }
            yy += 3
        }
        let frac = Double(dig) / Double(max(1, tot))
        digitBase = min(digitBase + 0.0005, frac)
        let timer = frac > max(0.03, digitBase + 0.015)
        let anyWhite = hand.contains { $0.white }
        // the red DISCARD banner across the middle of the board: someone has to throw a card away
        var red = 0, rtot = 0
        var dy = 960.0
        while dy < 1100 {
            var dx = 330.0
            while dx < 850 {
                let p = s.get(Int(dx * sx), Int(dy * sy))
                if p.0 > 150 && p.0 > p.1 * 1.8 && p.0 > p.2 * 1.8 { red += 1 }
                rtot += 1; dx += 4
            }
            dy += 4
        }
        let banner = Double(red) / Double(max(1, rtot)) > 0.12
        cells[JK.discard] = banner ? 1 : 0
        return BoardMessage(valid: sane, game: .jackaroo, cells: cells, me: seatCol[3], myTurn: sane && !hand.isEmpty && (timer || anyWhite))
    }

    @inline(__always) private static func gray(_ p: (Double, Double, Double)) -> Double { 0.299 * p.0 + 0.587 * p.1 + 0.114 * p.2 }

    /// Rank codes (1 A … 13 K) of the white cards, left to right. Grey cards (not your turn) are ignored.
    private static func readHand(_ s: Sampler) -> [(rank: Int, white: Bool)] {
        let W = s.w, H = s.h
        let ys = Int(Double(H) * 1900 / 2556), ye = Int(Double(H) * 2300 / 2556)
        let rowStep = 4
        var colLight = [Double](repeating: 0, count: W)
        var rows = 0
        var y = ys
        while y < ye {
            var x = 0
            while x < W { if gray(s.get(x, y)) > 170 { colLight[x] += 1 }; x += 1 }
            rows += 1; y += rowStep
        }
        if rows == 0 { return [] }
        for x in 0..<W { colLight[x] /= Double(rows) }
        var segs: [(Int, Int)] = []
        var inside = false, st = 0
        for x in 0..<W {
            let v = colLight[x]
            if v > 0.35 && !inside { inside = true; st = x }
            if (v <= 0.35 || x == W - 1) && inside {
                inside = false
                if Double(x - st) > Double(W) * 0.12 { segs.append((st, x)) }
            }
        }
        var ranks: [(rank: Int, white: Bool)] = []
        let cardW = Double(W) * 0.178          // one card
        let stackStep = cardW * 0.785           // grey cards overlap like this
        for (a0, b0) in segs {
            let w = Double(b0 - a0)
            var lefts: [Int] = [a0]
            if w > cardW * 1.15 {
                let gapped = Int((w / cardW).rounded())
                let stacked = Int(((w - cardW) / stackStep).rounded()) + 1
                // separate white cards sit ~cardW apart; stacked grey ones ~stackStep apart
                let spread = abs(w - Double(gapped) * cardW) <= abs(w - (cardW + Double(stacked - 1) * stackStep)) ? cardW : stackStep
                let n = spread == cardW ? gapped : stacked
                lefts = (0..<max(1, n)).map { a0 + Int(Double($0) * spread) }
            }
            for a in lefts {
                let b = a + Int(cardW)
                let cw = cardW
                // top edge of the card
                var top = -1
                var yy = ys
                while yy < ye {
                    var lit = 0, tot = 0
                    var xx = a + Int(cw * 0.3)
                    while xx < a + Int(cw * 0.5) { if gray(s.get(xx, yy)) > 170 { lit += 1 }; tot += 1; xx += 2 }
                    if tot > 0 && Double(lit) / Double(tot) > 0.6 { top = yy; break }
                    yy += 1
                }
                if top < 0 { continue }
                // white (your turn) or grey
                var body: [Double] = []
                var by = top
                while by < min(H - 1, top + Int(cw * 0.8)) {
                    var bx = a + Int(cw * 0.25)
                    while bx < b - Int(cw * 0.1) { body.append(gray(s.get(bx, by))); bx += 6 }
                    by += 6
                }
                body.sort()
                if body.isEmpty { continue }
                let white = body[body.count / 2] > 230
                if let r = rankOf(s, a, min(b, W - 1), top) { ranks.append((r, white)) }
            }
        }
        return ranks
    }

    private static func rankOf(_ s: Sampler, _ a: Int, _ b: Int, _ top: Int) -> Int? {
        let w = Double(b - a)
        let y0 = top + Int(0.03 * w), y1 = top + Int(0.24 * w), x0 = a + Int(0.03 * w), x1 = a + Int(0.36 * w)
        let hh = y1 - y0, ww = x1 - x0
        if hh < 8 || ww < 6 || y1 >= s.h || x1 >= s.w { return nil }
        var ink = [Bool](repeating: false, count: hh * ww)
        var rowCnt = [Int](repeating: 0, count: hh), colCnt = [Int](repeating: 0, count: ww)
        for yy in 0..<hh { for xx in 0..<ww {
            let p = s.get(x0 + xx, y0 + yy)
            let on = gray(p) < 120 || (p.0 - p.1) > 70
            if on { ink[yy * ww + xx] = true; rowCnt[yy] += 1; colCnt[xx] += 1 }
        } }
        let rs = (0..<hh).filter { rowCnt[$0] >= 2 }, cs = (0..<ww).filter { colCnt[$0] >= 2 }
        guard rs.count >= 4, cs.count >= 2, let ry0 = rs.first, let ry1 = rs.last, let cx0 = cs.first, let cx1 = cs.last else { return nil }
        let BH = ry1 - ry0 + 1, BW = cx1 - cx0 + 1
        var feat = [Double](repeating: 0, count: 320)
        for i in 0..<20 { for j in 0..<16 {
            let ya = i * BH / 20, yb = max(ya + 1, (i + 1) * BH / 20)
            let xa = j * BW / 16, xb = max(xa + 1, (j + 1) * BW / 16)
            var on = 0, tot = 0
            for yy in ya..<yb { for xx in xa..<xb {
                if ink[(ry0 + yy) * ww + cx0 + xx] { on += 1 }; tot += 1
            } }
            feat[i * 16 + j] = Double(on) / Double(max(1, tot))
        } }
        let aspect = Double(BW) / Double(BH)
        var best = ""
        var bestD = Double.infinity
        for t in JKGeo.templates {
            var d = 0.0
            var k = 0
            for ch in t.cells.utf8 { d += abs(feat[k] - Double(ch - 48) / 9); k += 1 }
            d = d / 320 + 0.3 * abs(aspect - t.aspect)
            if d < bestD { bestD = d; best = t.rank }
        }
        if bestD > 0.25 { return nil }
        return JK.rankNames.firstIndex(of: best)
    }
}
