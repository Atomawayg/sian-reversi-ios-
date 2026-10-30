import XCTest
import UIKit
@testable import SianReversi

final class TilePushTests: XCTestCase {
    let e = TilePushEngine()
    let noOpp = [Int](repeating: 0, count: 16)

    /// Atom's frame 11:36: holding 😭, only the joker's column takes it
    func testOnlyJokerColumn() {
        let g = [3, 2, 4, 5, 0, 0, 0, 0, 0, 4, 1, 0, 0, 4, 1, 0]
        let opp = [0, 1, 6, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 1, 1, 0]
        let r = e.think(mine: g, opp: opp, hand: 6)
        XCTAssertEqual(r.col, 1)
        XCTAssertEqual(r.popped, 4)
    }

    /// three of a face on top: the fourth finishes the column
    func testFinishColumn() {
        let g = [3, 0, 4, 0,
                 3, 0, 0, 0,
                 3, 0, 0, 0,
                 0, 0, 0, 0]
        let r = e.think(mine: g, opp: noOpp, hand: 3)
        XCTAssertEqual(r.col, 0)
        XCTAssertTrue(r.completes)
    }

    /// a new face: prefer the empty column whose bottom tile is yours (you keep playing) over one with food at the bottom
    func testKeepTheTurn() {
        let g = [0, 0, 3, 4,
                 0, 0, 3, 4,
                 0, 0, 1, 1,
                 1, 5, 1, 1]
        let r = e.think(mine: g, opp: noOpp, hand: 6)
        XCTAssertEqual(r.col, 1)
        XCTAssertEqual(r.popped, 5)
        XCTAssertEqual(r.keep, 1)
    }

    /// never push onto a different face
    func testRules() {
        TilePushEngine.W = 4; TilePushEngine.H = 4
        let g = [3, 4, 0, 0,
                 3, 0, 0, 0,
                 3, 0, 0, 0,
                 3, 0, 0, 0]
        XCTAssertTrue(TilePushEngine.allowed(g, 0, 3), "a finished column still takes its own face")
        XCTAssertFalse(TilePushEngine.allowed(g, 1, 3))
        XCTAssertTrue(TilePushEngine.allowed(g, 1, 4))
        XCTAssertTrue(TilePushEngine.allowed(g, 1, 2))
        XCTAssertTrue(TilePushEngine.allowed(g, 2, 3))
        let (n, out) = TilePushEngine.push(g, 1, 4)
        XCTAssertEqual(TilePushEngine.colCells(n, 1), [4, 4, 0, 0])
        XCTAssertEqual(out, 0)
    }

    /// the joker on hand goes where it finishes a column
    func testJokerFinishes() {
        let g = [4, 3, 0, 0,
                 4, 3, 0, 0,
                 0, 3, 0, 0,
                 0, 1, 0, 0]
        let r = e.think(mine: g, opp: noOpp, hand: 2)
        XCTAssertEqual(r.col, 1)
        XCTAssertTrue(r.completes)
    }

    /// a picture not known yet at the bottom: even odds to keep playing
    func testUnknownBottom() {
        let g = [0, 3, 4, 5,
                 0, 0, 0, 0,
                 0, 0, 0, 0,
                 9, 1, 1, 1]
        let r = e.think(mine: g, opp: noOpp, hand: 6)
        XCTAssertEqual(r.col, 0)
        XCTAssertEqual(r.keep, 0.5)
    }

    /// 5 wide × 4 high (Atom's 13:32): holding 😈 goes on the 😈 column
    func testFiveWide() {
        let g = [3, 4, 5, 6, 7,
                 0, 4, 0, 6, 7,
                 0, 2, 0, 6, 0,
                 0, 0, 0, 0, 0]
        let r = e.think(mine: g, opp: [Int](repeating: 0, count: 20), hand: 7, cols: 5, rows: 4)
        XCTAssertEqual(r.col, 4)
        let r2 = e.think(mine: g, opp: [Int](repeating: 0, count: 20), hand: 6, cols: 5, rows: 4)
        XCTAssertEqual(r2.col, 3)
        XCTAssertTrue(r2.completes || r2.col == 3)
    }

    /// 3×3: the third of a picture finishes the column
    func testThreeByThree() {
        let g = [3, 4, 0,
                 3, 0, 0,
                 0, 0, 0]
        let r = e.think(mine: g, opp: [Int](repeating: 0, count: 9), hand: 3, cols: 3, rows: 3)
        XCTAssertEqual(r.col, 0)
        XCTAssertTrue(r.completes)
    }

    /// Atom's 14:20: holding coffee, coffee ×3 + joker in the first column, nothing else takes coffee.
    /// Pushing it there keeps the column whole and gives the joker back (play on).
    func testPushIntoFinishedColumn() {
        let g = [3, 4, 5, 9, 6,
                 3, 4, 5, 0, 6,
                 3, 4, 0, 0, 6,
                 2, 4, 0, 1, 0]
        let r = e.think(mine: g, opp: [Int](repeating: 0, count: 20), hand: 3, cols: 5, rows: 4)
        XCTAssertEqual(r.col, 0)
        XCTAssertEqual(r.popped, 2)
        XCTAssertTrue(r.completes)
    }

    /// thinking stays quick on an open board
    func testSpeed() {
        let t0 = Date()
        _ = e.think(mine: [Int](repeating: 0, count: 16), opp: noOpp, hand: 3)
        _ = e.think(mine: [Int](repeating: 0, count: 20), opp: [Int](repeating: 0, count: 20), hand: 3, cols: 5, rows: 4)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
    }

    /// what the floating window shows for Atom's frame (written to Tests/out to look at)
    func testRenderWindow() throws {
        let cells = TP.pack(cols: 4, rows: 4, mine: [9, 2, 4, 5, 0, 0, 0, 0, 0, 4, 1, 0, 0, 4, 1, 0],
                            opp: [0, 1, 6, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 1, 1, 0], hand: 6)
        let five = TP.pack(cols: 5, rows: 4, mine: [3, 4, 5, 6, 7, 0, 4, 0, 6, 7, 0, 2, 0, 6, 0, 0, 0, 0, 0, 0], opp: [Int](repeating: 0, count: 20), hand: 7)
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let shots: [(String, Overlay)] = [
            ("tp-move", Overlay(game: .tilePush, cells: cells, rec: 1, title: "ช่อง 2", line: "ได้เล่นต่อแน่\nกำลังจำไพ่", mine: true)),
            ("tp-wait", Overlay(game: .tilePush, cells: Array(cells.prefix(TP.hand)) + [1], title: "รอ…", line: "ตาคู่แข่ง")),
            ("tp-five", Overlay(game: .tilePush, cells: five, rec: 4, title: "ช่อง 5", line: "ลุ้นเล่นต่อ 40%", mine: true)),
        ]
        for (name, o) in shots {
            let img = UIGraphicsImageRenderer(size: Renderer.size).image { _ in Renderer.draw(o, in: CGRect(origin: .zero, size: Renderer.size)) }
            try img.pngData()!.write(to: out.appendingPathComponent(name + ".png"))
        }
    }
}
