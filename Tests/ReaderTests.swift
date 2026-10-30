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
    /// the reader learns from steady frames: read the same frame a few times, like the screen recording does
    func steady(_ s: BoardReader.Sampler, _ n: Int = 5) -> BoardMessage {
        var m = BoardReader.read(s)
        for _ in 1..<n { m = BoardReader.read(s) }
        return m
    }

    func testFrames() throws {
        let rt = ReaderTests()
        BoardReader.tpReset()
        // your move (2 s left), holding 😭: 😂 joker 😇 😤 on top, two 😇 lower down beside cheese and a skewer
        let a = steady(try rt.sampler("tp-030.png"))
        print("TP 030", a.game, a.valid, a.cells, a.myTurn)
        XCTAssertEqual(a.game, .tilePush)
        let t = try XCTUnwrap(TP.unpack(a.cells))
        XCTAssertEqual(t.w, 4); XCTAssertEqual(t.h, 4)
        let c = t.mine, o = t.opp
        XCTAssertEqual(t.hand, 3, "😭 in hand on your turn is yours")
        XCTAssertTrue(a.myTurn)
        XCTAssertEqual(c[1], 2, "joker")
        for i in [4, 5, 6, 7, 8, 11, 12, 15] { XCTAssertEqual(c[i], 0, "face down \(i)") }
        XCTAssertEqual(c[9], c[13], "two 😇")
        XCTAssertEqual(c[2], c[9], "😇 on top too")
        XCTAssertNotEqual(c[10], c[9], "cheese is not 😇")
        XCTAssertEqual(o[2], 3, "😭 in the opponent's map")
        XCTAssertEqual(o[6], 3)
        XCTAssertEqual(c[10], o[1], "cheese in both maps")
        XCTAssertEqual(Set([c[0], c[2], c[3], c[10], c[14]]).count, 5, "five different pictures")

        // the opponent's move: not yours
        let b = steady(try rt.sampler("tp-060.png"))
        print("TP 060", b.valid, b.cells, b.myTurn)
        let tb = try XCTUnwrap(TP.unpack(b.cells))
        XCTAssertFalse(b.myTurn)
        XCTAssertEqual(tb.mine[1], 3, "😭 pushed into the joker's column")
        XCTAssertEqual(tb.mine[5], 2, "joker one down")

        let e = steady(try rt.sampler("tp-176.png"))
        let te = try XCTUnwrap(TP.unpack(e.cells))
        for c4 in 0..<4 { XCTAssertEqual(Set((0..<4).map { te.mine[$0 * 4 + c4] }.filter { $0 != 2 }).count, 1, "column \(c4) one picture") }

        // Atom's screenshot 12:59 (other pictures: food for him, animals for the opponent): the YOUR TURN banner is up
        let f = try rt.sampler("tp-banner.png")
        XCTAssertTrue(BoardReader.looksLikeTilePush(f))
        XCTAssertTrue(BoardReader.tpBanner(f))
        XCTAssertFalse(BoardReader.tpBanner(try rt.sampler("tp-030.png")))
        XCTAssertFalse(BoardReader.looksLikeTilePush(try rt.sampler("suika-1952.png")))
    }

    /// Atom's screenshots 13:32: a 5 wide × 4 high map (five pictures each)
    func testFiveWide() throws {
        let rt = ReaderTests()
        BoardReader.tpReset()
        // holding 😈 on your turn (3 s): 🤑 🤓 😤 😭 😈 on top; 🤓 😭 😈 below; joker under 🤓, 😭 under that
        let a = steady(try rt.sampler("tp5-c.png"))
        print("TP5 c", a.valid, a.cells, a.myTurn)
        let t = try XCTUnwrap(TP.unpack(a.cells))
        XCTAssertEqual(t.w, 5); XCTAssertEqual(t.h, 4)
        let c = t.mine
        XCTAssertTrue(a.myTurn)
        XCTAssertEqual(t.hand, c[4], "😈 in hand = 😈 on top")
        XCTAssertEqual(c[9], c[4])
        XCTAssertEqual(c[6], c[1], "🤓")
        XCTAssertEqual(c[8], c[3], "😭"); XCTAssertEqual(c[13], c[3])
        XCTAssertEqual(c[11], 2, "joker")
        for i in [5, 7, 10, 12, 14, 15, 16, 17, 18, 19] { XCTAssertEqual(c[i], 0, "face down \(i)") }
        XCTAssertEqual(Set(c[0..<5]).count, 5)
        // next screenshot: holding >_< — two of each on top
        let b = steady(try rt.sampler("tp5-d.png"))
        print("TP5 d", b.valid, b.cells, b.myTurn)
        let u = try XCTUnwrap(TP.unpack(b.cells))
        XCTAssertEqual(u.w, 5)
        for k in 0..<5 { XCTAssertEqual(u.mine[k], u.mine[5 + k], "column \(k)") }
        XCTAssertEqual(u.hand, u.mine[2])
    }

    /// Atom's first clip (11:31): a 3×3 map
    func testThreeByThree() throws {
        let rt = ReaderTests()
        BoardReader.tpReset()
        let s = try rt.sampler("tp3-005.png")
        XCTAssertTrue(BoardReader.looksLikeTilePush(s))
        XCTAssertEqual(BoardReader.tpSize(s).cols, 3); XCTAssertEqual(BoardReader.tpSize(s).rows, 3)
        let a = steady(s)
        print("TP3", a.valid, a.cells, a.myTurn)
        let t = try XCTUnwrap(TP.unpack(a.cells))
        XCTAssertEqual(t.w, 3); XCTAssertEqual(t.h, 3)
        for k in 0..<3 { XCTAssertEqual(t.mine[k], t.mine[3 + k], "column \(k)") }
    }
}
