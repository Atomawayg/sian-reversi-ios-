import XCTest
import UIKit
@testable import SianReversi

/// Replays Atom's pool logs (Tests/logs/*.txt) through the app at their real pace and writes what the PiP shows:
/// a text trail of every change (Tests/out/<log>.txt) and a picture at each change (Tests/out/<log>/NNN.png).
final class PoolReplayTests: XCTestCase {
    func testReplayLogs() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let logs = try FileManager.default.contentsOfDirectory(at: here.appendingPathComponent("logs"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" && !$0.lastPathComponent.hasPrefix("suika") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let out = here.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["REPLAY_ONLY"] ?? ""
        if only == "none" { return }
        for url in logs where only.isEmpty || url.lastPathComponent.contains(only) {
            UserDefaults.standard.removeObject(forKey: "poolBook")
            try replay(url, out)
        }
    }

    /// the fruit log's checks: a merge is not a loss, a pushed fruit is not a loss, a vanished one is; the real count survives
    func testSuikaLost() {
        let before = [SK.Fruit(t: 2, x: 300, y: 2200), SK.Fruit(t: 2, x: 430, y: 2200), SK.Fruit(t: 5, x: 800, y: 2150)]
        // the two grapes merged into a dekopon, the apple stayed
        XCTAssertEqual(GameModel.skLost(before, [SK.Fruit(t: 3, x: 365, y: 2240), SK.Fruit(t: 5, x: 800, y: 2150)]).count, 0)
        // the apple was pushed 150 px
        XCTAssertEqual(GameModel.skLost(before, [SK.Fruit(t: 2, x: 300, y: 2200), SK.Fruit(t: 2, x: 430, y: 2200), SK.Fruit(t: 5, x: 950, y: 2150)]).count, 0)
        // the apple vanished
        XCTAssertEqual(GameModel.skLost(before, [SK.Fruit(t: 2, x: 300, y: 2200), SK.Fruit(t: 2, x: 430, y: 2200)]).map { $0.t }, [5])
        let many = (0..<45).map { SK.Fruit(t: 0, x: 150 + Double($0 % 12) * 70, y: 1500 + Double($0 / 12) * 70) }
        let st = SK.decode(SK.encode(held: 1, heldX: 500, next: 2, fruits: many))!
        XCTAssertEqual(st.total, 45); XCTAssertEqual(st.fruits.count, SK.maxFruits)
    }

    /// Atom's fruit log, with the held fruit flicking cherry/strawberry as it did on the phone: the suggestion must not
    /// jump while the jar stays the same. Writes the trail to Tests/out/suika.txt.
    func testSuikaReplay() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let text = try String(contentsOf: here.appendingPathComponent("logs/suika-1627.txt"), encoding: .utf8)
        let model = GameModel()
        var trail = "", jumps = 0, jars = 0
        var lastJar: [Int] = [], lastDrop: Int? = nil
        func send(_ held: Int, _ next: Int, _ fruits: [SK.Fruit], x: Double) {
            let c = SK.encode(held: held, heldX: x, next: next, fruits: fruits)
            model.replaySuika(BoardMessage(valid: true, game: .suika, cells: c, me: 1, myTurn: held >= 0))
        }
        for raw in text.split(separator: "\n") where raw.dropFirst(11).hasPrefix("S ") {
            func field(_ k: String) -> Substring? { raw.range(of: " " + k + "=").map { r in raw[r.upperBound...].prefix { $0 != " " } } }
            let held = Int(field("held") ?? "-1") ?? -1, next = Int(field("next") ?? "-1") ?? -1
            var fruits: [SK.Fruit] = []
            if let r = raw.range(of: "jar=") {
                for tok in raw[r.upperBound...].split(separator: " ") {
                    let p = tok.split(separator: ":"); guard p.count == 2, let t = Int(p[0]) else { continue }
                    let xy = p[1].split(separator: ","); guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { continue }
                    fruits.append(SK.Fruit(t: t, x: x, y: y))
                }
            }
            let jarKey = GameModel.skJarOnly(SK.encode(held: 0, heldX: 500, next: 0, fruits: fruits))
            let sameJar = lastJar.count == jarKey.count && SK.same(lastJar, jarKey, tol: 3)
            if !sameJar { jars += 1; lastDrop = nil }
            // 20 readings while the finger drags across, the held fruit misread on every fourth, then a moment unseen
            for k in 0..<20 {
                let h = k % 4 == 3 && held <= 1 ? 1 - held : held
                send(k == 10 ? -1 : h, next, fruits, x: 200 + Double(k) * 30)
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let d = model.overlay.drop
            if sameJar, let a = lastDrop, let b = d, abs(a - b) > 20 { jumps += 1; trail += "JUMP " }
            if d != nil { lastDrop = d }
            trail += String(raw.prefix(10)) + " held=\(held) drop=\(d.map(String.init) ?? "-") title=\(model.overlay.title)\n"
            lastJar = jarKey
        }
        trail += "jars=\(jars) jumps=\(jumps)\n"
        let out = here.appendingPathComponent("out"); try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try trail.write(to: out.appendingPathComponent("suika.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(jumps, 0, "the suggestion jumped on an unchanged jar")
    }

    func time(_ s: Substring) -> Double? {
        let p = s.prefix(10).split(separator: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let x = Double(p[2]) else { return nil }
        return h * 3600 + m * 60 + x
    }

    func replay(_ url: URL, _ out: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let dir = out.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = GameModel()
        var trail = ""
        var lastKey = "", shots = 0, lastPic = -10.0
        var turn = true, bar = 1, mine = 0
        var prevT: Double? = nil
        let text = try String(contentsOf: url, encoding: .utf8)
        for raw in text.split(separator: "\n") {
            guard raw.count > 13, let t = time(raw) else { continue }
            let kind = raw.dropFirst(11).prefix(2)
            guard kind == "P " || kind == "M " else { continue }
            // keep the log's pace (the app's "still" and hold timers run on the clock); gaps (their turn) capped at 2 s
            if let p = prevT, t > p { RunLoop.main.run(until: Date().addingTimeInterval(min(2, t - p))) }
            prevT = t
            var cells = [Int](repeating: 0, count: PoolCodec.count)
            cells[PoolCodec.objDir] = 13; cells[PoolCodec.objDir + 1] = 13; cells[PoolCodec.objDir + 2] = 13
            cells[PoolCodec.spinX] = 13; cells[PoolCodec.spinY] = 13
            var flags = 1
            func field(_ k: String) -> Substring? {
                guard let r = raw.range(of: " " + k + "=") else { return nil }
                return raw[r.upperBound...].prefix { $0 != " " && $0 != "|" }
            }
            if kind == "P " {
                turn = field("turn") == "1"; bar = Int(field("bar") ?? "1") ?? 1; mine = Int(field("mine") ?? "0") ?? 0
            }
            if let r = raw.range(of: "balls=") {
                let rest = raw[r.upperBound...]
                for tok in rest.split(separator: " ") {
                    let p = tok.split(separator: ":")
                    guard p.count == 2, let id = Int(p[0]), id >= 0, id <= 15 else { break }
                    let xy = p[1].split(separator: ",")
                    guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { break }
                    cells[PoolCodec.balls + 7 * id] = 1
                    PoolCodec.put(&cells, PoolCodec.balls + 7 * id + 1, x, y)
                }
            }
            if kind == "P " {
                if let a = field("aim") { let xy = a.split(separator: ","); if xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) { PoolCodec.put(&cells, PoolCodec.aim, x, y); flags |= 2 } }
                if let p = field("power"), let v = Int(p) { cells[PoolCodec.power] = v / 14; cells[PoolCodec.power + 1] = v % 14; flags |= 4 }
                if let d = field("dir"), let deg = Double(d) {
                    let q = Int((deg * 7).rounded()) % 2520
                    cells[PoolCodec.objDir] = q / 196; cells[PoolCodec.objDir + 1] = (q / 14) % 14; cells[PoolCodec.objDir + 2] = q % 14
                }
            }
            cells[PoolCodec.flags] = flags
            cells[PoolCodec.myLeft] = mine
            model.replayPool(BoardMessage(valid: true, game: .pool, cells: cells, me: bar, myTurn: kind == "M " ? true : turn))
            let o = model.overlay
            var key = "\(o.title) | \(o.line)"
            if let v = o.pool {
                key += " | pick=\(v.pick.map { "\($0.ball)>\($0.pocket)@\($0.power)" } ?? "-") guides=\(v.guides.count) found=\(v.found.count)"
                key += " tgt=\(v.powerTarget.map(String.init) ?? "-") spin=\(v.spinY.map { String(format: "%.2f", $0) } ?? "-") zoom=\(v.zoomPocket.map(String.init) ?? "-")"
                key += " ring=\(v.breakSpotX.map { String(format: "%.0f,%.0f", $0, v.breakSpotY ?? 0) } ?? "-") pots=\(v.pots)"
            }
            if key != lastKey {
                lastKey = key
                trail += String(raw.prefix(10)) + "  " + key + "\n"
                // a picture at each change, at most one every 0.5 s of log time
                if t - lastPic >= 0.5 {
                    lastPic = t; shots += 1
                    let img = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).image { _ in
                        Renderer.draw(o, in: CGRect(x: 0, y: 0, width: 640, height: 360))
                    }
                    try img.pngData()?.write(to: dir.appendingPathComponent(String(format: "%03d_%@.png", shots, String(raw.prefix(10)).replacingOccurrences(of: ":", with: "-"))))
                    trail += "      [pic \(shots)]\n"
                }
            }
        }
        try trail.write(to: out.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    }
}
