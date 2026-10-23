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
        // Which game? Jackaroo has a green table under the board; the others differ in the top-left corner.
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

    // MARK: Plato 4 / 5 in a Row — board panel spans x 25…1150; 7×6 starts at y 836, 9×7 at y 881.
    // Themes change the board and the piece skins, so pieces are matched against the two player badges
    // at the top (left = opponent, right = you) instead of fixed colours. cells: 1 = yours, 2 = opponent's.
    private static var cCommitted: [[Double]] = []   // what each hole looked like on the last board we accepted
    private static var cLastFrame: [[Double]] = []
    private static var cOwner: [Int] = []             // 0 empty, 1 yours, 2 opponent's
    private static var cLastOwner = 0
    private static var cCertain = false               // false when we joined mid-game (owners guessed from badges)
    private static var cWasMyTurn = false
    private static var cKindSeen: GameKind? = nil
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
        let pill = s.avg(730 * sx, 398 * sy, 6 * sx)
        let myTurn = pill.2 > 200 && pill.2 - pill.0 > 120
        let N = cols * rows
        var patches: [[Double]] = []
        patches.reserveCapacity(N)
        for r in 0..<rows { for c in 0..<cols {
            patches.append(patch((25.5 + pitch * (Double(c) + 0.5)) * sx, (top + pitch * (Double(r) + 0.5)) * sy, pitch * 0.36 * sx))
        } }
        // fallback reading (used when we join mid-game or lose track): match each disc to the player badges
        func badgeRead() -> [Int] {
            let opp = patch(315 * sx, 310 * sy, 28 * sx), mine = patch(863 * sx, 310 * sy, 28 * sx)
            var out = [Int](repeating: 0, count: N)
            if dist(opp, mine) <= 20 { return out }
            for i in 0..<N {
                let dm = dist(patches[i], mine), dop = dist(patches[i], opp)
                if dm < 32 && dm < dop * 0.6 { out[i] = 1 } else if dop < 32 && dop < dm * 0.6 { out[i] = 2 }
            }
            // no floating pieces
            for c in 0..<cols { for r in stride(from: rows - 2, through: 0, by: -1) where out[(r + 1) * cols + c] == 0 { out[r * cols + c] = 0 } }
            return out
        }
        func resync() {
            let b = badgeRead()
            let nm = b.filter { $0 == 1 }.count, no = b.filter { $0 == 2 }.count
            cOwner = b
            cCertain = nm + no == 0          // an empty board is a fresh game: from here on we know every piece
            cLastOwner = nm > no ? 1 : (no > nm ? 2 : 0)
        }
        // whose piece is it? Not by looks (skins are endless) but by turn order: every turn adds exactly one
        // disc, and the player whose turn it was put it there.
        var motion = Double.infinity
        if cLastFrame.count == N { motion = 0; for i in 0..<N { motion = max(motion, dist(patches[i], cLastFrame[i])) } }
        cLastFrame = patches
        if cCommitted.count != N || cKindSeen != kind {
            cKindSeen = kind; cCommitted = patches; resync()
        } else if motion > 12 {
            // a disc is still falling (or something passes over the board): wait for a still picture
            return BoardMessage(valid: true, game: kind, cells: cOwner, me: cCertain ? 1 : 3, myTurn: false)
        } else {
            var changed: [Int] = []
            for i in 0..<N where dist(patches[i], cCommitted[i]) > 25 { changed.append(i) }
            if !changed.isEmpty {
                let drops = changed.filter { i in cOwner[i] == 0 && (i / cols == rows - 1 || cOwner[i + cols] != 0) }
                if changed.count <= 2 && drops.count == 1 {
                    let owner = cLastOwner != 0 ? 3 - cLastOwner : (cWasMyTurn ? 1 : 2)
                    cOwner[drops[0]] = owner; cLastOwner = owner
                    for i in changed { cCommitted[i] = patches[i] }
                } else if changed.count >= 3 || drops.count > 1 {
                    // new game, a pop-up over the board, or we missed moves: start over from what we can see
                    cCommitted = patches; resync()
                } else {
                    for i in changed { cCommitted[i] = patches[i] }   // a highlight ring fading etc.
                }
            }
        }
        cWasMyTurn = myTurn
        return BoardMessage(valid: true, game: kind, cells: cOwner, me: cCertain ? 1 : 3, myTurn: myTurn)
    }
}
