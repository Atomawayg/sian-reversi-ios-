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
    /// every game uses the same wide window (a tall one covered the table)
    static func frameSize(_ o: Overlay) -> CGSize { size }
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
            case .tilePush: drawTilePush(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
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

    /// Tile Push: your map (faces as coloured numbered tiles), the tile in hand above it, an arrow over the column to tap.
    private static let tpFace: [UIColor] = [
        UIColor(red: 0.95, green: 0.78, blue: 0.22, alpha: 1), UIColor(red: 0.36, green: 0.62, blue: 0.95, alpha: 1),
        UIColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 1), UIColor(red: 0.90, green: 0.45, blue: 0.75, alpha: 1),
        UIColor(red: 0.98, green: 0.60, blue: 0.30, alpha: 1), UIColor(red: 0.70, green: 0.55, blue: 0.95, alpha: 1)]
    private static func drawTilePush(_ o: Overlay, _ cells: [Int], _ r: CGRect) {
        guard cells.count == TP.count else { return }
        let top: CGFloat = 70
        let (cs, cell, box) = grid(CGRect(x: r.minX, y: r.minY + top, width: r.width, height: r.height - top), cols: 4, rows: 4, inset: 4, gap: 3)
        panel.setFill(); UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
        // which faces you have: number them 1…4 in the order the reader saw them
        let codes = Array(Set(cells.filter { $0 >= 3 && $0 <= 8 })).sorted()
        func tile(_ v: Int, _ t: CGRect) {
            let p = UIBezierPath(roundedRect: t.insetBy(dx: 1, dy: 1), cornerRadius: 6)
            switch v {
            case 0: UIColor(red: 0.93, green: 0.48, blue: 0.22, alpha: 1).setFill(); p.fill()
            case 1: UIColor(white: 0.45, alpha: 1).setFill(); p.fill()
            case 2: UIColor(red: 0.25, green: 0.80, blue: 0.95, alpha: 1).setFill(); p.fill()
            case 9...: // a picture not known yet to be yours or theirs
                UIColor(white: 0.78, alpha: 1).setFill(); p.fill()
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: t.height * 0.42, weight: .heavy), .foregroundColor: bg]
                let txt = "?" as NSString, sz = txt.size(withAttributes: a)
                txt.draw(at: CGPoint(x: t.midX - sz.width / 2, y: t.midY - sz.height / 2), withAttributes: a)
            default:
                UIColor.white.setFill(); p.fill()
                let i = codes.firstIndex(of: v) ?? 0
                tpFace[i % tpFace.count].setFill()
                UIBezierPath(ovalIn: t.insetBy(dx: t.width * 0.16, dy: t.height * 0.16)).fill()
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: t.height * 0.42, weight: .heavy), .foregroundColor: bg]
                let txt = "\(i + 1)" as NSString, sz = txt.size(withAttributes: a)
                txt.draw(at: CGPoint(x: t.midX - sz.width / 2, y: t.midY - sz.height / 2), withAttributes: a)
            }
            if v == 2 {
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: t.height * 0.42, weight: .heavy), .foregroundColor: bg]
                let txt = "★" as NSString, sz = txt.size(withAttributes: a)
                txt.draw(at: CGPoint(x: t.midX - sz.width / 2, y: t.midY - sz.height / 2), withAttributes: a)
            }
        }
        for rr in 0..<4 { for c in 0..<4 { tile(cells[TP.mine + rr * 4 + c], cell(rr, c)) } }
        // the tile in hand, above the column to push it into (centred when there is no answer)
        let hand = cells[TP.hand]
        if hand == 2 || (hand >= 3 && hand <= 8) {
            let col = o.rec ?? -1
            let x = col >= 0 ? cell(0, col).midX : box.midX
            let ht = CGRect(x: x - cs * 0.4, y: r.minY + 2, width: cs * 0.8, height: cs * 0.8)
            tile(hand, ht)
            if col >= 0 {
                gold.setFill()
                let a = UIBezierPath()
                a.move(to: CGPoint(x: x - 12, y: ht.maxY + 4)); a.addLine(to: CGPoint(x: x + 12, y: ht.maxY + 4))
                a.addLine(to: CGPoint(x: x, y: box.minY - 2)); a.close(); a.fill()
                gold.setStroke()
                let hl = UIBezierPath(roundedRect: CGRect(x: cell(0, col).minX - 2, y: cell(0, col).minY - 2, width: cs + 4, height: cell(3, col).maxY - cell(0, col).minY + 4), cornerRadius: 7)
                hl.lineWidth = 4; hl.stroke()
            }
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
        let cr = CGFloat(SK.corner) * k   // the jar's rounded bottom corners (3.36)
        UIBezierPath(roundedRect: jarRect, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: cr, height: cr)).fill()
        UIColor.white.setStroke()
        let wall = UIBezierPath(roundedRect: jarRect.insetBy(dx: -2, dy: -2), byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: cr + 2, height: cr + 2)); wall.lineWidth = 3; wall.stroke()
        // how far Will can carry a fruit: the lid's opening (grey ticks above the jar)
        for xe in [SK.dropLeft, SK.dropRight] {
            let a = P(xe, SK.dropY - 40), b = P(xe, SK.dead)
            let t = UIBezierPath(); t.move(to: a); t.addLine(to: b); t.lineWidth = 2; UIColor.white.withAlphaComponent(0.5).setStroke(); t.stroke()
        }
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
            // solid and thick with a dark edge (3.36: the dashed line was hard to see on the small window)
            let line = UIBezierPath(); line.move(to: P(x, SK.dropY)); line.addLine(to: P(x, endY))
            line.lineCapStyle = .round
            line.lineWidth = 8; UIColor.black.withAlphaComponent(0.55).setStroke(); line.stroke()
            line.lineWidth = 5; gold.setStroke(); line.stroke()
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
struct PoolStop: Equatable { var x: Double; var y: Double; var pct: Int }
struct PoolView: Equatable {
    var balls: [PoolEngine.Ball]
    var shot: PoolEngine.Shot?                 // the suggested shot
    var next: PoolEngine.Shot? = nil           // the shot after it (from where the cue ball should stop)
    var cueEndX: Double? = nil, cueEndY: Double? = nil
    var aimX: Double? = nil, aimY: Double? = nil   // the game's aim circle now
    var objPath: [Double] = []                 // x,y pairs: where the ball you are aiming at goes
    var cuePath: [Double] = []                 // x,y pairs: where the cue ball goes after the hit (no spin)
    var pots = false                           // your current aim pots one of your balls
    var risky = false                          // it reaches a pocket but only just (off the jaw / a hair from missing)
    var bankX: Double? = nil, bankY: Double? = nil   // where the bank shot meets the cushion
    var win: PoolEngine.Window? = nil          // how far the cue may turn and still pot (for the zoom and the meter)
    var zoomPocket: Int? = nil
    var cueStops: [PoolStop] = []              // where the cue ball comes to rest for your aim (by power %)
    var objStops: [PoolStop] = []              // where the hit ball comes to rest (when it doesn't drop)
    var stopsLive = false                      // pulling: the one stop for your power (else marks for 25/50/75/100)
    var options: [PoolEngine.Shot] = []        // (no longer filled: see `found`)
    var found: [PoolEngine.Found] = []         // every sure pot from here: a thin line along the ball's way to its pocket
    var pick: PoolEngine.Found? = nil          // the one suggested: drawn in gold with the cue ball's way and where it stops
    var safe: PoolEngine.Safety? = nil         // no sure pot: the safety (gold), where both balls stop
    var objPathFull: [Double] = []             // your line at the power to use (always into the pocket when it drops)
    var powerTarget: Int? = nil, powerNow: Int? = nil
    var breakSpotX: Double? = nil, breakSpotY: Double? = nil
    var guides: [PoolEngine.Guide] = []        // from the ball you aim at to every pocket (straight and off one cushion)
    var spinX: Double? = nil, spinY: Double? = nil   // the clip's spin for this shot: where the red dot sits on the cue ball (−1…1, + = right / down)
    var guideMatch: Int? = nil                 // the one your line runs along (its pocket is the one zoomed)
    var guideLines: [[Double]] = []            // from the ball you aim at to every pocket (straight and one-cushion banks)   // the break: where to put the cue ball   // the power bar: where to pull to, and where you are
    var target: Int? = nil                     // the ball your aim hits
    var legal: [Int] = []
}

