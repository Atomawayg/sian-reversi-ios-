import CoreVideo
import Foundation

/// Reads the WePlay Reversi board from a screen frame.
/// Positions are fractions calibrated on 1179×2556 iPhone screenshots:
/// grid top-left (159, 933), cell 107.5 px; score tiles at y 664–742.
enum BoardReader {
    private struct Sampler {
        let w: Int, h: Int
        let get: (Int, Int) -> (Double, Double, Double)
        func avg(_ cx: Double, _ cy: Double, _ rad: Double) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            let x0 = max(0, Int(cx - rad)), x1 = min(w - 1, Int(cx + rad))
            let y0 = max(0, Int(cy - rad)), y1 = min(h - 1, Int(cy + rad))
            let step = max(1, Int(rad / 4))
            var y = y0
            while y <= y1 {
                var x = x0
                while x <= x1 { let p = get(x, y); r += p.0; g += p.1; b += p.2; n += 1; x += step }
                y += step
            }
            return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
        }
    }

    static func read(_ pb: CVPixelBuffer) -> BoardMessage? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let fmt = CVPixelBufferGetPixelFormatType(pb)
        var sampler: Sampler?

        if fmt == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let p = base.assumingMemoryBound(to: UInt8.self)
            sampler = Sampler(w: w, h: h) { x, y in
                let i = y * bpr + x * 4
                return (Double(p[i + 2]), Double(p[i + 1]), Double(p[i]))
            }
        } else if fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let yb = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let cb = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }
            let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
            let ybpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cbpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            let yp = yb.assumingMemoryBound(to: UInt8.self), cp = cb.assumingMemoryBound(to: UInt8.self)
            let full = fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            sampler = Sampler(w: w, h: h) { x, y in
                var Y = Double(yp[y * ybpr + x])
                let ci = (y / 2) * cbpr + (x / 2) * 2
                var U = Double(cp[ci]) - 128, V = Double(cp[ci + 1]) - 128
                if !full { Y = (Y - 16) * 1.164; U *= 1.138; V *= 1.138 }
                let r = Y + 1.402 * V, g = Y - 0.344136 * U - 0.714136 * V, b = Y + 1.772 * U
                return (min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
            }
        }
        guard let s = sampler else { return nil }
        let W = Double(s.w), H = Double(s.h)
        // Portrait only. A landscape frame is not the game screen we expect.
        if W > H { return BoardMessage(valid: false, cells: [], me: 0, myTurn: false) }
        // Which game? The background in the top-left corner tells them apart.
        let tl = s.avg(W * 40 / 1179, H * 400 / 2556, W * 5 / 1179)
        let tlL = (tl.0 + tl.1 + tl.2) / 3
        if tl.0 > 160 && tl.0 - tl.1 > 50 { return readCheckers(s) }
        if tl.2 > tl.0 + 8 && tlL < 70 { return readConnect(s) }
        return readReversi(s)
    }

    // MARK: WePlay Reversi
    private static func readReversi(_ s: Sampler) -> BoardMessage {
        let W = Double(s.w), H = Double(s.h)
        let cw = W * 107.5 / 1179
        let gx = W * 159 / 1179, gy = H * 933 / 2556
        var cells = [Int](repeating: 0, count: 64)
        var nb = 0, nw = 0, glow = 0, nonBoard = 0
        for r in 0..<8 { for c in 0..<8 {
            let cx = gx + cw * (Double(c) + 0.5), cy = gy + cw * (Double(r) + 0.5)
            let p = s.avg(cx, cy, cw * 0.2)
            let L = (p.0 + p.1 + p.2) / 3, br = p.2 - p.0
            var v: Int
            if br > 4 { v = L > 140 ? 2 : 1 } else { v = L < 95 ? 3 : 0 }
            if v == 0 {
                // legal-move highlight: yellow glow along the inside of the cell edges
                var yr = 0.0, yg = 0.0, yb = 0.0
                for (fx, fy) in [(0.5, 0.1), (0.5, 0.9), (0.1, 0.5), (0.9, 0.5)] {
                    let q = s.avg(gx + cw * (Double(c) + fx), gy + cw * (Double(r) + fy), cw * 0.03)
                    yr += q.0; yg += q.1; yb += q.2
                }
                yr /= 4; yg /= 4; yb /= 4
                if (yr + yg) / 2 - yb > 60 && yr > 170 { glow += 1 }
                if L < 60 || L > 245 { nonBoard += 1 }
            }
            if v == 1 { nb += 1 } else if v == 2 { nw += 1 }
            cells[r * 8 + c] = v
        } }
        // sanity: a real board has both colours and mostly board-coloured empties
        let valid = nb >= 1 && nw >= 1 && nb + nw >= 4 && nonBoard < 6

        func lum(_ x: Double, _ y: Double) -> Double {
            let p = s.avg(W * x / 1179, H * y / 2556, W * 5 / 1179); return (p.0 + p.1 + p.2) / 3
        }
        func strip(_ x: Double) -> Double { var t = 0.0; for y in stride(from: 669.0, through: 737.0, by: 12) { t += lum(x, y) }; return t / 6 }
        let tl = strip(307), tr = strip(792)
        var me = 0
        if abs(tr - tl) > 60 { me = tr > tl ? 2 : 1 }

        return BoardMessage(valid: valid, game: .reversi, cells: cells, me: me, myTurn: valid && glow > 0)
    }

    // MARK: WePlay หมากฮอส — board x 52…1132, y 773…1849 on a 1179×2556 screen; you are always at the bottom
    private static func readCheckers(_ s: Sampler) -> BoardMessage {
        let W = Double(s.w), H = Double(s.h)
        let sx = W / 1179, sy = H / 2556
        var cells = [Int](repeating: 0, count: 64)
        var pieces = 0, lightOK = 0
        for r in 0..<8 { for c in 0..<8 {
            let x0 = 52 + 135 * Double(c), y0 = 773 + 134.5 * Double(r)
            if (r + c) & 1 == 0 {
                let p = s.avg((x0 + 67) * sx, (y0 + 62) * sy, 20 * sx)
                if (p.0 + p.1 + p.2) / 3 > 170 { lightOK += 1 }
                continue
            }
            // piece colour from the lower part of the square (a king's crown covers the top)
            var red = 0, pur = 0, gold = 0
            var dy = 80.0
            while dy <= 120 {
                var dx = 30.0
                while dx <= 105 {
                    let q = s.get(Int((x0 + dx) * sx), Int((y0 + dy) * sy))
                    let L = (q.0 + q.1 + q.2) / 3
                    if q.2 > q.0 + 5 && L < 170 { pur += 1 }
                    else if q.0 - q.1 > 60 && q.0 < 240 && q.1 < 150 { red += 1 }
                    dx += 6
                }
                dy += 6
            }
            // crown: gold pixels in the upper part of the square
            dy = -35
            while dy <= 50 {
                var dx = 25.0
                while dx <= 110 {
                    let y = Int((y0 + dy) * sy), x = Int((x0 + dx) * sx)
                    if y >= 0 && y < s.h {
                        let q = s.get(x, y)
                        if q.0 > 180 && q.1 > 140 && q.2 < 110 { gold += 1 }
                    }
                    dx += 6
                }
                dy += 6
            }
            var v = 0
            if red >= 12 && red > pur { v = 1 } else if pur >= 12 { v = 2 }
            if v != 0 && gold >= 6 { v += 2 }   // 3 red king, 4 purple king
            if v != 0 { pieces += 1 }
            cells[r * 8 + c] = v
        } }
        let valid = pieces >= 2 && lightOK >= 24
        // your colour: the small disc badge on your avatar (top-left)
        let bd = s.avg(262 * sx, 609 * sy, 5 * sx)
        let me = bd.0 - bd.1 > 60 ? 1 : (bd.2 > bd.0 ? 2 : 0)
        // your turn: the yellow countdown ring around your avatar
        var yellow = 0
        for k in 0..<24 {
            let ang = Double(k) * Double.pi / 12
            let q = s.avg((188 + 97 * cos(ang)) * sx, (530 + 97 * sin(ang)) * sy, 2 * sx)
            if (q.0 + q.1) / 2 - q.2 > 60 { yellow += 1 }
        }
        return BoardMessage(valid: valid, game: .checkers, cells: cells, me: me, myTurn: valid && yellow >= 2)
    }

    // MARK: Plato 4 / 5 in a Row — board panel spans x 25…1150; 7×6 starts at y 836, 9×7 at y 881
    private static func readConnect(_ s: Sampler) -> BoardMessage {
        let W = Double(s.w), H = Double(s.h)
        let sx = W / 1179, sy = H / 2556
        func lum(_ x: Double, _ y: Double) -> Double { let p = s.avg(x * sx, y * sy, 3 * sx); return (p.0 + p.1 + p.2) / 3 }
        var kind: GameKind
        var pitch: Double, top: Double
        if lum(30, 850) > 52 { kind = .connect4; pitch = 160.6; top = 836 }
        else if lum(30, 900) > 52 { kind = .connect5; pitch = 124.9; top = 881 }
        else { return BoardMessage(valid: false, cells: [], me: 0, myTurn: false) }
        let (cols, rows) = kind.size
        var cells = [Int](repeating: 0, count: cols * rows)
        for r in 0..<rows { for c in 0..<cols {
            let p = s.avg((25.5 + pitch * (Double(c) + 0.5)) * sx, (top + pitch * (Double(r) + 0.5)) * sy, pitch * 0.15 * sx)
            let L = (p.0 + p.1 + p.2) / 3
            var v = 0
            if L > 70 {
                if p.0 - p.1 > 100 { v = 1 }                    // red
                else if p.1 > 120 && p.0 > 170 { v = 2 }        // yellow
            }
            cells[r * cols + c] = v
        } }
        // your colour: the coin next to your avatar (top-right); your turn: the blue "Your Turn" pill
        let coin = s.avg(863 * sx, 312 * sy, 6 * sx)
        let me = coin.0 - coin.1 > 100 ? 1 : ((coin.1 > 120 && coin.0 > 170) ? 2 : 0)
        let pill = s.avg(730 * sx, 398 * sy, 6 * sx)
        let myTurn = pill.2 > 200 && pill.2 - pill.0 > 120
        return BoardMessage(valid: true, game: kind, cells: cells, me: me, myTurn: myTurn)
    }
}
