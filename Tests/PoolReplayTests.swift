import XCTest
import UIKit
@testable import SianReversi

/// Replays Atom's pool logs (Tests/logs/*.txt) through the app at their real pace and writes what the PiP shows:
/// a text trail of every change (Tests/out/<log>.txt) and a picture at each change (Tests/out/<log>/NNN.png).
final class PoolReplayTests: XCTestCase {
    func testReplayLogs() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let logs = try FileManager.default.contentsOfDirectory(at: here.appendingPathComponent("logs"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let out = here.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["REPLAY_ONLY"] ?? ""
        for url in logs where only.isEmpty || url.lastPathComponent.contains(only) {
            UserDefaults.standard.removeObject(forKey: "poolBook")
            try replay(url, out)
        }
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
