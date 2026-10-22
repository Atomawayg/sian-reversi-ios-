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

    init(game: GameKind = .reversi, cells: [Int]? = nil, rec: Int? = nil, path: [Int] = [], caps: [Int] = [],
         title: String, line: String, mine: Bool = false, meColor: Int = 1) {
        self.game = game; self.cells = cells; self.rec = rec; self.path = path; self.caps = caps
        self.title = title; self.line = line; self.mine = mine; self.meColor = meColor
    }
}

enum Renderer {
    static let size = CGSize(width: 640, height: 360)

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

    private static func drawJackaroo(_ o: Overlay, _ cells: [Int], _ rect: CGRect) {
        let pad: CGFloat = 14
        let side = rect.height - pad * 2
        let box = CGRect(x: pad, y: pad, width: side, height: side)
        let cx = JKGeo.center.0, cy = JKGeo.center.1, span = 1120.0
        let k = Double(side) / span
        let map = { (x: Double, y: Double) -> CGPoint in
            CGPoint(x: Double(box.midX) + (x - cx) * k, y: Double(box.midY) + (y - cy) * k)
        }
        UIColor(red: 0.86, green: 0.70, blue: 0.47, alpha: 1).setFill()
        UIBezierPath(ovalIn: box.insetBy(dx: 2, dy: 2)).fill()
        let r = CGFloat(15 * k)
        func dot(_ p: CGPoint, _ c: Int, _ big: Bool) {
            let rr = c == 0 ? r * 0.55 : r * (big ? 1.0 : 0.95)
            jkColours[c].setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)).fill()
        }
        // start squares in seat colour
        for s in 0..<4 {
            let c = cells[JK.seats + s]
            let p = map(JKGeo.track[19 * s].0, JKGeo.track[19 * s].1)
            (c > 0 ? jkColours[c] : UIColor.gray).withAlphaComponent(0.7).setStroke()
            let sq = UIBezierPath(roundedRect: CGRect(x: p.x - r * 1.3, y: p.y - r * 1.3, width: r * 2.6, height: r * 2.6), cornerRadius: 3)
            sq.lineWidth = 2; sq.stroke()
        }
        for t in 0..<76 { let p = JKGeo.track[t]; dot(map(p.0, p.1), cells[JK.track + t], true) }
        for s in 0..<4 { for q in 0..<4 {
            let l = JKGeo.lanes[s][q]; dot(map(l.0, l.1), cells[JK.lanes + 4 * s + q], true)
            let h = JKGeo.homes[s][q]; dot(map(h.0, h.1), cells[JK.homes + 4 * s + q], false)
        } }
        // the suggested move
        var i = 0
        while i + 1 < o.arrows.count {
            let a = jkPoint(o.arrows[i], map), b = jkPoint(o.arrows[i + 1], map)
            let path = UIBezierPath(); path.move(to: a); path.addLine(to: b)
            path.lineWidth = 6; path.lineCapStyle = .round
            arrow.setStroke(); path.stroke()
            gold.setStroke()
            let ra = UIBezierPath(ovalIn: CGRect(x: a.x - r * 1.6, y: a.y - r * 1.6, width: r * 3.2, height: r * 3.2)); ra.lineWidth = 4; ra.stroke()
            let rb = UIBezierPath(ovalIn: CGRect(x: b.x - r * 1.7, y: b.y - r * 1.7, width: r * 3.4, height: r * 3.4)); rb.lineWidth = 4
            rb.setLineDash([5, 4], count: 2, phase: 0); rb.stroke()
            // arrow head
            let ang = atan2(b.y - a.y, b.x - a.x), hl: CGFloat = 14
            let head = UIBezierPath()
            head.move(to: b)
            head.addLine(to: CGPoint(x: b.x - hl * cos(ang - 0.5), y: b.y - hl * sin(ang - 0.5)))
            head.addLine(to: CGPoint(x: b.x - hl * cos(ang + 0.5), y: b.y - hl * sin(ang + 0.5)))
            head.close(); arrow.setFill(); head.fill()
            i += 2
        }

        // right side: the card to play, big, then plain instructions
        let tx = box.maxX + 22
        let tw = rect.width - tx - 14
        if o.pick >= 0 && o.pick < o.hand.count {
            let cardRect = CGRect(x: tx, y: 18, width: 96, height: 132)
            UIColor.white.setFill()
            let cp = UIBezierPath(roundedRect: cardRect, cornerRadius: 12); cp.fill()
            gold.setStroke(); cp.lineWidth = 6; cp.stroke()
            let rank = o.hand[o.pick]
            let rAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: rank.count > 1 ? 54 : 70, weight: .heavy), .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            let rs = (rank as NSString).size(withAttributes: rAttr)
            (rank as NSString).draw(at: CGPoint(x: cardRect.midX - rs.width / 2, y: cardRect.midY - rs.height / 2), withAttributes: rAttr)
            // which card in your hand
            let hx = cardRect.maxX + 14
            let small = CGSize(width: 22, height: 30)
            let cols = max(1, Int((rect.width - hx - 10) / (small.width + 5)))
            for (j, h) in o.hand.enumerated() where j < cols {
                let rr = CGRect(x: hx + CGFloat(j) * (small.width + 5), y: 22, width: small.width, height: small.height)
                (j == o.pick ? gold : UIColor(white: 0.85, alpha: 1)).setFill()
                UIBezierPath(roundedRect: rr, cornerRadius: 4).fill()
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: UIColor.black]
                let sz = (h as NSString).size(withAttributes: a)
                (h as NSString).draw(at: CGPoint(x: rr.midX - sz.width / 2, y: rr.midY - sz.height / 2), withAttributes: a)
            }
            let tAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: muted]
            ("ใบที่ \(o.pick + 1) จากซ้าย" as NSString).draw(at: CGPoint(x: hx, y: 60), withAttributes: tAttr)
        }
        let topY: CGFloat = o.pick >= 0 ? 164 : 60
        let t1: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: o.title.count > 12 ? 30 : 38, weight: .heavy), .foregroundColor: o.mine ? gold : ink]
        let s1 = (o.title as NSString).boundingRect(with: CGSize(width: tw, height: 120), options: .usesLineFragmentOrigin, attributes: t1, context: nil)
        (o.title as NSString).draw(with: CGRect(x: tx, y: topY, width: tw, height: s1.height), options: .usesLineFragmentOrigin, attributes: t1, context: nil)
        let t2: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: muted]
        (o.line as NSString).draw(with: CGRect(x: tx, y: topY + s1.height + 6, width: tw, height: rect.height - topY - s1.height - 10), options: .usesLineFragmentOrigin, attributes: t2, context: nil)
        if !o.footer.isEmpty {
            let fAttr: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: muted.withAlphaComponent(0.6)]
            (o.footer as NSString).draw(at: CGPoint(x: tx, y: rect.height - 16), withAttributes: fAttr)
        }
    }

    static func image(_ o: Overlay) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in draw(o, in: CGRect(origin: .zero, size: size)) }
    }
}
