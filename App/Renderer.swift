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
    var stage = 0                // 1 = tap the card, 2 = card confirmed, tap the stone
    var action = ""              // one word: เดิน 7, ออกลูก, สลับ…
    // fruit game
    var drop: Int? = nil         // x (screen px) to drop the held fruit at
    var pool: PoolView? = nil    // pool: the table, the suggested shot and what your aim does
    var land: [Int] = []         // x, y where it comes to rest (empty when it merges)

    init(game: GameKind = .reversi, cells: [Int]? = nil, rec: Int? = nil, path: [Int] = [], caps: [Int] = [],
         title: String, line: String, mine: Bool = false, meColor: Int = 1) {
        self.game = game; self.cells = cells; self.rec = rec; self.path = path; self.caps = caps
        self.title = title; self.line = line; self.mine = mine; self.meColor = meColor
    }
}

enum Renderer {
    static let size = CGSize(width: 640, height: 360)
    /// pool is drawn upright like the game, so its window is tall
    static let poolSize = CGSize(width: 400, height: 870)
    static func frameSize(_ o: Overlay) -> CGSize { o.game == .pool && o.pool != nil ? poolSize : size }
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
        let size = frameSize(o)
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
        if o.game == .pool, let pv = o.pool { drawPool(o, pv, rect); return }
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
            case .checkers, .draughts: drawCheckers(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .chess: drawChess(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .connect4, .connect5: drawConnect(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .suika: drawSuika(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .jackaroo, .pool: break
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
        let cream = UIColor(red: 0.93, green: 0.89, blue: 0.80, alpha: 1)
        let mineCol = o.meColor == 3 ? cream : (o.meColor == 2 ? purple : red)
        let oppCol = o.meColor == 3 || o.meColor == 4 ? (o.meColor == 3 ? red : cream) : (o.meColor == 2 ? red : purple)
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

    // MARK: Fruit game
    static let skColours: [UIColor] = [
        UIColor(red: 0.86, green: 0.18, blue: 0.20, alpha: 1),   // cherry
        UIColor(red: 0.97, green: 0.40, blue: 0.52, alpha: 1),   // strawberry
        UIColor(red: 0.58, green: 0.38, blue: 0.90, alpha: 1),   // grape
        UIColor(red: 0.98, green: 0.74, blue: 0.22, alpha: 1),   // dekopon
        UIColor(red: 0.95, green: 0.50, blue: 0.14, alpha: 1),   // persimmon
        UIColor(red: 0.84, green: 0.26, blue: 0.22, alpha: 1),   // apple
        UIColor(red: 0.95, green: 0.86, blue: 0.32, alpha: 1),   // pear
        UIColor(red: 0.98, green: 0.72, blue: 0.74, alpha: 1),   // peach
        UIColor(red: 1.00, green: 0.90, blue: 0.10, alpha: 1),   // pineapple
        UIColor(red: 0.45, green: 0.76, blue: 0.42, alpha: 1),   // melon
        UIColor(red: 0.34, green: 0.66, blue: 0.14, alpha: 1),   // watermelon
    ]

    private static func drawSuika(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        guard let st = SK.decode(cells) else { return }
        // the jar from the read area's top (above the jar, where Will holds the fruit) down to the floor
        let wx0 = SK.left - 8, wx1 = SK.right + 8, wy0 = SK.top + 20, wy1 = SK.floor + 10
        let k = min(r.width / CGFloat(wx1 - wx0), r.height / CGFloat(wy1 - wy0))
        let ox = r.midX - CGFloat(wx1 - wx0) * k / 2, oy = r.minY
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + CGFloat(x - wx0) * k, y: oy + CGFloat(y - wy0) * k) }
        let jarRect = CGRect(origin: P(SK.left, SK.dead), size: CGSize(width: CGFloat(SK.right - SK.left) * k, height: CGFloat(SK.floor - SK.dead) * k))
        UIColor(red: 0.55, green: 0.78, blue: 0.97, alpha: 1).setFill()
        UIBezierPath(roundedRect: jarRect, cornerRadius: 6).fill()
        UIColor.white.setStroke()
        let wall = UIBezierPath(roundedRect: jarRect.insetBy(dx: -2, dy: -2), cornerRadius: 7); wall.lineWidth = 3; wall.stroke()
        // dashed line in the middle (the game draws it too) and scale 0…10 above the jar
        let mid = UIBezierPath(); mid.move(to: P((SK.left + SK.right) / 2, SK.dead)); mid.addLine(to: P((SK.left + SK.right) / 2, SK.floor))
        mid.lineWidth = 1.5; mid.setLineDash([5, 5], count: 2, phase: 0); UIColor.white.withAlphaComponent(0.7).setStroke(); mid.stroke()
        for i in 0...10 {
            let x = SK.left + (SK.right - SK.left) * Double(i) / 10
            let a = P(x, SK.dead), h: CGFloat = i % 5 == 0 ? 10 : 5
            let t = UIBezierPath(); t.move(to: CGPoint(x: a.x, y: a.y - 2)); t.addLine(to: CGPoint(x: a.x, y: a.y - 2 - h))
            t.lineWidth = 2; muted.setStroke(); t.stroke()
        }
        for f in st.fruits {
            let c = P(f.x, f.y), rr = CGFloat(SK.radius[f.t]) * k
            skColours[f.t].setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)).fill()
        }
        // suggestion: gold line from the drop spot down to where the fruit lands
        if let dx = o.drop, st.held >= 0 {
            let x = Double(dx)
            let endY = o.land.count == 2 ? Double(o.land[1]) : SK.floor
            let line = UIBezierPath(); line.move(to: P(x, SK.dropY)); line.addLine(to: P(x, endY))
            line.lineWidth = 3; line.setLineDash([7, 5], count: 2, phase: 0); gold.setStroke(); line.stroke()
            let rr = CGFloat(SK.radius[st.held]) * k
            if o.land.count == 2 {
                let c = P(Double(o.land[0]), Double(o.land[1]))
                let g = UIBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)); g.lineWidth = 3; g.stroke()
            }
            let c = P(x, SK.dropY)
            gold.setFill()
            let a = UIBezierPath()
            a.move(to: CGPoint(x: c.x - 10, y: oy)); a.addLine(to: CGPoint(x: c.x + 10, y: oy)); a.addLine(to: CGPoint(x: c.x, y: oy + 14)); a.close(); a.fill()
        }
        // the fruit Will holds, where it is now
        if st.held >= 0 {
            let c = P(st.heldX, SK.dropY), rr = CGFloat(SK.radius[st.held]) * k
            skColours[st.held].setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)).fill()
            UIColor.white.setStroke()
            let e = UIBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)); e.lineWidth = 2; e.stroke()
        }
        // next fruit: small badge in the top-right corner
        if st.next >= 0 {
            let c = CGPoint(x: r.maxX - 14, y: r.minY + 14)
            skColours[st.next].setFill(); UIBezierPath(ovalIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)).fill()
        }
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
        let pad: CGFloat = 6
        let side = rect.height - pad * 2
        let box = CGRect(x: pad, y: pad, width: side, height: side)
        let cx = JKGeo.center.0, cy = JKGeo.center.1
        let k = Double(side) / 1120
        let map = { (x: Double, y: Double) -> CGPoint in
            CGPoint(x: Double(box.midX) + (x - cx) * k, y: Double(box.midY) + (y - cy) * k)
        }
        let moving = !o.marks.isEmpty
        // the whole board, plain and dark, so the move is the only bright thing
        UIColor(red: 0.27, green: 0.23, blue: 0.19, alpha: 1).setFill()
        UIBezierPath(ovalIn: box).fill()
        let r = CGFloat(15 * k)
        func dot(_ p: CGPoint, _ c: Int) {
            if c == 0 {
                UIColor(red: 0.55, green: 0.47, blue: 0.39, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill()
                return
            }
            let rr = moving ? r * 0.85 : r * 1.1
            jkColours[c].withAlphaComponent(moving ? 0.55 : 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)).fill()
        }
        for s in 0..<4 {   // start squares in seat colour
            let c = cells[JK.seats + s]
            let p = map(JKGeo.track[19 * s].0, JKGeo.track[19 * s].1)
            (c > 0 ? jkColours[c] : UIColor.gray).withAlphaComponent(0.6).setStroke()
            let sq = UIBezierPath(roundedRect: CGRect(x: p.x - r * 1.2, y: p.y - r * 1.2, width: r * 2.4, height: r * 2.4), cornerRadius: 2)
            sq.lineWidth = 1.5; sq.stroke()
        }
        for t in 0..<76 { let p = JKGeo.track[t]; dot(map(p.0, p.1), cells[JK.track + t]) }
        for s in 0..<4 { for q in 0..<4 {
            let l = JKGeo.lanes[s][q]; dot(map(l.0, l.1), cells[JK.lanes + 4 * s + q])
            let h = JKGeo.homes[s][q]; dot(map(h.0, h.1), cells[JK.homes + 4 * s + q])
        } }
        let live = o.stage == 2          // after the card is confirmed the stone is what matters
        // route + target
        if o.swap, o.marks.count >= 2 {
            let a = jkPoint(o.marks[0], map), b = jkPoint(o.marks[1], map)
            let path = UIBezierPath(); path.move(to: a); path.addLine(to: b)
            path.lineWidth = live ? 8 : 4; path.lineCapStyle = .round
            arrow.withAlphaComponent(live ? 1 : 0.5).setStroke(); path.stroke()
            if live { head(from: b, to: a); head(from: a, to: b) }
        } else {
            var j = 0
            while j + 1 < o.arrows.count {
                let pts = jkRoute(o.arrows[j], o.arrows[j + 1]).map { jkPoint($0, map) }
                let b = jkPoint(o.arrows[j + 1], map)
                let path = UIBezierPath(); path.move(to: pts.first ?? b)
                for q in pts.dropFirst() { path.addLine(to: q) }
                if pts.count < 2 { path.addLine(to: b) }
                path.lineJoinStyle = .round; path.lineCapStyle = .round
                path.lineWidth = live ? 9 : 4
                arrow.withAlphaComponent(live ? 1 : 0.5).setStroke(); path.stroke()
                if live {
                    for (rad, w) in [(r * 2.2, CGFloat(4)), (r * 1.3, CGFloat(4))] {
                        let t = UIBezierPath(ovalIn: CGRect(x: b.x - rad, y: b.y - rad, width: rad * 2, height: rad * 2)); t.lineWidth = w
                        UIColor.white.setStroke(); t.stroke()
                    }
                }
                j += 2
            }
        }
        // the stone(s) to tap: a big gold disc with the stone's colour in the middle
        for (n, code) in o.marks.enumerated() {
            let a = jkPoint(code, map)
            let seatColour: Int = {
                if code >= 200 { return cells[JK.seats + (code - 200)] }
                if code >= 100 { return cells[JK.lanes + (code - 100)] }
                return cells[JK.track + code]
            }()
            let rr = live ? r * (pulse ? 2.6 : 2.2) : r * 1.8
            gold.withAlphaComponent(live ? 1 : 0.45).setFill()
            UIBezierPath(ovalIn: CGRect(x: a.x - rr, y: a.y - rr, width: rr * 2, height: rr * 2)).fill()
            let ir = rr * 0.58
            (seatColour > 0 ? jkColours[seatColour] : UIColor.white).setFill()
            UIBezierPath(ovalIn: CGRect(x: a.x - ir, y: a.y - ir, width: ir * 2, height: ir * 2)).fill()
            if o.marks.count > 1 && live { badge(n + 1, at: CGPoint(x: a.x + rr * 0.8, y: a.y - rr * 0.8), radius: 13) }
        }

        // right side
        let tx = box.maxX + 18
        let tw = rect.width - tx - 10
        let bigWord: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 60, weight: .heavy), .foregroundColor: ink]
        func word(_ t: String, _ y: CGFloat, _ colour: UIColor = ink, _ size: CGFloat = 60) {
            var a = bigWord; a[.foregroundColor] = colour
            var fs = size
            while fs > 26 && (t as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fs, weight: .heavy)]).width > tw { fs -= 4 }
            a[.font] = UIFont.systemFont(ofSize: fs, weight: .heavy)
            (t as NSString).draw(at: CGPoint(x: tx, y: y), withAttributes: a)
        }
        if o.pick >= 0 && o.pick < o.hand.count {
            // step 1: which card — big card, and its place in your hand as gold slot
            let cardRect = CGRect(x: tx, y: 14, width: 118, height: 164)
            UIColor.white.setFill()
            let cp = UIBezierPath(roundedRect: cardRect, cornerRadius: 14); cp.fill()
            gold.setStroke(); cp.lineWidth = pulse ? 9 : 6; cp.stroke()
            let rank = o.hand[o.pick]
            let rAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: rank.count > 1 ? 80 : 110, weight: .heavy), .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            let rsz = (rank as NSString).size(withAttributes: rAttr)
            (rank as NSString).draw(at: CGPoint(x: cardRect.midX - rsz.width / 2, y: cardRect.midY - rsz.height / 2), withAttributes: rAttr)
            let n = max(o.hand.count, 1)
            let gap: CGFloat = 7
            let sw = min(46, (tw - gap * CGFloat(n - 1)) / CGFloat(n))
            for j in 0..<n {
                let rr = CGRect(x: tx + CGFloat(j) * (sw + gap), y: 196, width: sw, height: 58)
                (j == o.pick ? gold : UIColor(red: 0.33, green: 0.36, blue: 0.46, alpha: 1)).setFill()
                UIBezierPath(roundedRect: rr, cornerRadius: 7).fill()
                if j == o.pick {
                    let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .heavy), .foregroundColor: bg]
                    let sz = (rank as NSString).size(withAttributes: a)
                    (rank as NSString).draw(at: CGPoint(x: rr.midX - sz.width / 2, y: rr.midY - sz.height / 2), withAttributes: a)
                }
            }
            word(o.stage == 1 ? "กดไพ่" : o.action, 270, gold, 56)
        } else if o.stage == 2 {
            // step 2: just what to do with the stone
            word("กดลูก", 40, gold, 56)
            word(o.action, 120, ink, 72)
            if let tag = o.tags.first {
                let g: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: gold]
                (tag as NSString).draw(with: CGRect(x: tx, y: 230, width: tw, height: 100), options: .usesLineFragmentOrigin, attributes: g, context: nil)
            }
        } else {
            word(o.title, 70, o.mine ? gold : ink, 52)
            let t2: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: muted]
            (o.line as NSString).draw(with: CGRect(x: tx, y: 150, width: tw, height: rect.height - 160), options: .usesLineFragmentOrigin, attributes: t2, context: nil)
        }
    }

    static func image(_ o: Overlay) -> UIImage {
        UIGraphicsImageRenderer(size: frameSize(o)).image { _ in draw(o, in: CGRect(origin: .zero, size: frameSize(o))) }
    }
    // MARK: chess
    private static func drawChess(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        let (cs, cell, box) = grid(r, cols: 8, rows: 8, inset: 4, gap: 0)
        UIColor(white: 0.97, alpha: 1).setFill(); UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
        let light = UIColor(red: 0.96, green: 0.88, blue: 0.74, alpha: 1), dark = UIColor(red: 0.62, green: 0.40, blue: 0.24, alpha: 1)
        for row in 0..<8 { for col in 0..<8 { ((row + col) & 1 == 1 ? dark : light).setFill(); UIRectFill(cell(row, col)) } }
        if o.path.count >= 2 {
            gold.withAlphaComponent(0.6).setFill(); UIRectFill(cell(o.path[0] / 8, o.path[0] % 8))
            gold.withAlphaComponent(0.35).setFill(); UIRectFill(cell(o.path[1] / 8, o.path[1] % 8))
        }
        let solid = ["", "♟", "♞", "♝", "♜", "♛", "♚"]
        for i in 0..<64 where cells[i] > 0 && cells[i] <= 12 {
            let white = cells[i] <= 6, t = solid[white ? cells[i] : cells[i] - 6] as NSString
            let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: cs * 0.82),
                                                     .foregroundColor: white ? UIColor.white : UIColor(white: 0.08, alpha: 1),
                                                     .strokeColor: white ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.7, alpha: 1), .strokeWidth: -2.5]
            let cr = cell(i / 8, i % 8), sz = t.size(withAttributes: a)
            t.draw(at: CGPoint(x: cr.midX - sz.width / 2, y: cr.midY - sz.height / 2), withAttributes: a)
        }
        if o.path.count >= 2 {
            let a = cell(o.path[0] / 8, o.path[0] % 8), b2 = cell(o.path[1] / 8, o.path[1] % 8)
            let p = UIBezierPath(); p.move(to: CGPoint(x: a.midX, y: a.midY)); p.addLine(to: CGPoint(x: b2.midX, y: b2.midY))
            p.lineWidth = 7; p.lineCapStyle = .round; arrow.withAlphaComponent(0.9).setStroke(); p.stroke()
            arrow.setFill(); UIBezierPath(ovalIn: CGRect(x: b2.midX - cs * 0.2, y: b2.midY - cs * 0.2, width: cs * 0.4, height: cs * 0.4)).fill()
            ring(a, cs)
        }
    }

}