extension Renderer {
    private static let poolColours: [UIColor] = [
        .white, UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1), UIColor(red: 0.10, green: 0.35, blue: 0.95, alpha: 1),
        UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1), UIColor(red: 0.45, green: 0.15, blue: 0.65, alpha: 1),
        UIColor(red: 1.0, green: 0.50, blue: 0.10, alpha: 1), UIColor(red: 0.10, green: 0.65, blue: 0.20, alpha: 1),
        UIColor(red: 0.50, green: 0.12, blue: 0.10, alpha: 1), .black]

    /// The table upright on the left (as in the game), the shot in words on the right.
    static func drawPool(_ o: Overlay, _ v: PoolView, _ rect: CGRect) {
        let gold = UIColor(red: 0.949, green: 0.757, blue: 0.306, alpha: 1)
        let green = UIColor(red: 0.30, green: 0.95, blue: 0.45, alpha: 1), red = UIColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 1)
        let zoomAt = v.zoomPocket   // steadied in GameModel (the pocket your line ends at)
        let zoom = zoomAt != nil && v.aimX != nil
        let zs: CGFloat = min(200, rect.height - 24)   // the pocket close-up, big on the right while your line nears a pocket
        // table in the middle (the PiP's rounded corners hid the left pockets); text on the left, power bar beside the table, zoom far right
        let tabW = (rect.height - 32) * 759 / 1551
        let tabX = rect.width - zs - 12 - 26 - 24 - tabW - 16   // same spot with or without the zoom, so the table never jumps
        let area = CGRect(x: tabX, y: 16, width: tabW, height: rect.height - 32)
        let barW: CGFloat = 26, barX = area.maxX + 16
        let tx: CGFloat = 26, tw = area.minX - tx - 14
        let tAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: zoom ? 26 : 34, weight: .heavy), .foregroundColor: o.mine ? gold : UIColor.white]
        let tH = (o.title as NSString).boundingRect(with: CGSize(width: tw, height: 200), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil).height
        let lAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: zoom ? 18 : 22, weight: .semibold), .foregroundColor: UIColor(white: 0.8, alpha: 1)]
        let lH = (o.line as NSString).boundingRect(with: CGSize(width: tw, height: 200), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil).height
        let ty = max(8, (rect.height - tH - 10 - lH - (zoom ? 40 : 0)) / 2)
        (o.title as NSString).draw(with: CGRect(x: tx, y: ty, width: tw, height: tH), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil)
        (o.line as NSString).draw(with: CGRect(x: tx, y: ty + tH + 10, width: tw, height: lH), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil)
        if let sdx = v.spinX, let sdy = v.spinY {   // a little cue ball with the red dot where the clip put it
            let r: CGFloat = 30, c = CGPoint(x: tx + r + 4, y: min(rect.height - r - 10, ty + tH + 10 + lH + r + 12))
            UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
            let cross = UIBezierPath(); cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r)); cross.lineWidth = 1; UIColor(white: 0.7, alpha: 1).setStroke(); cross.stroke()
            let d = CGPoint(x: c.x + CGFloat(sdx) * r * 0.8, y: c.y + CGFloat(sdy) * r * 0.8)
            let ring = UIBezierPath(ovalIn: CGRect(x: d.x - 6, y: d.y - 6, width: 12, height: 12)); ring.lineWidth = 3
            UIColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1).setStroke(); ring.stroke()
        }
        let sc = min(area.width / 759, area.height / 1551)
        let w = 759 * sc, h = 1551 * sc
        let box = CGRect(x: area.midX - w / 2, y: area.minY + (area.height - h) / 2, width: w, height: h)
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: box.minX + CGFloat(x - 207.5) * sc, y: box.minY + CGFloat(y - 584) * sc) }
        UIColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1).setFill(); UIBezierPath(roundedRect: box.insetBy(dx: -6, dy: -6), cornerRadius: 6).fill()
        UIColor(red: 0.13, green: 0.47, blue: 0.68, alpha: 1).setFill(); UIRectFill(box)
        // the diamonds on the rails (as in the game), to aim banks by
        UIColor(red: 0.95, green: 0.80, blue: 0.55, alpha: 1).setFill()
        func dot(_ c: CGPoint) { UIBezierPath(ovalIn: CGRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4)).fill() }
        for k in 1...3 {
            let x = 203 + Double(k) * (975 - 203) / 4
            dot(CGPoint(x: pt(x, 584).x, y: box.minY - 3)); dot(CGPoint(x: pt(x, 584).x, y: box.maxY + 3))
        }
        for k in [1.0, 2, 3, 5, 6, 7] {
            let y = k < 4 ? 581 + k * (PoolEngine.midY - 581) / 4 : PoolEngine.midY + (k - 4) * (2140 - PoolEngine.midY) / 4
            dot(CGPoint(x: box.minX - 3, y: pt(207.5, y).y)); dot(CGPoint(x: box.maxX + 3, y: pt(207.5, y).y))
        }
        UIColor.black.setFill()
        for p in PoolEngine.pockets { let c = pt(p.x, p.y); UIBezierPath(ovalIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)).fill() }
        let br = CGFloat(PoolEngine.R) * sc
        func poly(_ xy: [Double], _ col: UIColor, _ width: CGFloat, dash: Bool = false) {
            guard xy.count >= 4 else { return }
            let l = UIBezierPath(); l.move(to: pt(xy[0], xy[1]))
            var i = 2; while i + 1 < xy.count { l.addLine(to: pt(xy[i], xy[i + 1])); i += 2 }
            l.lineWidth = width; if dash { l.setLineDash([8, 6], count: 2, phase: 0) }
            col.setStroke(); l.stroke()
        }
        // suggested shot: gold (faint while you are aiming, so your own line stands out)
        let aiming = v.aimX != nil
        // every sure pot: a thin line along the ball's way into the pocket, cushions included (the best per ball)
        var drawnBalls = Set<Int>()
        let thin = UIColor(red: 1.0, green: 0.45, blue: 0.35, alpha: aiming ? 0.25 : 0.8)
        // (thin lines for every sure pot were dropped in 3.21: the guide lines to every pocket cover it)
        _ = thin; _ = drawnBalls
        // the pick: the cue ball's way to the ball (gold), the ghost ring, the ball's way in, and where the cue ball stops
        // (while you aim only the "1" stays: your own line is the one to read)
        if let f = v.pick, !aiming {
            let col = gold
            poly(f.cuePts, col, 2)
            poly(f.objPts, col, 2)
            let g = pt(f.ghostX, f.ghostY)
            col.setStroke(); let gr = UIBezierPath(ovalIn: CGRect(x: g.x - br, y: g.y - br, width: br * 2, height: br * 2)); gr.lineWidth = 1.5; gr.stroke()
            if f.cueStop.count >= 2 {
                let e = pt(f.cueStop[f.cueStop.count - 2], f.cueStop[f.cueStop.count - 1])
                UIColor.white.setStroke(); let r = UIBezierPath(ovalIn: CGRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2)); r.lineWidth = 2; r.setLineDash([3, 3], count: 2, phase: 0); r.stroke()
            }
        }
        // the safety: the cue ball's way to the ball (gold), where the hit ball stops (dashed, small ring), and the cue
        // ball's stop as a solid gold ring — that ring and the ghost ring stay up while you aim, to line your ring up with
        if let sf = v.safe {
            if !aiming {
                poly(sf.cuePts, gold, 2)
                poly(sf.objPts, gold.withAlphaComponent(0.8), 1.5, dash: true)
                poly(sf.cueStop, UIColor.white.withAlphaComponent(0.7), 1.5, dash: true)
            }
            if sf.objPts.count >= 2 {
                let e = pt(sf.objPts[sf.objPts.count - 2], sf.objPts[sf.objPts.count - 1])
                gold.withAlphaComponent(0.8).setStroke(); let r = UIBezierPath(ovalIn: CGRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2)); r.lineWidth = 1.5; r.setLineDash([3, 3], count: 2, phase: 0); r.stroke()
            }
            let g = pt(sf.ghostX, sf.ghostY)
            gold.withAlphaComponent(aiming ? 0.7 : 1).setStroke(); let gr = UIBezierPath(ovalIn: CGRect(x: g.x - br, y: g.y - br, width: br * 2, height: br * 2)); gr.lineWidth = 1.5; gr.stroke()
            if sf.cueStop.count >= 2 {
                let e = pt(sf.cueStop[sf.cueStop.count - 2], sf.cueStop[sf.cueStop.count - 1])
                UIColor.black.withAlphaComponent(0.6).setStroke(); let r0 = UIBezierPath(ovalIn: CGRect(x: e.x - br - 1, y: e.y - br - 1, width: br * 2 + 2, height: br * 2 + 2)); r0.lineWidth = 4.5; r0.stroke()
                gold.setStroke(); let r = UIBezierPath(ovalIn: CGRect(x: e.x - br - 1, y: e.y - br - 1, width: br * 2 + 2, height: br * 2 + 2)); r.lineWidth = 2.5; r.stroke()
            }
        }
        let sg = aiming ? gold.withAlphaComponent(0.35) : gold
        if let s = v.shot {
            let cue = pt(s.cueX, s.cueY), g = pt(s.ghostX, s.ghostY)
            if let b = v.balls.first(where: { $0.id == s.ball }) {
                let p = PoolEngine.pockets[s.pocket]
                poly(PoolEngine.objectPath(b.x, b.y, gx: s.ghostX, gy: s.ghostY, balls: v.balls, skip: b.id, pocket: p), sg, 2.5, dash: s.bank)
            }
            let l1 = UIBezierPath(); l1.move(to: cue); l1.addLine(to: g); l1.lineWidth = 2.5; sg.setStroke(); l1.stroke()
            let gr = UIBezierPath(ovalIn: CGRect(x: g.x - br, y: g.y - br, width: br * 2, height: br * 2)); gr.lineWidth = 2.5; gr.stroke()
            if s.placed {   // where to put the cue ball
                gold.withAlphaComponent(0.6).setFill(); UIBezierPath(ovalIn: CGRect(x: cue.x - br * 1.6, y: cue.y - br * 1.6, width: br * 3.2, height: br * 3.2)).fill()
            }
        }
        // your aim now: where the ball goes (green = drops, red = doesn't) and where the cue ball runs
        let orange = UIColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1)
        // a dark edge under your lines so they stand out on the small table
        // every way the ball you aim at can reach a pocket: thin light lines
        // (guide lines to every pocket dropped in 3.22: Atom found them cluttered and of little use)
        // your line all the way in at the power to use (thin), then what your pull really reaches (bold)
        // main line (your ball's way) 3 px solid with a thin dark edge; everything else thin and dashed
        // guide lines (thin, coral): where the ball would have to go for each pocket; the one your line follows a bit bolder.
        // Your own line is the thick one with a dark edge: green drops, orange only just, white misses
        let guideCol = UIColor(red: 0.95, green: 0.45, blue: 0.38, alpha: 1)
        // (3.28: thicker, and they stay up between aims)
        // (3.33: Atom — no more thin lines to every pocket on the table; only the main line, or your own line when you aim
        // elsewhere. They are still worked out: they pick the pocket close-up, which still draws the one you follow.)
        _ = guideCol
        let mineCol = v.pots ? green : (v.risky ? orange : UIColor.white)
        poly(v.objPathFull, mineCol.withAlphaComponent(0.7), 2, dash: true)
        poly(v.objPath, UIColor.black.withAlphaComponent(0.7), 7.5)
        poly(v.objPath, mineCol, 4.5)
        if let bx = v.bankX, let by = v.bankY {   // where to hit the cushion: a gold mark on the rail by the diamonds
            let c = pt(bx, by)
            var m = c
            if abs(bx - PoolEngine.xMin) < 3 { m.x = box.minX - 3 } else if abs(bx - PoolEngine.xMax) < 3 { m.x = box.maxX + 3 }
            else if by < PoolEngine.midY { m.y = box.minY - 3 } else { m.y = box.maxY + 3 }
            gold.setFill(); UIBezierPath(ovalIn: CGRect(x: m.x - 5, y: m.y - 5, width: 10, height: 10)).fill()
        }
        // (the cue ball's way after the hit is not drawn any more: only where it stops — 3.28, Atom)
        // where the balls stop: while pulling a full ring for your power; before, small marks for 25/50/75/100
        func stop(_ s: PoolStop, _ col: UIColor) {
            let e = pt(s.x, s.y)
            let at: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: v.stopsLive ? 14 : 11, weight: .heavy), .foregroundColor: col,
                                                     .strokeColor: UIColor.black, .strokeWidth: -3]
            if v.stopsLive {
                col.setStroke(); let r = UIBezierPath(ovalIn: CGRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2)); r.lineWidth = 2; r.stroke()
                _ = at
            } else {
                UIColor.black.setFill(); UIBezierPath(ovalIn: CGRect(x: e.x - 4.5, y: e.y - 4.5, width: 9, height: 9)).fill()
                col.setFill(); UIBezierPath(ovalIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)).fill()
                ("\(s.pct)" as NSString).draw(at: CGPoint(x: e.x + 5, y: e.y - 7), withAttributes: at)
            }
        }
        for s in v.objStops { stop(s, v.pots ? green : (v.risky ? orange : red)) }
        for s in v.cueStops { stop(s, .white) }
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
                UIColor.black.withAlphaComponent(0.6).setFill(); UIBezierPath(ovalIn: rr).fill()
            } else if b.id != 0 {                        // yours: a white ring
                UIColor.white.setStroke(); let o = UIBezierPath(ovalIn: rr.insetBy(dx: -1.5, dy: -1.5)); o.lineWidth = 1.5; o.stroke()
            }
            if let s = v.shot, s.ball == b.id { gold.setStroke(); let o = UIBezierPath(ovalIn: rr.insetBy(dx: -3, dy: -3)); o.lineWidth = 3; o.stroke() }
        }
        // the plan: 1 and 2 on the balls, a ring where the cue ball should stop after shot 1
        func label(_ txt: String, _ b: PoolEngine.Ball) {
            let c = pt(b.x, b.y)
            let d: CGFloat = 22
            let at: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .black), .foregroundColor: UIColor.black]
            let r = CGRect(x: c.x + br - 4, y: c.y - br - d + 4, width: d, height: d)
            UIColor.black.setFill(); UIBezierPath(ovalIn: r.insetBy(dx: -2, dy: -2)).fill()
            gold.setFill(); UIBezierPath(ovalIn: r).fill()
            let sz = (txt as NSString).size(withAttributes: at)
            (txt as NSString).draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: at)
        }
        // the ball to play now: a "1" on it (only ever 1 — once it drops, the 1 moves to the next ball)
        if let f = v.pick, let b = v.balls.first(where: { $0.id == f.ball }) { label("1", b) }
        else if let sf = v.safe, let b = v.balls.first(where: { $0.id == sf.ball }) { label("1", b) }
        if let s = v.shot, let b = v.balls.first(where: { $0.id == s.ball }) { label("1", b) }
        if let n = v.next, let b = v.balls.first(where: { $0.id == n.ball }) { label("2", b) }
        if let ex = v.cueEndX, let ey = v.cueEndY, !aiming {
            let e = pt(ex, ey)
            UIColor.white.setStroke()
            let r = UIBezierPath(ovalIn: CGRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2)); r.lineWidth = 2; r.setLineDash([3, 3], count: 2, phase: 0); r.stroke()
        }
        if let bx = v.breakSpotX, let by = v.breakSpotY {
            let e = pt(bx, by)
            gold.setStroke(); let r = UIBezierPath(ovalIn: CGRect(x: e.x - br * 1.3, y: e.y - br * 1.3, width: br * 2.6, height: br * 2.6)); r.lineWidth = 3; r.stroke()
        }
        if let ax = v.aimX, let ay = v.aimY {
            let a = pt(ax, ay)
            (v.pots ? green : UIColor.white).setStroke()
            let c = UIBezierPath(ovalIn: CGRect(x: a.x - br, y: a.y - br, width: br * 2, height: br * 2)); c.lineWidth = 2.5; c.stroke()
        }
        // the power bar, like the game's: a cue stick in a slot, a gold mark where to pull to, white down to where you are
        if v.powerTarget != nil || v.powerNow != nil {
            let top = CGFloat(18), h = rect.height - 36
            let slot = CGRect(x: barX, y: top, width: barW, height: h)
            UIColor(white: 0.12, alpha: 0.9).setFill(); UIBezierPath(roundedRect: slot.insetBy(dx: -3, dy: -3), cornerRadius: 8).fill()
            // the stick: tip at the top, wood below
            let stick = CGRect(x: slot.midX - 3, y: slot.minY + 4, width: 6, height: h - 8)
            UIColor(red: 0.78, green: 0.58, blue: 0.33, alpha: 1).setFill(); UIBezierPath(roundedRect: stick, cornerRadius: 3).fill()
            UIColor(red: 0.42, green: 0.25, blue: 0.12, alpha: 1).setFill(); UIBezierPath(roundedRect: CGRect(x: stick.minX, y: stick.minY + stick.height * 0.62, width: stick.width, height: stick.height * 0.38), cornerRadius: 3).fill()
            UIColor.white.setFill(); UIRectFill(CGRect(x: stick.minX, y: stick.minY, width: stick.width, height: 6))
            func yAt(_ p: Int) -> CGFloat { slot.minY + CGFloat(max(0, min(100, p))) / 100 * h }
            if let n = v.powerNow {   // how far you have pulled
                UIColor.white.withAlphaComponent(0.35).setFill(); UIRectFill(CGRect(x: slot.minX, y: slot.minY, width: barW, height: yAt(n) - slot.minY))
                UIColor.white.setFill(); UIRectFill(CGRect(x: slot.minX - 4, y: yAt(n) - 1.5, width: barW + 8, height: 3))
            }
            if let p = v.powerTarget {   // pull to here
                let y = yAt(p), near = v.powerNow.map { abs($0 - p) <= 4 } ?? false
                (near ? green : gold).setFill()
                UIBezierPath(roundedRect: CGRect(x: slot.minX - 6, y: y - 3, width: barW + 12, height: 6), cornerRadius: 3).fill()
                let tri = UIBezierPath(); tri.move(to: CGPoint(x: slot.minX - 7, y: y)); tri.addLine(to: CGPoint(x: slot.minX - 15, y: y - 7)); tri.addLine(to: CGPoint(x: slot.minX - 15, y: y + 7)); tri.close(); tri.fill()
            }
        }
        if zoom, let k = zoomAt {
            drawPoolZoom(v, k, v.win?.pocket == k ? v.win : nil, CGRect(x: rect.width - zs - 12, y: (rect.height - zs) / 2, width: zs, height: zs), pots: v.pots, risky: v.risky)
        }
    }

    /// Close-up of the pocket your line goes to: cushion noses, jaws, the hole, the balls, your line, and (gold, dashed)
    /// the line through the middle of what drops.
    static func drawPoolZoom(_ v: PoolView, _ pocket: Int, _ win: PoolEngine.Window?, _ r: CGRect, pots: Bool, risky: Bool) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let h = PoolEngine.holes[pocket]
        // look from the hole a little into the table
        let side = pocket == 2 || pocket == 3
        let cx = h.x + (PoolEngine.midX - h.x) * (side ? 0.17 : 0.12)
        let cy = h.y + (PoolEngine.midY - h.y) * (side ? 0 : 0.06)
        let span = 230.0, sc = CGFloat(Double(r.width) / span)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.midX + CGFloat(x - cx) * sc, y: r.midY + CGFloat(y - cy) * sc) }
        ctx.saveGState()
        UIBezierPath(roundedRect: r, cornerRadius: 10).addClip()
        UIColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1).setFill(); UIRectFill(r)
        // felt: inside the noses (the corner channel included)
        UIColor(red: 0.13, green: 0.47, blue: 0.68, alpha: 1).setFill()
        UIRectFill(CGRect(origin: p(207.5, 584), size: CGSize(width: CGFloat(759) * sc, height: CGFloat(1551) * sc)))
        let felt = UIBezierPath()
        for s in PoolEngine.segs where s.jaw {
            felt.move(to: p(s.x1, s.y1)); felt.addLine(to: p(s.x2, s.y2))
        }
        felt.lineWidth = 2; UIColor(red: 0.95, green: 0.80, blue: 0.55, alpha: 1).setStroke()
        // the channel between the jaws is felt too
        UIColor(red: 0.13, green: 0.47, blue: 0.68, alpha: 1).setFill()
        let jaws = PoolEngine.segs.filter { $0.jaw && min(hypot($0.x1 - h.x, $0.y1 - h.y), hypot($0.x2 - h.x, $0.y2 - h.y)) < 120 }
        if jaws.count == 2 {
            let ch = UIBezierPath(); ch.move(to: p(jaws[0].x1, jaws[0].y1)); ch.addLine(to: p(jaws[0].x2, jaws[0].y2))
            ch.addLine(to: p(jaws[1].x2, jaws[1].y2)); ch.addLine(to: p(jaws[1].x1, jaws[1].y1)); ch.close(); ch.fill()
        }
        UIColor.black.setFill()
        let hr = CGFloat(side ? 39 : 45) * sc, hc = p(h.x, h.y)
        UIBezierPath(ovalIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2)).fill()
        felt.stroke()
        let noses = UIBezierPath()
        for s in PoolEngine.segs where !s.jaw { noses.move(to: p(s.x1, s.y1)); noses.addLine(to: p(s.x2, s.y2)) }
        noses.lineWidth = 2; noses.stroke()
        let br = CGFloat(PoolEngine.R) * sc
        // where the middle of the pocket is from the ball (gold dashed), and your line
        if let w = win, let t = v.target, let b = v.balls.first(where: { $0.id == t }) {
            let mid = PoolEngine.path(b.x, b.y, cos(w.centreDir), sin(w.centreDir), balls: v.balls, skip: b.id)
            let g = UIBezierPath(); g.move(to: p(mid[0], mid[1])); var i = 2; while i + 1 < mid.count { g.addLine(to: p(mid[i], mid[i + 1])); i += 2 }
            g.lineWidth = 2; g.setLineDash([6, 5], count: 2, phase: 0); UIColor(red: 0.95, green: 0.76, blue: 0.31, alpha: 1).setStroke(); g.stroke()
        }
        if let mi = v.guideMatch, mi < v.guides.count, v.guides[mi].pocket == pocket {
            let gp = v.guides[mi].pts
            let g = UIBezierPath(); g.move(to: p(gp[0], gp[1])); var i = 2; while i + 1 < gp.count { g.addLine(to: p(gp[i], gp[i + 1])); i += 2 }
            g.lineWidth = 1.5; UIColor(red: 0.95, green: 0.45, blue: 0.38, alpha: 1).setStroke(); g.stroke()
        }
        if v.objPath.count >= 4 {
            let l = UIBezierPath(); l.move(to: p(v.objPath[0], v.objPath[1])); var i = 2
            while i + 1 < v.objPath.count { l.addLine(to: p(v.objPath[i], v.objPath[i + 1])); i += 2 }
            l.lineWidth = 2
            (pots ? UIColor(red: 0.30, green: 0.95, blue: 0.45, alpha: 1) : (risky ? UIColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1) : UIColor.white)).setStroke(); l.stroke()
            // the ball where it ends up on your line
            let e = p(v.objPath[v.objPath.count - 2], v.objPath[v.objPath.count - 1])
            let o = UIBezierPath(ovalIn: CGRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2)); o.lineWidth = 2; o.stroke()
        }
        for b in v.balls {
            let c = p(b.x, b.y)
            if !r.insetBy(dx: -br, dy: -br).contains(c) { continue }
            (b.id == 0 ? UIColor.white : poolColours[b.id == 8 ? 8 : (b.id - 1) % 8 + 1]).setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)).fill()
        }
        ctx.restoreGState()
        UIColor(white: 1, alpha: 0.5).setStroke()
        let frame = UIBezierPath(roundedRect: r, cornerRadius: 10); frame.lineWidth = 1.5; frame.stroke()
    }

    /// A level: the green part is how far you may turn the cue and still pot, the white mark is your aim now.
    static func drawPoolMeter(_ w: PoolEngine.Window, _ r: CGRect) {
        let width = max(w.hi - w.lo, 0.3)
        let a = min(w.lo, 0) - width * 0.6, b = max(w.hi, 0) + width * 0.6
        func x(_ d: Double) -> CGFloat { r.minX + CGFloat((d - a) / (b - a)) * r.width }
        let barY = r.midY - 5
        UIColor(white: 1, alpha: 0.18).setFill()
        UIBezierPath(roundedRect: CGRect(x: r.minX, y: barY, width: r.width, height: 10), cornerRadius: 5).fill()
        // green: drops for sure; orange: only drops if the jaws are kind (nothing sure on this line)
        let zone = w.sure ? UIColor(red: 0.30, green: 0.95, blue: 0.45, alpha: 1) : UIColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1)
        zone.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: CGRect(x: x(w.lo), y: barY, width: max(3, x(w.hi) - x(w.lo)), height: 10), cornerRadius: 5).fill()
        let q = (w.hi - w.lo) / 4
        zone.setFill()
        UIBezierPath(roundedRect: CGRect(x: x(w.lo + q), y: barY, width: max(2, x(w.hi - q) - x(w.lo + q)), height: 10), cornerRadius: 5).fill()
        // your aim now
        let m = x(0)
        let tri = UIBezierPath(); tri.move(to: CGPoint(x: m, y: barY - 2)); tri.addLine(to: CGPoint(x: m - 8, y: barY - 14)); tri.addLine(to: CGPoint(x: m + 8, y: barY - 14)); tri.close()
        UIColor.white.setFill(); tri.fill()
        UIRectFill(CGRect(x: m - 1.5, y: barY - 2, width: 3, height: 14))
    }

}
