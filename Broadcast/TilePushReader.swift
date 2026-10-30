import Foundation

/// WePlay Tile Push (4×4): your map at the bottom, the opponent's at the top, the tile to place in the middle.
/// Calibrated on Atom's 1180×2556 recording (30 Oct). Cells (TP layout): 0 face down, 1 not yours (food…),
/// 2 the blue cat (joker), 3… your faces, numbered in the order first seen (only "same or not" matters).
extension BoardReader {
    static let tpCols: [Double] = [417, 570, 722, 874]
    static let tpRows: [Double] = [1608, 1779, 1950, 2120]
    static let tpOppCols: [Double] = [306, 459, 612, 764]
    static let tpOppRows: [Double] = [417, 588, 759, 930]
    static let tpCentre = (x: 591.0, y: 1258.0)

    private static func tpSand(_ p: (Double, Double, Double)) -> Bool {
        p.0 > 230 && p.1 > 185 && p.1 < 228 && p.2 > 110 && p.2 < 175
    }

    /// One tile: kind and, for a face, a 6×6 colour picture to tell the faces apart.
    /// kind: 0 face down, 1 other picture, 2 joker, 3 one of your faces, -1 not a resting tile (moving / covered)
    static func tpTile(_ s: Sampler, _ x: Double, _ y: Double) -> (kind: Int, sig: [Double]) {
        let sx = Double(s.w) / 1180, sy = Double(s.h) / 2556
        var n = 0.0, orange = 0.0, white = 0.0, blue = 0.0, emo = 0.0, ne = 0.0, ex = 0.0, ey = 0.0
        var dy = -54.0
        while dy <= 54 {
            var dx = -54.0
            while dx <= 54 {
                let p = s.get(Int((x + dx) * sx), Int((y + dy) * sy))
                let r = p.0, g = p.1, b = p.2
                n += 1
                if r > 200 && r - g > 70 && b < 120 { orange += 1 }
                if r > 225 && g > 225 && b > 220 { white += 1 }
                if b > 180 && b - r > 80 { blue += 1 }
                if abs(dx) <= 42 && abs(dy) <= 42 {
                    ne += 1
                    if r > 225 && g > 185 && g < 228 && b < 100 { emo += 1; ex += dx; ey += dy }   // emoji yellow (cheese is darker: g ≈ 179)
                }
                dx += 3
            }
            dy += 3
        }
        orange /= n; white /= n; blue /= n
        let emoN = emo; emo /= max(1, ne)
        if orange > 0.6 { return (0, []) }
        if white < 0.15 { return (-1, []) }
        if blue > 0.12 { return (2, []) }
        guard emo > 0.35 else { return (1, []) }
        // the picture is taken around the yellow face's middle, so a few px off in the tile position don't matter
        let fx = x + ex / emoN, fy = y + ey / emoN
        var sig: [Double] = []
        for j in 0..<6 { for i in 0..<6 {
            var r = 0.0, g = 0.0, b = 0.0
            for v in 0..<4 { for u in 0..<4 {
                let p = s.get(Int((fx - 48 + Double(i * 16 + u * 4 + 2)) * sx), Int((fy - 48 + Double(j * 16 + v * 4 + 2)) * sy))
                r += p.0; g += p.1; b += p.2
            } }
            sig += [r / 16, g / 16, b / 16]
        } }
        return (3, sig)
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
        var pts: [(Double, Double)] = []
        for y in tpRows { for x in tpCols { pts.append((x, y)) } }
        for y in tpOppRows { for x in tpOppCols { pts.append((x, y)) } }
        pts.append(tpCentre)
        var cells: [Int] = []
        var faces: [[Double]] = []
        for (k, p) in pts.enumerated() {
            let t = tpTile(s, p.0, p.1)
            if t.kind < 0 {
                if k < 16 { return bad }        // your map mid-animation
                cells.append(1); continue   // the tile in flight: nothing to place yet
            }
            if t.kind < 3 { cells.append(t.kind); continue }
            // same face = same picture (measured: same kind ≤ 12 apart — the top map is drawn a little differently — different kinds ≥ 20)
            var id = -1
            for (i, f) in faces.enumerated() {
                var d = 0.0
                for q in 0..<f.count { d += abs(f[q] - t.sig[q]) }
                if d / Double(f.count) < 16 { id = i; break }
            }
            if id < 0 { faces.append(t.sig); id = faces.count - 1 }
            cells.append(min(13, 3 + id))
        }
        // a hand tile that is yours means it's your move (the opponent is handed food)
        let hand = cells[32]
        return BoardMessage(valid: true, game: .tilePush, cells: cells, me: 1, myTurn: hand == 2 || hand >= 3)
    }
}
