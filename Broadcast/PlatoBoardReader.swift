import Foundation

/// Plato chess and Plato checkers (same wooden 8×8 board). Coordinates of a 1180-wide screen:
/// board left edge x 34.5, square 138.7 px, top edge found per frame (chess ≈ 721, checkers ≈ 745).
/// You are always at the bottom. Your turn: the blue "Your Turn" pill under your avatar.
enum PlatoBoardReader {
    static let X0 = 34.5, CELL = 138.7

    /// Wooden frame on both sides of the board.
    static func looksLikeBoard(_ s: BoardReader.Sampler) -> Bool {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        func wood(_ p: (Double, Double, Double)) -> Bool { p.0 > 195 && p.0 < 245 && p.1 > 155 && p.1 < 205 && p.2 > 90 && p.2 < 150 && p.0 - p.2 > 75 }
        return wood(s.avg(12 * sx, 1300 * sy, 3 * sx)) && wood(s.avg(1165 * sx, 1300 * sy, 3 * sx))
    }

    static func read(_ s: BoardReader.Sampler) -> BoardMessage? {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        @inline(__always) func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            s.get(min(s.w - 1, max(0, Int(Double(x) * sx))), min(s.h - 1, max(0, Int(Double(y) * sy))))
        }
        func lum(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Double {
            var t = 0.0
            for yy in y..<(y + h) { for xx in x..<(x + w) { let p = px(xx, yy); t += p.0 + p.1 + p.2 } }
            return t / Double(3 * w * h)
        }
        // board top edge: strongest light/dark flips across the square edges
        var bestY = 721, bestS = -1.0
        for y0 in stride(from: 690, through: 780, by: 1) {
            var sc = 0.0
            for r in 1..<8 {
                let y = Int((Double(y0) + Double(r) * CELL).rounded())
                for c in 0..<8 {
                    let x = Int(X0 + Double(c) * CELL + 12)
                    sc += abs(lum(x, y - 8, 6, 5) - lum(x, y + 3, 6, 5))
                }
            }
            if sc > bestS { bestS = sc; bestY = y0 }
        }
        let y0 = Double(bestY)
        // turn pill
        let pill = s.avg(745 * sx, 418 * sy, 4 * sx)
        let myTurn = pill.2 > 200 && pill.0 < 90 && pill.1 > 95 && pill.1 < 170

        // checkers discs on the dark squares
        var disc = [Int](repeating: 0, count: 64)
        var reds = 0, creams = 0
        for r in 0..<8 { for c in 0..<8 where (r + c) % 2 == 1 {
            let cx = Int(X0 + Double(c) * CELL + CELL / 2), cy = Int(y0 + Double(r) * CELL + CELL / 2)
            var red = 0, cream = 0, n = 0
            for yy in stride(from: cy - 35, to: cy + 35, by: 2) { for xx in stride(from: cx - 35, to: cx + 35, by: 2) {
                let p = px(xx, yy); n += 1
                if p.0 > 110 && p.1 < 60 && p.2 < 60 && abs(p.1 - p.2) < 25 { red += 1 }   // red disc (G ≈ B ≈ 28); dark wood has G ≈ 80 > B
                if p.0 > 195 && p.0 < 245 && p.1 > 175 && p.1 < 230 && p.2 > 140 && p.2 < 200 { cream += 1 }
            } }
            var v = 0
            if Double(red) > 0.25 * Double(n) { v = 1 } else if Double(cream) > 0.4 * Double(n) { v = 2 }
            if v != 0 {
                var odd = 0, m = 0
                for yy in stride(from: cy - 24, to: cy + 24, by: 2) { for xx in stride(from: cx - 24, to: cx + 24, by: 2) {
                    let p = px(xx, yy); m += 1
                    if v == 1 ? (p.0 > 200 && p.1 > 170 && p.2 > 150) : (p.0 - p.1 > 60) { odd += 1 }
                } }
                if Double(odd) > 0.06 * Double(m) { v += 2 }
                if v == 1 || v == 3 { reds += 1 } else { creams += 1 }
            }
            disc[r * 8 + c] = v
        } }

        // chess pieces
        var chess = [Int](repeating: 0, count: 64)
        var wk = 0, bk = 0, pieces = 0
        for r in 0..<8 { for c in 0..<8 {
            let v = chessCell(px, Int(X0 + Double(c) * CELL), Int(y0 + Double(r) * CELL))
            chess[r * 8 + c] = v
            if v != 0 { pieces += 1 }
            if v == 6 { wk += 1 } else if v == 12 { bk += 1 }
        } }
        if wk == 1 && bk == 1 && reds < 2 {
            // your colour: the knight icon next to your avatar is white or black
            var hi = 0, n = 0
            for yy in stride(from: 285, to: 335, by: 2) { for xx in stride(from: 630, to: 680, by: 2) {
                let p = px(xx, yy); n += 1
                if (p.0 + p.1 + p.2) / 3 > 170 { hi += 1 }
            } }
            let meWhite = Double(hi) > 0.08 * Double(n)
            return BoardMessage(valid: true, game: .chess, cells: chess, me: meWhite ? 1 : 2, myTurn: myTurn)
        }
        if reds + creams >= 2 {
            return BoardMessage(valid: true, game: .draughts, cells: disc, me: 0, myTurn: myTurn)
        }
        return nil
    }

    /// 0 empty, 1…6 white P N B R Q K, 7…12 black.
    static func chessCell(_ px: (Int, Int) -> (Double, Double, Double), _ x: Int, _ y: Int) -> Int {
        let x0 = x + 6, y0 = y + 6, w = Int(CELL) - 12, h = Int(CELL) - 12
        // background: median of the corner pixels
        var rs: [Double] = [], gs: [Double] = [], bs: [Double] = []
        for (cx, cy) in [(x0, y0), (x0 + w - 8, y0), (x0, y0 + h - 8), (x0 + w - 8, y0 + h - 8)] {
            for yy in cy..<(cy + 8) { for xx in cx..<(cx + 8) { let p = px(xx, yy); rs.append(p.0); gs.append(p.1); bs.append(p.2) } }
        }
        rs.sort(); gs.sort(); bs.sort()
        let br = rs[rs.count / 2], bg = gs[gs.count / 2], bb = bs[bs.count / 2]
        let G = 24
        var M = [Float](repeating: 0, count: G * G)
        var fgSum = 0.0, fgN = 0.0
        for i in 0..<G {
            let ya = y0 + i * h / G, yb = y0 + (i + 1) * h / G
            for j in 0..<G {
                let xa = x0 + j * w / G, xb = x0 + (j + 1) * w / G
                var f = 0, n = 0
                for yy in ya..<yb { for xx in xa..<xb {
                    let p = px(xx, yy); n += 1
                    if abs(p.0 - br) + abs(p.1 - bg) + abs(p.2 - bb) > 60 { f += 1; fgSum += (p.0 + p.1 + p.2) / 3; fgN += 1 }
                } }
                M[i * G + j] = Float(f) / Float(max(1, n))
            }
        }
        var centre: Float = 0
        for i in 6..<18 { for j in 6..<18 { centre += M[i * G + j] } }
        if centre / 144 < 0.35 { return 0 }
        let S = PlatoChessData.shapes
        var best = 0; var bd = Float.greatestFiniteMagnitude
        for t in 0..<6 {
            var d: Float = 0
            for k in 0..<(G * G) { d += abs(M[k] - S[t * G * G + k]) }
            if d < bd { bd = d; best = t }
        }
        let white = fgN > 0 && fgSum / fgN > 128
        return best + 1 + (white ? 0 : 6)
    }
}
