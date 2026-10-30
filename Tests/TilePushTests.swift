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
        XCTAssertEqual(r.popped, -1)
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

    /// never push onto a different face; a finished column is closed
    func testRules() {
        let g = [3, 4, 0, 0,
                 3, 0, 0, 0,
                 3, 0, 0, 0,
                 3, 0, 0, 0]
        XCTAssertFalse(TilePushEngine.allowed(g, 0, 3))
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

    /// thinking stays quick on an open board
    func testSpeed() {
        let t0 = Date()
        _ = e.think(mine: [Int](repeating: 0, count: 16), opp: noOpp, hand: 3)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
    }

    /// what the floating window shows for Atom's frame (written to Tests/out to look at)
    func testRenderWindow() throws {
        let cells = [3, 2, 4, 5, 0, 0, 0, 0, 0, 4, 1, 0, 0, 4, 1, 0] + [0, 1, 6, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 1, 1, 0] + [6]
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let shots: [(String, Overlay)] = [
            ("tp-move", Overlay(game: .tilePush, cells: cells, rec: 1, title: "ช่อง 2", line: "ลุ้นเล่นต่อ 48%", mine: true)),
            ("tp-wait", Overlay(game: .tilePush, cells: Array(cells[0..<32]) + [1], title: "รอ…", line: "ตาคู่แข่ง")),
        ]
        for (name, o) in shots {
            let img = UIGraphicsImageRenderer(size: Renderer.size).image { _ in Renderer.draw(o, in: CGRect(origin: .zero, size: Renderer.size)) }
            try img.pngData()!.write(to: out.appendingPathComponent(name + ".png"))
        }
    }
}
