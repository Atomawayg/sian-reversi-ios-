import UIKit
import CoreVideo

/// What the floating window shows.
struct Overlay: Equatable {
    var game: GameKind = .reversi
    /// board cells (row-major from top-left) or nil.
    /// reversi: 0 empty, 1 black, 2 white, 3 hole · checkers: 1 your man, 2 your king, 3 opp man, 4 opp king
    /// connect: 1 you, 3 opponent
    var cells: [Int]? = nil
    var rec: Int? = nil          // reversi: cell index · connect: column
    var path: [Int] = []         // checkers: squares 0..63 of the suggested move
    var caps: [Int] = []         // checkers: captured squares
    var title: String = ""
    var line: String = ""
    var mine: Bool = false       // gold accent when it's your move
    var meColor: Int = 1         // checkers/connect: 1 red, 2 purple/yellow (to match the game's colours)
    var footer: String = ""
    // Jackaroo
    var hand: [String] = []      // cards in your hand
    var pick: Int = -1           // index of the card to play
    var arrows: [Int] = []       // pairs (from, to): 0…75 track, 100+4*seat+slot lane, 200+seat home
    var steps: [String] = []     // numbered things to tap, in order (step 1 = the card)
    var tags: [String] = []      // why: captures, finishing, reasons
    var marks: [Int] = []        // stone to tap for step 2, 3… (same codes as arrows)
    var swap = false             // J: the two marked stones trade places

    init(game: GameKind = .reversi, cells: [Int]? = nil, rec: Int? = nil, path: [Int] = [], caps: [Int] = [],
         title: String, line: String, mine: Bool = false, meColor: Int = 1) {
        self.game = game; self.cells = cells; self.rec = rec; self.path = path; self.caps = caps
        self.title = title; self.line = line; self.mine = mine; self.meColor = meColor
    }
}

enum Renderer {
    static let size = CGSize(width: 640, height: 360)
    /// flips twice a second so the stones to tap blink
    static var pulse = false

    private static let bg = UIColor(red: 0.055, green: 0.078, blue: 0.141, alpha: 1)
    private static let felt = UIColor(red: 0.118, green: 0.416, blue: 0.271, alpha: 1)
    private static let feltLine = UIColor(red: 0.059, green: 0.239, blue: 0.153, alpha: 1)
    private static let gold = UIColor(red: 0.949, green: 0.757, blue: 0.306, alpha: 1)
    private static let ink = UIColor(red: 0.914, green: 0.941, blue: 0.918, alpha: 1)
    private static let muted = UIColor(red: 0.588, green: 0.627, blue: 0.722, alpha: 1)
    private static let hole = UIColor(red: 0.17, green: 0.11, blue: 0.07, alpha: 1)
    private static let red = UIColor(red: 0.80, green: 0.22, blue: 0.20, alpha: 1)
    private static let purple = UIColor(red: 0.42, green: 0.38, blue: 0.52, alpha: 1)
    private static let yellow = UIColor(red: 0.95, green: 0.78, blue: 0.22, alpha: 1)
    private static let sqLight = UIColor(red: 0.93, green: 0.86, blue: 0.81, alpha: 1)
    private static let sqDark = UIColor(red: 0.80, green: 0.66, blue: 0.62, alpha: 1)
    private static let panel = UIColor(red: 0.22, green: 0.20, blue: 0.30, alpha: 1)
    private static let slot = UIColor(red: 0.14, green: 0.13, blue: 0.20, alpha: 1)
    private static let arrow = UIColor(red: 0.25, green: 0.88, blue: 0.68, alpha: 1)

