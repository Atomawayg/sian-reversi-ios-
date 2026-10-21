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

    init(game: GameKind = .reversi, cells: [Int]? = nil, rec: Int? = nil, path: [Int] = [], caps: [Int] = [],
         title: String, line: String, mine: Bool = false, meColor: Int = 1) {
        self.game = game; self.cells = cells; self.rec = rec; self.path = path; self.caps = caps
        self.title = title; self.line = line; self.mine = mine; self.meColor = meColor
    }
}

enum Renderer {
    static let size = CGSize(width: 640, height: 360)

    private static let bg = UIColor(red: 0.055, green: 0.078, blue: 0.067, alpha: 1)
    private static let felt = UIColor(red: 0.118, green: 0.416, blue: 0.271, alpha: 1)
    private static let feltLine = UIColor(red: 0.059, green: 0.239, blue: 0.153, alpha: 1)
    private static let gold = UIColor(red: 0.957, green: 0.776, blue: 0.310, alpha: 1)
    private static let ink = UIColor(red: 0.914, green: 0.941, blue: 0.918, alpha: 1)
    private static let muted = UIColor(red: 0.561, green: 0.635, blue: 0.596, alpha: 1)
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
        if let cells = o.cells, !cells.isEmpty {
            switch o.game {
            case .reversi: drawReversi(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .checkers: drawCheckers(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
            case .connect4, .connect5: drawConnect(o, cells, CGRect(x: pad, y: pad, width: side, height: side))
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

    static func image(_ o: Overlay) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in draw(o, in: CGRect(origin: .zero, size: size)) }
    }
}
