import Foundation

/// HosBase (hosbase.com in Safari): Thai checkers on a wooden 8×8 board under the site's orange title bar.
/// Measured on Atom's screen recording 27 Oct 20:07 (1180×2556): bar y 357–416, board wood x 6…1176,
/// y 984…, grid inset 10 px, square 144 px. Pieces sit on the dark squares: red men, silver men, and kings
/// are the piece turned over (a flat face with no ring). The page can scroll, so the board is found per frame.
/// Cells: 1 red, 2 silver, 3 red king, 4 silver king. You play from the bottom.
enum HosBaseReader {
    private static let lock = NSLock()
    private static var last: [Int] = [], same = 0
    private static var stable: [Int] = [], sent: BoardMessage? = nil
    private static var me = 2, meSure = false, myTurn = true

    private static func orange(_ p: (Double, Double, Double)) -> Bool { p.0 > 170 && p.1 > 90 && p.1 < 160 && p.2 < 95 }
    private static func wood(_ p: (Double, Double, Double)) -> Bool { p.0 - p.2 > 40 && p.0 > 110 }

    /// y of the bottom of the orange title bar, or nil
    static func barBottom(_ s: BoardReader.Sampler) -> Int? {
        let W = s.w, H = s.h
        func frac(_ y: Int, _ f: ((Double, Double, Double)) -> Bool) -> Double {
            var n = 0
            for k in 0..<40 { if f(s.get(W * (2 * k + 1) / 80, y)) { n += 1 } }
            return Double(n) / 40
        }
        var y = H / 20, found = -1
        while y < H * 2 / 5 {
            if frac(y, orange) >= 0.8 { found = y } else if found >= 0 { return found }
            y += 2
        }
        return nil
    }

    static func looksLikeHosBase(_ s: BoardReader.Sampler) -> Bool { barBottom(s) != nil }

    static func read(_ s: BoardReader.Sampler) -> BoardMessage? {
        guard let bar = barBottom(s) else { return nil }
        let W = s.w, H = s.h
        // the board's sides: wood across a row a little below the middle of the screen; its top: going up the
        // first column from there until the wood stops (the white page above the board)
        let ry = H * 55 / 100
        var x0 = 0, x1 = W - 1
        while x0 < W / 4 && !wood(s.get(x0, ry)) { x0 += 1 }
        while x1 > W * 3 / 4 && !wood(s.get(x1, ry)) { x1 -= 1 }
        let size = Double(x1 - x0 + 1)
        if size < Double(W) * 0.7 { return nil }
        let cx = Int(Double(x0) + size * 10 / 1170 + size / 16)
        var top = ry, gap = 0
        while top > bar && gap < 25 { top -= 1; gap = wood(s.get(cx, top)) ? 0 : gap + 1 }
        top += gap
        if top <= bar || Double(top) + size > Double(H) { return nil }
        let inset = size * 10 / 1170, C = (size - 2 * inset) / 8
        let gx = Double(x0) + inset, gy = Double(top) + inset * 0.6

        func avg(_ cx: Double, _ cy: Double, _ r: Int) -> (Double, Double, Double) {
            var a = 0.0, b = 0.0, c = 0.0, n = 0.0
            for dy in -r...r { for dx in -r...r {
                let p = s.get(min(W - 1, max(0, Int(cx) + dx)), min(H - 1, max(0, Int(cy) + dy)))
                a += p.0; b += p.1; c += p.2; n += 1
            } }
            return (a / n, b / n, c / n)
        }
        var cells = [Int](repeating: 0, count: 64)
        var reds = 0, silvers = 0, odd = 0
        var rowSum = [0.0, 0.0, 0.0]
        for r in 0..<8 { for c in 0..<8 where (r + c) & 1 == 1 {
            let px = gx + C * (Double(c) + 0.5), py = gy + C * (Double(r) + 0.5)
            let p = avg(px, py, max(1, Int(C / 48)))
            let L = (p.0 + p.1 + p.2) / 3
            var v = 0
            if p.0 - p.1 > 70 && p.1 < 60 { v = 1 }
            else if abs(p.0 - p.2) < 15 && abs(p.0 - p.1) < 15 && L > 95 { v = 2 }
            else if !(p.0 - p.2 > 25) { odd += 1 }   // neither a piece nor wood (or the grey last-move tint): something passing over
            if v != 0 {
                // a man has a ring moulded into its face; a king (turned over) is flat there
                var lo = 999.0, hi = -1.0
                for k in 0..<16 {
                    let a = Double(k) * Double.pi / 8
                    let q = avg(px + 0.2 * C * cos(a), py + 0.2 * C * sin(a), max(1, Int(C / 72)))
                    let l = (q.0 + q.1 + q.2) / 3
                    lo = min(lo, l); hi = max(hi, l)
                }
                if hi - lo < 14 { v += 2 }
                if v % 2 == 1 { reds += 1 } else { silvers += 1 }
                rowSum[(v - 1) % 2 + 1] += Double(r)
            }
            cells[r * 8 + c] = v
        } }
        let valid = reds + silvers >= 2 && reds <= 12 && silvers <= 12 && odd <= 2

        lock.lock(); defer { lock.unlock() }
        if !valid {
            same = 0; last = []
            return sent ?? BoardMessage(valid: false, game: .checkers, cells: cells, me: me, myTurn: false)
        }
        // a board only counts once it has been read the same three frames running (pieces slide and fade)
        if cells == last { same += 1 } else { last = cells; same = 1 }
        if same < 3 { return sent ?? BoardMessage(valid: false, game: .checkers, cells: cells, me: me, myTurn: false) }
        if cells != stable {
            // which side you are: the one at the bottom, judged while plenty of men are on the board
            if reds >= 5 && silvers >= 5 {
                let ar = rowSum[1] / Double(reds), as_ = rowSum[2] / Double(silvers)
                if abs(ar - as_) > 1.5 { me = ar > as_ ? 1 : 2; meSure = true }
            }
            // whose turn: the side that just moved has a piece where it had none
            if !stable.isEmpty {
                var moved = 0
                for i in 0..<64 where cells[i] != 0 && (stable[i] == 0 || (stable[i] - 1) % 2 != (cells[i] - 1) % 2) {
                    moved = (cells[i] - 1) % 2 + 1
                }
                if moved != 0 { myTurn = moved != me }
            }
            // more pieces than before: a new game (or a position set up by hand) — assume it's your move
            if reds + silvers > stable.filter({ $0 != 0 }).count { myTurn = true }
            stable = cells
        }
        let m = BoardMessage(valid: true, game: .checkers, cells: cells, me: me, myTurn: myTurn)
        sent = m
        return m
    }
}
