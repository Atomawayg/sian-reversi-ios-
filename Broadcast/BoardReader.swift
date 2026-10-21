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

        return BoardMessage(valid: valid, cells: cells, me: me, myTurn: valid && glow > 0)
    }
}