    static func pixelBuffer(_ o: Overlay) -> CVPixelBuffer? {
        let w = Int(size.width), h = Int(size.height)
        var pbOut: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        draw(o, in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        return pb
    }

    static func draw(_ o: Overlay, in rect: CGRect) {
        bg.setFill(); UIRectFill(rect)
        let pad: CGFloat = 20
        let side = rect.height - pad * 2
        var textX = pad
        if o.game == .jackaroo, let cells = o.cells, cells.count == JK.count {
            drawJackaroo(o, cells, rect)
            return
        }
        if let cells = o.cells, !cells.isEmpty {
            switch o.game {
            case .reversi: drawReversi(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .checkers: drawCheckers(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .connect4, .connect5: drawConnect(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .jackaroo: break
            }
            textX = pad + side + 24
        }
        let tw = rect.width - textX - pad
        let titleFont = UIFont.systemFont(ofSize: o.title.count <= 3 ? 110 : (o.title.count <= 6 ? 64 : 40), weight: .heavy)
        let tAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: o.mine ? gold : ink]
        let tSize = (o.title as NSString).boundingRect(with: CGSize(width: tw, height: 200), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil)
        let lAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: muted]
        let lSize = (o.line as NSString).boundingRect(with: CGSize(width: tw, height: 170), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil)
        let total = tSize.height + 8 + lSize.height
        var y = (rect.height - total) / 2
        (o.title as NSString).draw(with: CGRect(x: textX, y: y, width: tw, height: tSize.height), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil)
        y += tSize.height + 8
        (o.line as NSString).draw(with: CGRect(x: textX, y: y, width: tw, height: lSize.height), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil)
        if !o.footer.isEmpty {
            let fAttr: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: muted.withAlphaComponent(0.8)]
            (o.footer as NSString).draw(with: CGRect(x: 8, y: rect.height - 20, width: rect.width - 16, height: 18), options: .usesLineFragmentOrigin, attributes: fAttr, context: nil)
        }
    }

    private static func grid(_ r: CGRect, cols: Int, rows: Int, inset: CGFloat, gap: CGFloat) -> (CGFloat, (Int, Int) -> CGRect, CGRect) {
        let cs = min((r.width - inset * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols), (r.height - inset * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let bw = cs * CGFloat(cols) + gap * CGFloat(cols - 1) + inset * 2
        let bh = cs * CGFloat(rows) + gap * CGFloat(rows - 1) + inset * 2
        let box = CGRect(x: r.minX + (r.width - bw) / 2, y: r.minY + (r.height - bh) / 2, width: bw, height: bh)
        let cell = { (row: Int, col: Int) -> CGRect in
            CGRect(x: box.minX + inset + CGFloat(col) * (cs + gap), y: box.minY + inset + CGFloat(row) * (cs + gap), width: cs, height: cs)
        }
        return (cs, cell, box)
    }

    private static func ring(_ cr: CGRect, _ cs: CGFloat) {
        gold.setStroke()
        let p = UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.06, dy: cs * 0.06)); p.lineWidth = 4; p.stroke()
    }

    private static func drawReversi(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        let (cs, cell, box) = grid(r, cols: 8, rows: 8, inset: 5, gap: 2)
        feltLine.setFill(); UIBezierPath(roundedRect: box, cornerRadius: 10).fill()
        for row in 0..<8 { for col in 0..<8 {
            let cr = cell(row, col), v = cells[row * 8 + col]
            (v == 3 ? hole : felt).setFill(); UIBezierPath(roundedRect: cr, cornerRadius: 3).fill()
            if v == 1 || v == 2 {
                (v == 1 ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1)).setFill()
                UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.1, dy: cs * 0.1)).fill()
            }
            if o.rec == row * 8 + col {
                ring(cr, cs)
                gold.withAlphaComponent(0.35).setFill(); UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.25, dy: cs * 0.25)).fill()
            }
        } }
    }

    private static func drawCheckers(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        let (cs, cell, box) = grid(r, cols: 8, rows: 8, inset: 4, gap: 0)
        UIColor(white: 0.97, alpha: 1).setFill(); UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
        let mineCol = o.meColor == 2 ? purple : red, oppCol = o.meColor == 2 ? red : purple
        for row in 0..<8 { for col in 0..<8 {
            let cr = cell(row, col)
            ((row + col) & 1 == 1 ? sqDark : sqLight).setFill(); UIRectFill(cr)
        } }
        if o.path.count >= 2 {
            let from = o.path[0]
            gold.withAlphaComponent(0.55).setFill(); UIRectFill(cell(from / 8, from % 8))
        }
        for i in 0..<64 {
            let v = cells[i]; if v == 0 { continue }
            let cr = cell(i / 8, i % 8)
            ((v == 1 || v == 2) ? mineCol : oppCol).setFill()
            UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.1, dy: cs * 0.1)).fill()
            if v == 2 || v == 4 {
                gold.setStroke()
                let k = UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.28, dy: cs * 0.28)); k.lineWidth = 3; k.stroke()
            }
        }
        for s in o.caps {
            let cr = cell(s / 8, s % 8).insetBy(dx: cs * 0.22, dy: cs * 0.22)
            let x = UIBezierPath(); x.move(to: cr.origin); x.addLine(to: CGPoint(x: cr.maxX, y: cr.maxY))
            x.move(to: CGPoint(x: cr.maxX, y: cr.minY)); x.addLine(to: CGPoint(x: cr.minX, y: cr.maxY))
            x.lineWidth = 5; x.lineCapStyle = .round; arrow.setStroke(); x.stroke()
        }
        if o.path.count >= 2 {
            let pts = o.path.map { s -> CGPoint in let c = cell(s / 8, s % 8); return CGPoint(x: c.midX, y: c.midY) }
            let p = UIBezierPath(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }
            p.lineWidth = 7; p.lineCapStyle = .round; p.lineJoinStyle = .round
            arrow.setStroke(); p.stroke()
            let last = pts[pts.count - 1]
            arrow.setFill(); UIBezierPath(ovalIn: CGRect(x: last.x - cs * 0.22, y: last.y - cs * 0.22, width: cs * 0.44, height: cs * 0.44)).fill()
            ring(cell(o.path[0] / 8, o.path[0] % 8), cs)
        }
    }

    private static func drawConnect(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        let (cols, rows) = o.game.size
        let top: CGFloat = 26
        let area = CGRect(x: r.minX, y: r.minY + top, width: r.width, height: r.height - top)
        let (cs, cell, box) = grid(area, cols: cols, rows: rows, inset: 4, gap: 2)
        panel.setFill(); UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
        let mineCol = o.meColor == 2 ? yellow : red, oppCol = o.meColor == 2 ? red : yellow
        var landing: Int? = nil
        if let c = o.rec, c >= 0 && c < cols {
            var rr = rows - 1
            while rr >= 0 && cells[rr * cols + c] != 0 { rr -= 1 }
            if rr >= 0 { landing = rr }
            let colRect = cell(0, c)
            gold.setFill()
            let a = UIBezierPath()
            a.move(to: CGPoint(x: colRect.midX - 12, y: r.minY)); a.addLine(to: CGPoint(x: colRect.midX + 12, y: r.minY))
            a.addLine(to: CGPoint(x: colRect.midX, y: r.minY + top - 2)); a.close(); a.fill()
        }
        for row in 0..<rows { for col in 0..<cols {
            let cr = cell(row, col).insetBy(dx: cs * 0.06, dy: cs * 0.06)
            let v = cells[row * cols + col]
            (v == 1 ? mineCol : (v == 3 ? oppCol : slot)).setFill()
            UIBezierPath(ovalIn: cr).fill()
            if let c = o.rec, c == col, let lr = landing, lr == row {
                mineCol.withAlphaComponent(0.45).setFill(); UIBezierPath(ovalIn: cr).fill()
                ring(cell(row, col), cs)
            }
        } }
    }

    // MARK: Jackaroo
    static let jkColours: [UIColor] = [
        UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1),   // empty hole
        UIColor(red: 0.22, green: 0.80, blue: 0.20, alpha: 1),   // green
        UIColor(red: 0.90, green: 0.18, blue: 0.16, alpha: 1),   // red
        UIColor(red: 0.20, green: 0.62, blue: 0.95, alpha: 1),   // blue
        UIColor(red: 1.00, green: 0.66, blue: 0.05, alpha: 1),   // orange
    ]

    static func jkPoint(_ code: Int, _ map: (Double, Double) -> CGPoint) -> CGPoint {
        if code >= 0 && code < 76 { let p = JKGeo.track[code]; return map(p.0, p.1) }
        if code >= 100 && code < 116 { let s = (code - 100) / 4, k = (code - 100) % 4; let p = JKGeo.lanes[s][k]; return map(p.0, p.1) }
        let s = max(0, min(3, code - 200))
        let hs = JKGeo.homes[s]
        return map(hs.map { $0.0 }.reduce(0, +) / 4, hs.map { $0.1 }.reduce(0, +) / 4)
    }

    /// Holes the stone passes through, so the arrow follows the track.
    static func jkRoute(_ from: Int, _ to: Int) -> [Int] {
        guard from >= 0 && from < 76 else { return [from, to] }
        if to >= 0 && to < 76 {
            let f = ((to - from) % 76 + 76) % 76
            if f <= 13 { return (0...f).map { (from + $0) % 76 } }
            let bk = ((from - to) % 76 + 76) % 76
            if bk <= 4 { return (0...bk).map { ((from - $0) % 76 + 76) % 76 } }
            return [from, to]
        }
        if to >= 100 && to < 116 {
            let s = (to - 100) / 4, k = (to - 100) % 4
            let entry = ((19 * s - 2) % 76 + 76) % 76
            let f = ((entry - from) % 76 + 76) % 76
            if f > 13 { return [from, to] }
            return (0...f).map { (from + $0) % 76 } + (0...k).map { 100 + 4 * s + $0 }
        }
        return [from, to]
    }

    private static func head(from p: CGPoint, to b: CGPoint) {
        let ang = atan2(b.y - p.y, b.x - p.x), hl: CGFloat = 14
        let h = UIBezierPath()
        h.move(to: b)
        h.addLine(to: CGPoint(x: b.x - hl * cos(ang - 0.5), y: b.y - hl * sin(ang - 0.5)))
        h.addLine(to: CGPoint(x: b.x - hl * cos(ang + 0.5), y: b.y - hl * sin(ang + 0.5)))
        h.close(); arrow.setFill(); h.fill()
    }

    private static func badge(_ n: Int, at c: CGPoint, radius: CGFloat) {
        gold.setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
        let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: radius * 1.35, weight: .heavy), .foregroundColor: bg]
        let t = "\(n)" as NSString, sz = t.size(withAttributes: a)
        t.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2), withAttributes: a)
    }

    /// which step (2, 3…) is on screen now: multi-tap moves show one tap at a time, every 2 seconds
    static func jkStepNow(_ count: Int) -> Int {
        count <= 1 ? 0 : Int(Date().timeIntervalSince1970 / 2) % count
    }

    private static func drawJackaroo(_ o: Overlay, _ cells: [Int], _ rect: CGRect) {
        let pad: CGFloat = 8
        let side = rect.height - pad * 2
        let box = CGRect(x: pad, y: pad, width: side, height: side)
        // stone steps are "colour|which stone|what to do"
        let stoneSteps = o.steps.dropFirst().map { $0.components(separatedBy: "|") }.filter { $0.count == 3 }
        let now = jkStepNow(stoneSteps.count)
        // zoom on the move: every hole the stones pass through, plus a margin
        var focus: [(Double, Double)] = []
        func src(_ code: Int) -> (Double, Double) {
            if code >= 0 && code < 76 { return JKGeo.track[code] }
            if code >= 100 && code < 116 { return JKGeo.lanes[(code - 100) / 4][(code - 100) % 4] }
            let hs = JKGeo.homes[max(0, min(3, code - 200))]
            return (hs.map { $0.0 }.reduce(0, +) / 4, hs.map { $0.1 }.reduce(0, +) / 4)
        }
        var i = 0
        while i + 1 < o.arrows.count { for c in jkRoute(o.arrows[i], o.arrows[i + 1]) { focus.append(src(c)) }; i += 2 }
        for m in o.marks { focus.append(src(m)) }
        var cx = JKGeo.center.0, cy = JKGeo.center.1, span = 1120.0
        if !focus.isEmpty {
            let xs = focus.map { $0.0 }, ys = focus.map { $0.1 }
            cx = (xs.min()! + xs.max()!) / 2; cy = (ys.min()! + ys.max()!) / 2
            span = min(1120, max(420, max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) + 300))
        }
        let k = Double(side) / span
        let map = { (x: Double, y: Double) -> CGPoint in
            CGPoint(x: Double(box.midX) + (x - cx) * k, y: Double(box.midY) + (y - cy) * k)
        }
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        let clip = UIBezierPath(roundedRect: box, cornerRadius: 18)
        clip.addClip()
        UIColor(red: 0.86, green: 0.70, blue: 0.47, alpha: 1).setFill(); UIRectFill(box)
        let r = CGFloat(15 * k)
        func dot(_ p: CGPoint, _ c: Int) {
            let rr = c == 0 ? r * 0.55 : r
            jkColours[c].setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)).fill()
        }
        for s in 0..<4 {
            let c = cells[JK.seats + s]
            let p = map(JKGeo.track[19 * s].0, JKGeo.track[19 * s].1)
            (c > 0 ? jkColours[c] : UIColor.gray).withAlphaComponent(0.8).setStroke()
            let sq = UIBezierPath(roundedRect: CGRect(x: p.x - r * 1.35, y: p.y - r * 1.35, width: r * 2.7, height: r * 2.7), cornerRadius: 4)
            sq.lineWidth = 3; sq.stroke()
        }
        for t in 0..<76 { let p = JKGeo.track[t]; dot(map(p.0, p.1), cells[JK.track + t]) }
        for s in 0..<4 { for q in 0..<4 {
            let l = JKGeo.lanes[s][q]; dot(map(l.0, l.1), cells[JK.lanes + 4 * s + q])
            let h = JKGeo.homes[s][q]; dot(map(h.0, h.1), cells[JK.homes + 4 * s + q])
        } }
        // the move: route + white target
        if o.swap, o.marks.count >= 2 {
            let a = jkPoint(o.marks[0], map), b = jkPoint(o.marks[1], map)
            let path = UIBezierPath(); path.move(to: a); path.addLine(to: b)
            path.lineWidth = 8; path.lineCapStyle = .round; arrow.setStroke(); path.stroke()
            head(from: b, to: a); head(from: a, to: b)
        } else {
            var j = 0
            while j + 1 < o.arrows.count {
                let current = stoneSteps.count <= 1 || j / 2 == now
                let pts = jkRoute(o.arrows[j], o.arrows[j + 1]).map { jkPoint($0, map) }
                let b = jkPoint(o.arrows[j + 1], map)
                let path = UIBezierPath(); path.move(to: pts.first ?? b)
                for q in pts.dropFirst() { path.addLine(to: q) }
                if pts.count < 2 { path.addLine(to: b) }
                path.lineJoinStyle = .round; path.lineCapStyle = .round
                path.lineWidth = current ? 8 : 4
                arrow.withAlphaComponent(current ? 1 : 0.4).setStroke(); path.stroke()
                if current {
                    for (rad, w) in [(r * 2.1, CGFloat(4)), (r * 1.3, CGFloat(4))] {
                        let t = UIBezierPath(ovalIn: CGRect(x: b.x - rad, y: b.y - rad, width: rad * 2, height: rad * 2)); t.lineWidth = w
                        UIColor.white.setStroke(); t.stroke()
                    }
                    head(from: pts.count >= 2 ? pts[pts.count - 2] : b, to: b)
                }
                j += 2
            }
        }
        // the stone to tap now: big blinking gold ring
        for (n, code) in o.marks.enumerated() {
            let a = jkPoint(code, map)
            let current = o.swap || stoneSteps.count <= 1 || n == now
            let rr = r * (current && pulse ? 2.2 : 1.8)
            let ring = UIBezierPath(ovalIn: CGRect(x: a.x - rr, y: a.y - rr, width: rr * 2, height: rr * 2))
            ring.lineWidth = current ? (pulse ? 8 : 5) : 3
            gold.withAlphaComponent(current ? 1 : 0.45).setStroke(); ring.stroke()
            if o.marks.count > 1 { badge(n + 2, at: CGPoint(x: a.x + rr * 0.85, y: a.y - rr * 0.85), radius: 14) }
        }
        ctx?.restoreGState()
        UIColor(white: 1, alpha: 0.15).setStroke()
        let frame = UIBezierPath(roundedRect: box, cornerRadius: 18); frame.lineWidth = 2; frame.stroke()
        // little whole-board map in the corner when zoomed, so you know where on the board this is
        if span < 1100 {
            let mm = CGRect(x: box.maxX - 78, y: box.maxY - 78, width: 70, height: 70)
            bg.withAlphaComponent(0.85).setFill(); UIBezierPath(ovalIn: mm.insetBy(dx: -3, dy: -3)).fill()
            let mk = Double(mm.width) / 1120
            let mmap = { (x: Double, y: Double) -> CGPoint in CGPoint(x: Double(mm.midX) + (x - JKGeo.center.0) * mk, y: Double(mm.midY) + (y - JKGeo.center.1) * mk) }
            for t in 0..<76 { let p = JKGeo.track[t], q = mmap(p.0, p.1), c = cells[JK.track + t]
                (c == 0 ? UIColor(white: 1, alpha: 0.25) : jkColours[c]).setFill()
                let rr: CGFloat = c == 0 ? 1 : 2.4
                UIBezierPath(ovalIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)).fill() }
            let vw = CGFloat(span * mk), vc = mmap(cx, cy)
            gold.setStroke(); let v = UIBezierPath(rect: CGRect(x: vc.x - vw / 2, y: vc.y - vw / 2, width: vw, height: vw)); v.lineWidth = 2; v.stroke()
        }

        // right side: big card, which card, then the one thing to do now
        let tx = box.maxX + 16
        let tw = rect.width - tx - 10
        var y: CGFloat = 12
        if o.pick >= 0 && o.pick < o.hand.count {
            let cardRect = CGRect(x: tx, y: y, width: 92, height: 128)
            UIColor.white.setFill()
            let cp = UIBezierPath(roundedRect: cardRect, cornerRadius: 12); cp.fill()
            gold.setStroke(); cp.lineWidth = pulse ? 8 : 5; cp.stroke()
            let rank = o.hand[o.pick]
            let rAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: rank.count > 1 ? 62 : 84, weight: .heavy), .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            let rsz = (rank as NSString).size(withAttributes: rAttr)
            (rank as NSString).draw(at: CGPoint(x: cardRect.midX - rsz.width / 2, y: cardRect.midY - rsz.height / 2), withAttributes: rAttr)
            let hx = cardRect.maxX + 14
            let big: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .heavy), .foregroundColor: ink]
            ("ใบที่ \(o.pick + 1)" as NSString).draw(at: CGPoint(x: hx, y: y + 6), withAttributes: big)
            let sm: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: muted]
            ("จากซ้าย" as NSString).draw(at: CGPoint(x: hx, y: y + 58), withAttributes: sm)
            // tiny hand under it so the position is easy to match
            for (jj, h) in o.hand.enumerated() {
                let rr = CGRect(x: hx + CGFloat(jj) * 25, y: y + 98, width: 21, height: 28)
                if rr.maxX > rect.width - 4 { break }
                (jj == o.pick ? gold : UIColor(white: 0.8, alpha: 1)).setFill()
                UIBezierPath(roundedRect: rr, cornerRadius: 3).fill()
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.black]
                let sz = (h as NSString).size(withAttributes: a)
                (h as NSString).draw(at: CGPoint(x: rr.midX - sz.width / 2, y: rr.midY - sz.height / 2), withAttributes: a)
            }
            y = cardRect.maxY + 14
        } else { y = 40 }
        if !stoneSteps.isEmpty {
            let st = stoneSteps[min(now, stoneSteps.count - 1)]
            let colour = Int(st[0]) ?? 0
            var lx = tx
            if colour > 0 {
                jkColours[colour].setFill()
                UIBezierPath(ovalIn: CGRect(x: tx, y: y + 8, width: 34, height: 34)).fill()
                gold.setStroke(); let rg = UIBezierPath(ovalIn: CGRect(x: tx - 3, y: y + 5, width: 40, height: 40)); rg.lineWidth = 3; rg.stroke()
                lx = tx + 46
            }
            let who: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: st[1].count > 9 ? 32 : 42, weight: .heavy), .foregroundColor: gold]
            (st[1] as NSString).draw(with: CGRect(x: lx, y: y, width: rect.width - lx - 8, height: 52), options: .usesLineFragmentOrigin, attributes: who, context: nil)
            y += 54
            let act: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: st[2].count > 9 ? 34 : 44, weight: .heavy), .foregroundColor: ink]
            (st[2] as NSString).draw(with: CGRect(x: tx, y: y, width: tw, height: 56), options: .usesLineFragmentOrigin, attributes: act, context: nil)
            y += 56
            if stoneSteps.count > 1 {
                let note: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: muted]
                ("ขั้นที่ \(now + 1)/\(stoneSteps.count)" as NSString).draw(at: CGPoint(x: tx, y: y), withAttributes: note)
                y += 26
            }
            if let tag = o.tags.first {
                let g: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: gold]
                (tag as NSString).draw(with: CGRect(x: tx, y: y, width: tw, height: rect.height - y - 4), options: .usesLineFragmentOrigin, attributes: g, context: nil)
            }
        } else {
            let t1: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: o.title.count > 10 ? 32 : 40, weight: .heavy), .foregroundColor: o.mine ? gold : ink]
            let s1 = (o.title as NSString).boundingRect(with: CGSize(width: tw, height: 120), options: .usesLineFragmentOrigin, attributes: t1, context: nil)
            (o.title as NSString).draw(with: CGRect(x: tx, y: y, width: tw, height: s1.height), options: .usesLineFragmentOrigin, attributes: t1, context: nil)
            let t2: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: muted]
            let body = ([o.line] + o.tags).filter { !$0.isEmpty }.joined(separator: "\n")
            (body as NSString).draw(with: CGRect(x: tx, y: y + s1.height + 4, width: tw, height: rect.height - y - s1.height - 8), options: .usesLineFragmentOrigin, attributes: t2, context: nil)
        }
    }

    static func image(_ o: Overlay) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in draw(o, in: CGRect(origin: .zero, size: size)) }
    }
}
