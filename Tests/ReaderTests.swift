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

    /// Atom's screenshots 26 Oct 21:35/21:36: Will holds a cherry; the jar has one strawberry and one cherry (and two grapes)
    func testHeldCherryAndJar() throws {
        for (name, grapes) in [("suika-2135.png", 0), ("suika-2136.png", 2)] {
            let st = SK.decode(BoardReader.readSuika(try sampler(name)).cells)!
            print("READER \(name): held \(st.held) next \(st.next) jar", st.fruits.map { "\($0.t):\(Int($0.x)),\(Int($0.y))" })
            XCTAssertEqual(st.held, 0, "\(name) held")
            XCTAssertEqual(st.fruits.filter { $0.t == 1 }.count, 1, "\(name) strawberries")
            XCTAssertEqual(st.fruits.filter { $0.t == 0 }.count, 1, "\(name) cherries")
            XCTAssertEqual(st.fruits.filter { $0.t == 2 }.count, grapes, "\(name) grapes")
            XCTAssertEqual(st.next, 1, "\(name) next")
        }
    }

    /// every saved screenshot against Atom's counts by hand (Tools/suika/truth.json), the fruit Will holds left out
    func testAllFramesMatchHandCounts() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Tools/suika/truth.json")
        let truth = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [Int]]
        var total = 0
        for (name, want) in truth.sorted(by: { $0.key < $1.key }) {
            let st = SK.decode(BoardReader.readSuika(try sampler(name)).cells)!
            let got = (0..<SK.types).map { t in st.fruits.filter { $0.t == t }.count }
            let err = zip(got, want).map { abs($0 - $1) }.reduce(0, +); total += err
            print("READER \(name) err \(err) got \(got) want \(want)")
        }
        XCTAssertLessThanOrEqual(total, 5, "fruits misread across the saved screenshots (5 of ~350: cherries almost hidden behind a big fruit)")
    }
}

/// Tile Push: frames from Atom's recording of 30 Oct (11:36)
final class TilePushReaderTests: XCTestCase {
    func testFrames() throws {
        let rt = ReaderTests()
        // your move, holding 😭: the faces 😂 joker 😇 😤 on top, two 😇 lower down beside cheese and a skewer
        let a = BoardReader.read(try rt.sampler("tp-030.png"))
        print("TP 030", a.game, a.cells, a.myTurn)
        XCTAssertEqual(a.game, .tilePush)
        XCTAssertEqual(Array(a.cells[0..<16]), [3, 2, 4, 5, 0, 0, 0, 0, 0, 4, 1, 0, 0, 4, 1, 0])
        XCTAssertEqual(Array(a.cells[16..<32]), [0, 1, 6, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 1, 1, 0])
        XCTAssertEqual(a.cells[32], 6)
        XCTAssertTrue(a.myTurn)
        let b = BoardReader.read(try rt.sampler("tp-060.png"))
        print("TP 060", b.game, b.cells, b.myTurn)
        XCTAssertEqual(b.game, .tilePush)
        XCTAssertEqual(Array(b.cells[0..<16]), [3, 4, 5, 6, 0, 2, 5, 0, 0, 0, 0, 0, 0, 5, 1, 0])
        XCTAssertFalse(b.myTurn)
        let c = BoardReader.read(try rt.sampler("tp-176.png"))
        print("TP 176", c.game, c.cells, c.myTurn)
        XCTAssertEqual(Array(c.cells[0..<16]), [3, 4, 5, 6, 3, 4, 5, 6, 3, 4, 5, 2, 3, 4, 5, 6])
        // other games' screenshots are not Tile Push
        for f in ["suika-1952.png"] { XCTAssertFalse(BoardReader.looksLikeTilePush(try rt.sampler(f)), f) }
    }
}
