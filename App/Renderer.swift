import UIKit
import CoreVideo

/// What the floating window shows.
struct Overlay: Equatable {
    var cells: [Int]?        // 64 cells or nil
    var rec: Int?            // 0..63 recommended cell
    var title: String        // big text, e.g. "G8"
    var line: String         // small text under it
    var mine: Bool = false   // gold accent when it's your move
    var footer: String = ""  // tiny diagnostics line
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
        let boardRect = CGRect(x: pad, y: pad, width: side, height: side)
        var textX = pad
        if let cells = o.cells, cells.count == 64 {
            textX = boardRect.maxX + 24
            feltLine.setFill(); UIBezierPath(roundedRect: boardRect, cornerRadius: 10).fill()
            let inset: CGFloat = 5, gap: CGFloat = 2
            let cs = (side - inset * 2 - gap * 7) / 8
            for r in 0..<8 { for c in 0..<8 {
                let cr = CGRect(x: boardRect.minX + inset + CGFloat(c) * (cs + gap),
                                y: boardRect.minY + inset + CGFloat(r) * (cs + gap), width: cs, height: cs)
                let v = cells[r * 8 + c]
                if v == 3 { hole.setFill() } else { felt.setFill() }
                UIBezierPath(roundedRect: cr, cornerRadius: 3).fill()
                if v == 1 || v == 2 {
                    (v == 1 ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1)).setFill()
                    UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.1, dy: cs * 0.1)).fill()
                }
                if o.rec == r * 8 + c {
                    gold.setStroke()
                    let p = UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.08, dy: cs * 0.08)); p.lineWidth = 4; p.stroke()
                    gold.withAlphaComponent(0.35).setFill(); UIBezierPath(ovalIn: cr.insetBy(dx: cs * 0.25, dy: cs * 0.25)).fill()
                }
            } }
        }
        let tw = rect.width - textX - pad
        let titleFont = UIFont.systemFont(ofSize: o.title.count <= 3 ? 110 : 44, weight: .heavy)
        let tAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: o.mine ? gold : ink]
        let tSize = (o.title as NSString).boundingRect(with: CGSize(width: tw, height: 200), options: .usesLineFragmentOrigin, attributes: tAttr, context: nil)
        let lAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: muted]
        let lSize = (o.line as NSString).boundingRect(with: CGSize(width: tw, height: 160), options: .usesLineFragmentOrigin, attributes: lAttr, context: nil)
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

    static func image(_ o: Overlay) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in draw(o, in: CGRect(origin: .zero, size: size)) }
    }
}
