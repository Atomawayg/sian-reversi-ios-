import XCTest
import UIKit

/// The screen reader on saved screenshots (compiled into this test target with the Broadcast and Shared sources).
final class ReaderTests: XCTestCase {
    func sampler(_ name: String) throws -> BoardReader.Sampler {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("frames/" + name)
        guard let img = UIImage(contentsOfFile: url.path)?.cgImage else { throw XCTSkip("no frame \(name)") }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = px
        return BoardReader.Sampler(w: w, h: h) { x, y in
            let i = (max(0, min(h - 1, y)) * w + max(0, min(w - 1, x))) * 4
            return (Double(data[i]), Double(data[i + 1]), Double(data[i + 2]))
        }
    }

    /// Atom's screenshot 26 Oct 19:52: 6 strawberries and 4 cherries in the jar (the reader used to call most strawberries cherries)
    func testStrawberriesAreNotCherries() throws {
        let s = try sampler("suika-1952.png")
        XCTAssertTrue(BoardReader.looksLikeSuika(s))
        let st = SK.decode(BoardReader.readSuika(s).cells)!
        let n = (0..<SK.types).map { t in st.fruits.filter { $0.t == t }.count }
        print("READER counts by kind:", n, st.fruits.map { "\($0.t):\(Int($0.x)),\(Int($0.y))" }.joined(separator: " "))
        XCTAssertGreaterThanOrEqual(n[1], 5, "strawberries")
        XCTAssertLessThanOrEqual(n[0], 5, "cherries")
    }
}
