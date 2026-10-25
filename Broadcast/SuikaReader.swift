import Foundation

/// WePlay Frog Watermelon: every fruit in the jar, the fruit Will holds, and the next fruit (centre of the wheel).
/// Calibrated on a 1179×2556 screenshot. Fruits are rigid circles that never overlap, so each one is found as a
/// disc of its own colour and size, biggest first; a found disc is claimed so smaller fruits can't reuse it.
extension BoardReader {
    /// colour groups: 0 background / outline, 1 red (cherry, apple), 2 pink-red (strawberry), 3 purple (grape),
    /// 4 yellow (dekopon, pear, pineapple), 5 orange (persimmon), 6 pale pink / white (peach), 7 green (melon, watermelon)
    static func skGroup(_ p: (Double, Double, Double)) -> UInt8 {
        let r = p.0, g = p.1, b = p.2
        let mx = max(r, g, b), mn = min(r, g, b)
        let v = mx / 255, s = mx > 0 ? (mx - mn) / mx : 0
        var h = 0.0
        if mx != mn {
            if mx == r { h = 60 * ((g - b) / (mx - mn)) }
            else if mx == g { h = 60 * ((b - r) / (mx - mn) + 2) }
            else { h = 60 * ((r - g) / (mx - mn) + 4) }
        }
        if h < 0 { h += 360 }
        if v < 0.35 { return 0 }
        if s >= 0.52 && (h >= 335 || h <= 14) { return b - g > 8 ? 2 : 1 }
        if (s >= 0.25 || (s >= 0.12 && v > 0.8)) && h >= 235 && h <= 305 { return 3 }
        if s >= 0.45 && h >= 35 && h <= 60 { return 4 }
        if s >= 0.58 && h >= 17 && h < 35 { return 5 }
        if s >= 0.3 && h >= 62 && h <= 170 { return 7 }
        if v > 0.78 && s <= 0.55 && (h >= 330 || h < 12) { return 6 }
        if v > 0.9 && s < 0.12 { return 6 }
        return 0
    }

    /// colour groups each fruit type is drawn in (bit mask)
    static let skMask: [UInt16] = [
        1 << 1 | 1 << 2,         // cherry (reads pinker on some screens)
        1 << 2 | 1 << 1,         // strawberry
        1 << 3,                  // grape
        1 << 4,                  // dekopon
        1 << 5,                  // persimmon
        1 << 1 | 1 << 2,         // apple
        1 << 4,                  // pear
        1 << 6 | 1 << 2 | 1 << 1, // peach
        1 << 4,                  // pineapple
        1 << 7,                  // melon
        1 << 7,                  // watermelon
    ]

    /// The fruit game screen: blue sky on both sides of a white-walled jar and the wooden sign at the top.
    static func looksLikeSuika(_ s: Sampler) -> Bool {
        let sx = Double(s.w) / 1179, sy = Double(s.h) / 2556
        func at(_ x: Double, _ y: Double) -> (Double, Double, Double) { s.avg(x * sx, y * sy, 3 * sx) }
        // the sky's blue varies between recordings and screenshots: (111,190,249) on one, (69,189,255) on another
        func sky(_ p: (Double, Double, Double)) -> Bool { p.2 > 215 && p.1 > 155 && p.1 < 220 && p.0 > 40 && p.0 < 150 && p.2 - p.0 > 80 }
        func white(_ p: (Double, Double, Double)) -> Bool { min(p.0, p.1, p.2) > 232 }
        guard sky(at(30, 1300)), sky(at(1150, 1300)), sky(at(30, 1900)), sky(at(1150, 1900)) else { return false }
        guard white(at(70, 1500)), white(at(1108, 1500)), white(at(70, 2000)), white(at(1108, 2000)) else { return false }
        return true
    }

