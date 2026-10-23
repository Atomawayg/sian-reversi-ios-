import CoreVideo
import Foundation

/// Reads the WePlay Reversi board from a screen frame.
/// Positions are fractions calibrated on 1179×2556 iPhone screenshots:
/// grid top-left (159, 933), cell 107.5 px; score tiles at y 664–742.
enum BoardReader {
    struct Sampler {
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

    /// YCbCr → RGB coefficients for the frame's colour matrix (BT.709 unless tagged 601).
    private static func matrix(_ pb: CVPixelBuffer) -> (rv: Double, gu: Double, gv: Double, bu: Double) {
        let bt709 = (rv: 1.5748, gu: 0.1873, gv: 0.4681, bu: 1.8556)
        let bt601 = (rv: 1.402, gu: 0.344136, gv: 0.714136, bu: 1.772)
        guard let m = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, nil) as? String else { return bt709 }
        return m == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) ? bt601 : bt709
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
            // Use the matrix the frame is tagged with. Screen recordings are BT.709; decoding them as
            // BT.601 (the old code) shifts reds and purples enough to turn highlights into pieces.
            let K = matrix(pb)
            sampler = Sampler(w: w, h: h) { x, y in
                var Y = Double(yp[y * ybpr + x])
                let ci = (y / 2) * cbpr + (x / 2) * 2
                var U = Double(cp[ci]) - 128, V = Double(cp[ci + 1]) - 128
                if !full { Y = (Y - 16) * 1.164; U *= 1.138; V *= 1.138 }
                let r = Y + K.rv * V, g = Y - K.gu * U - K.gv * V, b = Y + K.bu * U
                return (min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
            }
        }
        guard let s = sampler else { return nil }
        let W = Double(s.w), H = Double(s.h)
        // Portrait only. A landscape frame is not the game screen we expect.
        if W > H { return BoardMessage(valid: false, cells: [], me: 0, myTurn: false) }
        // Which game? Pool first (its city background would otherwise look like Plato's dark corner).
        if PoolReader.looksLikePool(s) { return PoolReader.read(s) }
        // Jackaroo has a green table under the board; the others differ in the top-left corner.
        let jg = s.avg(W * 590 / 1180, H * 1650 / 2556, W * 6 / 1180)
        if jg.1 > jg.0 + 60 && jg.1 > jg.2 + 20 { return readJackaroo(s) }
        let tl = s.avg(W * 40 / 1179, H * 400 / 2556, W * 5 / 1179)
        let tlL = (tl.0 + tl.1 + tl.2) / 3
        if tl.0 > 160 && tl.0 - tl.1 > 50 { return readCheckers(s) }
        // Plato's bottom bar (yellow ITEMS star + green chat icon) looks the same in every board theme
        let star = s.avg(W * 55 / 1179, H * 2133 / 2556, W * 4 / 1179), chat = s.avg(W * 85 / 1179, H * 2380 / 2556, W * 4 / 1179)
        let platoUI = star.0 > 225 && star.1 > 140 && star.1 < 220 && star.2 < 70 && chat.1 > chat.0 + 25 && chat.1 > chat.2 + 60
        if platoUI || (tl.2 > tl.0 + 8 && tlL < 70) { return readConnect(s) }
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
        var pieces = 0, lightOK = 0, unsure = 0
        for r in 0..<8 { for c in 0..<8 {
            let x0 = 52 + 135 * Double(c), y0 = 773 + 134.5 * Double(r)
            if (r + c) & 1 == 0 {
                let p = s.avg((x0 + 67) * sx, (y0 + 62) * sy, 20 * sx)
                if (p.0 + p.1 + p.2) / 3 > 170 { lightOK += 1 }
                continue
            }
            // A real piece is a 3D disc: the band under its face is its dark side wall. The last-move
            // highlight is a flat bright square and a captured piece fades out bright, so neither has one.
            // Measured on real frames: pieces 56–113 dark samples of 128, highlights/ghosts/empties ≤ 3.
            var red = 0, pur = 0, dark = 0, gold = 0
            var dy = 92.0
            while dy <= 120 {
                var dx = 30.0
                while dx <= 105 {
                    let q = s.get(Int((x0 + dx) * sx), Int((y0 + dy) * sy))
                    let L = (q.0 + q.1 + q.2) / 3
                    if L < 130 { dark += 1 }
                    if L < 150 && q.0 - q.1 > 50 { red += 1 }
                    if L < 150 && q.2 > q.0 + 5 { pur += 1 }
                    dx += 5
                }
                dy += 4
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
            if dark >= 30 {
                if red >= 25 && red > 3 * pur { v = 1 } else if pur >= 25 && pur > 3 * red { v = 2 } else { unsure += 1 }
            }
            if v != 0 && gold >= 20 { v += 2 }   // 3 red king, 4 purple king (crowns score ≥ 76, others 0)
            if v != 0 { pieces += 1 }
            cells[r * 8 + c] = v
        } }
        let valid = pieces >= 2 && lightOK >= 24 && unsure == 0   // something disc-shaped we can't name: mid-animation
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

    // MARK: Plato 4 / 5 in a Row — board panel spans x 25…1150; 7×6 starts at y 836, 9×7 at y 881.
    // Themes change the board and the piece skins, so pieces are matched against the two player badges
    // at the top (left = opponent, right = you) instead of fixed colours. cells: 1 = yours, 2 = opponent's.
    private static var cLastPieces = 0
    private static var cDropSince = 0.0
    private static var cLastKind: GameKind? = nil

    private static func readConnect(_ s: Sampler) -> BoardMessage {
        let W = Double(s.w), H = Double(s.h)
        let sx = W / 1179, sy = H / 2556
        let bad = BoardMessage(valid: false, cells: [], me: 0, myTurn: false)
        func gray(_ x: Int, _ y: Int) -> Double { let p = s.get(x, y); return (p.0 + p.1 + p.2) / 3 }
        // which board: the holes repeat every 125 px (5 in a row) or 161 px (4 in a row)
        let x0 = Int(25 * sx), x1 = min(s.w - 1, Int(1150 * sx))
        let n = x1 - x0
        guard n > 400 else { return bad }
        let L5 = Int((124.9 * sx).rounded()), L4 = Int((160.6 * sx).rounded())
        var c5 = 0.0, c4 = 0.0, rowsUsed = 0
        var y = 900.0
        while y < 1750 {
            let yy = Int(y * sy)
            var prof = [Double](repeating: 0, count: n)
            for i in 0..<n { prof[i] = gray(x0 + i, yy) }
            var pre = [Double](repeating: 0, count: n + 1)
            for i in 0..<n { pre[i + 1] = pre[i] + prof[i] }
            let h = 15
            var g = [Double](repeating: 0, count: n)
            for i in 0..<n { let a = max(0, i - h), b = min(n, i + h + 1); g[i] = prof[i] - (pre[b] - pre[a]) / Double(b - a) }
            func corr(_ lag: Int) -> Double {
                let m = n - lag
                if m < 50 { return 0 }
                var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0
                for i in 0..<m { let a = g[i], b = g[i + lag]; sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b }
                let mm = Double(m)
                let cov = sab / mm - sa / mm * sb / mm
                let va = saa / mm - (sa / mm) * (sa / mm), vb = sbb / mm - (sb / mm) * (sb / mm)
                return va > 1e-6 && vb > 1e-6 ? cov / sqrt(va * vb) : 0
            }
            c5 += corr(L5); c4 += corr(L4); rowsUsed += 1
            y += 35
        }
        c5 /= Double(max(1, rowsUsed)); c4 /= Double(max(1, rowsUsed))
        // pieces make the pattern less regular, so only ask for a clear winner (and remember the last answer)
        var kind: GameKind
        if max(c5, c4) > 0.15 && abs(c5 - c4) > 0.12 { kind = c5 > c4 ? .connect5 : .connect4; cLastKind = kind }
        else if let k = cLastKind { kind = k }
        else { return bad }
        let pitch = kind == .connect5 ? 124.9 : 160.6, top = kind == .connect5 ? 881.0 : 836.0
        let (cols, rows) = kind.size

        // a small picture of a disc: 9×9 points inside the circle
        func patch(_ cx: Double, _ cy: Double, _ R: Double) -> [Double] {
            var out: [Double] = []
            for j in 0..<9 { for i in 0..<9 {
                let u = Double(i - 4) / 4, v = Double(j - 4) / 4
                if u * u + v * v > 1 { continue }
                let p = s.avg(cx + u * R * 0.75, cy + v * R * 0.75, max(1, 1.5 * sx))
                out += [p.0, p.1, p.2]
            } }
            return out
        }
        func dist(_ a: [Double], _ b: [Double]) -> Double {
            var t = 0.0; for i in 0..<min(a.count, b.count) { t += abs(a[i] - b[i]) }; return t / Double(max(1, a.count))
        }
        let opp = patch(315 * sx, 310 * sy, 28 * sx), mine = patch(863 * sx, 310 * sy, 28 * sx)
        guard dist(opp, mine) > 20 else { return bad }   // badges hidden (banner) or identical
        var cells = [Int](repeating: 0, count: cols * rows)
        var nMine = 0, nOpp = 0
        // First pass: brightness and texture of every hole. Then a hole holds a piece only if it is textured
        // AND clearly brighter/darker than a typical hole on this board. Measured: flat theme holes spread 0,
        // dark gold theme holes show the background through (spread up to 16, mean 1–10); pieces spread ≥ 24
        // and differ from the typical hole by ≥ 54.
        var patches: [[Double]] = [], means: [Double] = [], spreads: [Double] = []
        for r in 0..<rows { for c in 0..<cols {
            let P = patch((25.5 + pitch * (Double(c) + 0.5)) * sx, (top + pitch * (Double(r) + 0.5)) * sy, pitch * 0.36 * sx)
            var sum = 0.0, sq = 0.0, n = 0.0
            var i = 0
            while i + 2 < P.count { let L = (P[i] + P[i + 1] + P[i + 2]) / 3; sum += L; sq += L * L; n += 1; i += 3 }
            let mean = sum / max(1, n)
            patches.append(P); means.append(mean); spreads.append((max(0, sq / max(1, n) - mean * mean)).squareRoot())
        } }
        // the typical empty hole: median brightness of the low-texture holes (a full board has few of them)
        let flat = (0..<means.count).filter { spreads[$0] <= 20 }.map { means[$0] }.sorted()
        let typical: Double? = flat.isEmpty ? nil : flat[flat.count / 2]
        for k in 0..<patches.count {
            var v = 0
            if spreads[k] > 20 && (typical.map { abs(means[k] - $0) > 30 } ?? true) {
                let dm = dist(patches[k], mine), dop = dist(patches[k], opp)
                if min(dm, dop) > max(dm, dop) * 0.8 { return bad }   // looks like neither badge: mid-animation
                if dm < dop { v = 1; nMine += 1 } else { v = 2; nOpp += 1 }
            }
            cells[k] = v
        }
        // sanity: pieces sit on top of each other (no floating ones), counts differ by at most one
        for c in 0..<cols { for r in 0..<(rows - 1) where cells[r * cols + c] != 0 && cells[(r + 1) * cols + c] == 0 { return bad } }
        if abs(nMine - nOpp) > 1 { return bad }
        // pieces never disappear mid-game: a sudden drop is a covered or fading frame, unless it lasts (new game)
        let total = nMine + nOpp
        let now = Date().timeIntervalSince1970
        if total < cLastPieces && cLastPieces >= 2 {
            if cDropSince == 0 { cDropSince = now }
            if now - cDropSince < 3 { return bad }
        }
        cDropSince = 0; cLastPieces = total
        let pill = s.avg(730 * sx, 398 * sy, 6 * sx)
        let myTurn = pill.2 > 200 && pill.2 - pill.0 > 120
        return BoardMessage(valid: true, game: kind, cells: cells, me: 1, myTurn: myTurn)
    }
}