/// Pool drawing data (screen pixels of a 1180×2556 screen).
struct PoolView: Equatable {
    var balls: [PoolEngine.Ball]
    var shot: PoolEngine.Shot?                 // the suggested shot
    var aimX: Double? = nil, aimY: Double? = nil   // the game's aim circle now
    var objPath: [Double] = []                 // x,y pairs: where the ball you are aiming at goes
    var cuePath: [Double] = []                 // x,y pairs: where the cue ball goes after the hit (no spin)
    var pots = false                           // your current aim pots one of your balls
    var legal: [Int] = []
}

extension Renderer {
    private static let poolColours: [UIColor] = [
        .white, UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1), UIColor(red: 0.10, green: 0.35, blue: 0.95, alpha: 1),
        UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1), UIColor(red: 0.45, green: 0.15, blue: 0.65, alpha: 1),
        UIColor(red: 1.0, green: 0.50, blue: 0.10, alpha: 1), UIColor(red: 0.10, green: 0.65, blue: 0.20, alpha: 1),
        UIColor(red: 0.50, green: 0.12, blue: 0.10, alpha: 1), .black]

    /// The table upright, as in the game, with a line of text on top.
    static func drawPool(_ o: Overlay, _ v: PoolView, _ rect: CGRect) {
        let gold = UIColor(red: 0.949, green: 0.757, blue: 0.306, alpha: 1)
        let green = UIColor(red: 0.30, green: 0.95, blue: 0.45, alpha: 1), red = UIColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 1)
        // text
        let tAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30, weight: .heavy), .foregroundColor: o.mine ? gold : UIColor.white]
        (o.title as NSString).draw(with: CGRect(x: 12, y: 6, width: rect.width - 24, height: 38), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil)
        let lAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: UIColor(white: 0.8, alpha: 1)]
        (o.line as NSString).draw(with: CGRect(x: 12, y: 42, width: rect.width - 24, height: 28), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil)
        // table: playing surface 759 × 1551 px on screen
        let area = CGRect(x: 14, y: 80, width: rect.width - 28, height: rect.height - 92)
        let sc = min(area.width / 759, area.height / 1551)
        let w = 759 * sc, h = 1551 * sc
        let box = CGRect(x: area.midX - w / 2, y: area.minY + (area.height - h) / 2, width: w, height: h)
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: box.minX + CGFloat(x - 207.5) * sc, y: box.minY + CGFloat(y - 584) * sc) }
        UIColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1).setFill(); UIBezierPath(roundedRect: box.insetBy(dx: -9, dy: -9), cornerRadius: 9).fill()
        UIColor(red: 0.13, green: 0.47, blue: 0.68, alpha: 1).setFill(); UIRectFill(box)
        UIColor.black.setFill()
        for p in PoolEngine.pockets { let c = pt(p.x, p.y); UIBezierPath(ovalIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)).fill() }
        let br = CGFloat(PoolEngine.R) * sc
        func poly(_ xy: [Double], _ col: UIColor, _ width: CGFloat, dash: Bool = false) {
            guard xy.count >= 4 else { return }
            let l = UIBezierPath(); l.move(to: pt(xy[0], xy[1]))
            var i = 2; while i + 1 < xy.count { l.addLine(to: pt(xy[i], xy[i + 1])); i += 2 }
            l.lineWidth = width; if dash { l.setLineDash([8, 6], count: 2, phase: 0) }
            col.setStroke(); l.stroke()
        }
        // suggested shot: gold
        if let s = v.shot {
            let cue = pt(s.cueX, s.cueY), g = pt(s.ghostX, s.ghostY)
            if let b = v.balls.first(where: { $0.id == s.ball }) {
                let p = PoolEngine.pockets[s.pocket]
                poly(PoolEngine.objectPath(b.x, b.y, gx: s.ghostX, gy: s.ghostY, balls: v.balls, skip: b.id, pocket: p), gold.withAlphaComponent(0.8), 3)
            }
            let l1 = UIBezierPath(); l1.move(to: cue); l1.addLine(to: g); l1.lineWidth = 3; gold.setStroke(); l1.stroke()
            let gr = UIBezierPath(ovalIn: CGRect(x: g.x - br, y: g.y - br, width: br * 2, height: br * 2)); gr.lineWidth = 2.5; gr.stroke()
            if s.placed {   // where to put the cue ball
                gold.withAlphaComponent(0.6).setFill(); UIBezierPath(ovalIn: CGRect(x: cue.x - br * 1.6, y: cue.y - br * 1.6, width: br * 3.2, height: br * 3.2)).fill()
            }
        }
        // your aim now: where the ball goes (green = drops, red = doesn't) and where the cue ball runs
        poly(v.objPath, v.pots ? green : red, 3)
        poly(v.cuePath, UIColor.white.withAlphaComponent(0.8), 2, dash: true)
        for b in v.balls {
            let c = pt(b.x, b.y), rr = CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)
            poolColours[b.id == 0 ? 0 : (b.id == 8 ? 8 : (b.id - 1) % 8 + 1)].setFill()
            UIBezierPath(ovalIn: rr).fill()
            if b.id >= 9 {   // stripe: white caps
                UIColor.white.setFill()
                UIBezierPath(ovalIn: rr).addClip()
                UIRectFill(CGRect(x: rr.minX, y: rr.minY, width: rr.width, height: rr.height * 0.28))
                UIRectFill(CGRect(x: rr.minX, y: rr.maxY - rr.height * 0.28, width: rr.width, height: rr.height * 0.28))
                UIGraphicsGetCurrentContext()?.resetClip()
            }
            if b.id != 0 && !v.legal.contains(b.id) {   // not yours: dimmed
                UIColor.black.withAlphaComponent(0.45).setFill(); UIBezierPath(ovalIn: rr).fill()
            }
            if let s = v.shot, s.ball == b.id { gold.setStroke(); let o = UIBezierPath(ovalIn: rr.insetBy(dx: -3, dy: -3)); o.lineWidth = 3; o.stroke() }
        }
        if let ax = v.aimX, let ay = v.aimY {
            let a = pt(ax, ay)
            (v.pots ? green : UIColor.white).setStroke()
            let c = UIBezierPath(ovalIn: CGRect(x: a.x - br, y: a.y - br, width: br * 2, height: br * 2)); c.lineWidth = 2.5; c.stroke()
        }
    }
}