    static func readSuika(_ s: Sampler) -> BoardMessage {
        let sx = Double(s.w) / 1179, sy = Double(s.h) / 2556
        let S = 4.0                                   // grid step in screenshot pixels
        let X0 = SK.left, Y0 = SK.top
        let gw = Int((SK.right - X0) / S), gh = Int((SK.floor + 6 - Y0) / S)
        var grid = [UInt8](repeating: 0, count: gw * gh)
        for j in 0..<gh {
            let y = Int((Y0 + Double(j) * S + S / 2) * sy)
            for i in 0..<gw {
                grid[j * gw + i] = skGroup(s.get(Int((X0 + Double(i) * S + S / 2) * sx), y))
            }
        }
        var claimed = [Bool](repeating: false, count: gw * gh)
        // sample points of a disc: centre and three rings
        var unit: [(Double, Double)] = [(0, 0)]
        for (fr, k) in [(0.3, 8), (0.55, 12), (0.8, 18)] {
            for a in 0..<k { let t = 2 * Double.pi * Double(a) / Double(k); unit.append((fr * cos(t), fr * sin(t))) }
        }
        func on(_ x: Int, _ y: Int, _ m: UInt16) -> Bool {
            if x < 0 || x >= gw || y < 0 || y >= gh { return false }
            let k = y * gw + x
            return !claimed[k] && grid[k] != 0 && m & (1 << UInt16(grid[k])) != 0
        }
        /// share of the disc's sample points in the fruit's colour, and share of the outer ring alone
        /// (a big disc over a smaller fruit of the same colour fills its middle but not its rim)
        func score(_ ci: Double, _ cj: Double, _ rr: Double, _ m: UInt16) -> (all: Double, rim: Double) {
            var hit = 0, rim = 0
            for (k, (ux, uy)) in unit.enumerated() where on(Int((ci + ux * rr).rounded()), Int((cj + uy * rr).rounded()), m) {
                hit += 1
                if k >= 21 { rim += 1 }
            }
            return (Double(hit) / Double(unit.count), Double(rim) / Double(unit.count - 21))
        }
        /// hits on a ring just inside the edge: highest when the centre is right
        func edge(_ ci: Double, _ cj: Double, _ rr: Double, _ m: UInt16) -> Int {
            var h = 0
            for a in 0..<36 {
                let t = 2 * Double.pi * Double(a) / 36
                if on(Int((ci + 0.88 * rr * cos(t)).rounded()), Int((cj + 0.88 * rr * sin(t)).rounded()), m) { h += 1 }
            }
            return h
        }
        /// Tests measured on recordings: the disc's edge lies on the fruit, and the big look-alikes are told apart
        /// (a pear beside a dekopon is not a pineapple, an apple is not a peach, melon vs watermelon).
        func lookAlikeOK(_ t: Int, _ ci: Double, _ cj: Double, _ rr: Double, _ m: UInt16) -> Bool {
            var h = 0
            for a in 0..<32 {
                let th = 2 * Double.pi * Double(a) / 32
                if on(Int((ci + 0.93 * rr * cos(th)).rounded()), Int((cj + 0.93 * rr * sin(th)).rounded()), m) { h += 1 }
            }
            if Double(h) / 32 < 0.35 { return false }
            if t < 7 { return true }
            var n = 0, pale = 0, red = 0, band = 0, bandOwn = 0
            let R = Int(rr) + 1
            for y in max(0, Int(cj) - R)...min(gh - 1, Int(cj) + R) {
                for x in max(0, Int(ci) - R)...min(gw - 1, Int(ci) + R) {
                    let d = ((Double(x) - ci) * (Double(x) - ci) + (Double(y) - cj) * (Double(y) - cj)).squareRoot()
                    let g = grid[y * gw + x]
                    if d <= 0.85 * rr { n += 1; if g == 6 { pale += 1 }; if g == 1 || g == 2 { red += 1 } }
                    if d > 0.6 * rr && d < 0.95 * rr { band += 1; if on(x, y, m) { bandOwn += 1 } }
                }
            }
            let f = Double(max(1, n))
            switch t {
            case 7: return Double(pale) / f >= 0.2                       // a peach is mostly pale pink
            case 8: return Double(bandOwn) / Double(max(1, band)) >= 0.8 // a pineapple is a solid yellow ring
            case 9: return Double(red) / f < 0.06                        // a melon has no red
            case 10: return Double(red) / f >= 0.06                      // a watermelon shows its red mouth
            default: return true
            }
        }
        var found: [(t: Int, x: Double, y: Double, sc: Double)] = []
        // biggest first, except apples before the peach: a red apple beside a peach would be read as part of it
        for t in [10, 9, 8, 5, 7, 6, 4, 3, 2, 1, 0] {
            let rr = SK.radius[t] / S, m = BoardReader.skMask[t]
            // a fruit can't stick out of the jar sideways or through the floor
            let iLo = Int(rr * 0.9), iHi = gw - Int(rr * 0.9), jHi = gh - Int(rr * 0.85)
            if iLo >= iHi || jHi <= 0 { continue }
            var cands: [(Double, Int, Int)] = []
            var j = 2
            while j < jHi {
                var i = iLo
                while i < iHi {
                    let k = j * gw + i
                    if !claimed[k] && grid[k] != 0 && m & (1 << UInt16(grid[k])) != 0 {
                        let sc = score(Double(i), Double(j), rr, m)
                        if sc.all >= 0.62 && sc.rim >= 0.5 { cands.append((sc.all, i, j)) }
                    }
                    i += 2
                }
                j += 2
            }
            cands.sort { $0.0 > $1.0 }
            for (_, i, j) in cands {
                if claimed[j * gw + i] { continue }
                // centre = middle of this colour inside the disc (faces and leaves are a different colour)
                var sxs = 0.0, sys = 0.0, cnt = 0.0
                let R = Int(rr * 1.05) + 1
                for y in max(0, j - R)...min(gh - 1, j + R) {
                    for x in max(0, i - R)...min(gw - 1, i + R) {
                        let dx = Double(x - i), dy = Double(y - j)
                        if dx * dx + dy * dy > rr * rr * 1.1 { continue }
                        let k = y * gw + x
                        if !claimed[k] && grid[k] != 0 && m & (1 << UInt16(grid[k])) != 0 { sxs += Double(x); sys += Double(y); cnt += 1 }
                    }
                }
                if cnt == 0 { continue }
                var ci = sxs / cnt, cj = sys / cnt
                // faces pull the middle of the colour off centre: nudge until the edge ring sits on the fruit
                var bx = ci, by = cj, bh = edge(ci, cj, rr, m)
                for dy in -8...8 { for dx in -8...8 {
                    let x = ci + Double(dx) * 0.5, y = cj + Double(dy) * 0.5
                    let h = edge(x, y, rr, m)
                    if h > bh || (h == bh && (x - ci) * (x - ci) + (y - cj) * (y - cj) < (bx - ci) * (bx - ci) + (by - cj) * (by - cj)) { bx = x; by = y; bh = h }
                } }
                ci = bx; cj = by
                let sc = score(ci, cj, rr, m)
                if sc.all < 0.6 || sc.rim < 0.45 { continue }
                if !lookAlikeOK(t, ci, cj, rr, m) { continue }
                var px = X0 + ci * S + S / 2, py = Y0 + cj * S + S / 2
                px = min(max(px, SK.left + SK.radius[t]), SK.right - SK.radius[t])
                py = min(py, SK.floor - SK.radius[t])
                // two fruits never overlap much
                if found.contains(where: { hypot($0.x - px, $0.y - py) < 0.7 * (SK.radius[$0.t] + SK.radius[t]) }) { continue }
                found.append((t, px, py, sc.all))
                let C = Int(rr + 2)
                for y in max(0, Int(cj) - C)...min(gh - 1, Int(cj) + C) {
                    for x in max(0, Int(ci) - C)...min(gw - 1, Int(ci) + C) {
                        let dx = Double(x) - ci, dy = Double(y) - cj
                        if dx * dx + dy * dy <= (rr + 1.5) * (rr + 1.5) { claimed[y * gw + x] = true }
                    }
                }
            }
        }
        // the fruit under Will: above the jar's dashed line, one of the five kinds that can be dropped
        var held = -1, heldX = 0.0
        if let h = found.filter({ $0.t <= 4 && $0.y > 850 && $0.y < 960 }).min(by: { $0.y < $1.y }) {
            held = h.t; heldX = h.x
            found.removeAll { $0.t == h.t && $0.x == h.x && $0.y == h.y }
        }
        let jar = found.map { SK.Fruit(t: $0.t, x: $0.x, y: $0.y) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let next = readNext(s)
        let cells = SK.encode(held: held, heldX: heldX, next: next, fruits: jar)
        return BoardMessage(valid: true, game: .suika, cells: cells, me: 1, myTurn: held >= 0)
    }

    /// Next fruit: the icon in the middle of the wheel at the top right. Only the five small kinds come next.
    private static func readNext(_ s: Sampler) -> Int {
        let sx = Double(s.w) / 1179, sy = Double(s.h) / 2556
        var votes = [Int](repeating: 0, count: 8)
        var total = 0, redV = 0.0, redN = 0.0
        var y = 485.0
        while y <= 545 {
            var x = 935.0
            while x <= 995 {
                if (x - 965) * (x - 965) + (y - 515) * (y - 515) <= 900 {
                    let p = s.get(Int(x * sx), Int(y * sy))
                    let g = Int(skGroup(p))
                    votes[g] += 1; total += 1
                    if g == 1 || g == 2 { redV += max(p.0, p.1, p.2); redN += 1 }
                }
                x += 3
            }
            y += 3
        }
        // the icons are drawn pinker than the fruits in the jar, so red and pink-red count together here
        let red = votes[1] + votes[2]
        let pick = [(red, 0), (votes[3], 2), (votes[4], 3), (votes[5], 4)].max { $0.0 < $1.0 }!
        if pick.0 < 25 { return -1 }
        if pick.1 != 0 { return pick.1 }
        // cherry has a yellow diamond beak; strawberry has pale seeds and a lighter skin
        let f = Double(max(1, total))
        if Double(votes[4]) / f >= 0.05 { return 0 }
        if Double(votes[6]) / f >= 0.1 { return 1 }
        return redN > 0 && redV / redN > 0.88 * 255 ? 1 : 0
    }
}
