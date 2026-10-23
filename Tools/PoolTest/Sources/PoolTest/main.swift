import Foundation

// Minimal stand-in for the app's BoardReader.Sampler (the real one reads CVPixelBuffers).
enum BoardReader {
    struct Sampler {
        let w: Int, h: Int
        let get: (Int, Int) -> (Double, Double, Double)
        func avg(_ cx: Double, _ cy: Double, _ rad: Double) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            let x0 = max(0, Int(cx - rad)), x1 = min(w - 1, Int(cx + rad))
            let y0 = max(0, Int(cy - rad)), y1 = min(h - 1, Int(cy + rad))
            let step = max(1, Int(rad / 4))
            var y = y0
            while y <= y1 { var x = x0; while x <= x1 { let p = get(x, y); r += p.0; g += p.1; b += p.2; n += 1; x += step }; y += step }
            return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
        }
    }
}

func loadPPM(_ path: String) -> (Int, Int, [UInt8])? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    let bytes = [UInt8](d)
    var fields: [String] = [], i = 0, cur = ""
    while fields.count < 4 && i < bytes.count {
        let c = bytes[i]; i += 1
        if c == 0x23 { while i < bytes.count && bytes[i] != 0x0A { i += 1 }; continue }
        if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { if !cur.isEmpty { fields.append(cur); cur = "" } } else { cur.append(Character(UnicodeScalar(c))) }
    }
    guard fields.count == 4, let w = Int(fields[1]), let h = Int(fields[2]) else { return nil }
    return (w, h, Array(bytes[i...]))
}

for name in CommandLine.arguments.dropFirst() {
    guard let (w, h, px) = loadPPM(name) else { print("\(name): cannot read"); continue }
    let s = BoardReader.Sampler(w: w, h: h) { x, y in let k = (y * w + x) * 3; return (Double(px[k]), Double(px[k + 1]), Double(px[k + 2])) }
    let t0 = Date()
    let pool = PoolReader.looksLikePool(s)
    let m = PoolReader.read(s)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    let c = m.cells
    var balls: [PoolEngine.Ball] = []
    for id in 0...15 where c[PoolCodec.balls + 7 * id] == 1 { let p = PoolCodec.get(c, PoolCodec.balls + 7 * id + 1); balls.append(.init(id: id, x: p.x, y: p.y)) }
    let aim = c[PoolCodec.flags] & 2 == 2 ? PoolCodec.get(c, PoolCodec.aim) : nil
    var line = "\((name as NSString).lastPathComponent) pool=\(pool) clean=\(c[PoolCodec.flags] & 1) turn=\(m.myTurn) group=\(m.me) left=\(c[PoolCodec.myLeft])/\(c[PoolCodec.oppLeft]) ids=\(balls.map { $0.id }.sorted())"
    if let a = aim { line += String(format: " aim=(%.0f,%.0f)", a.x, a.y) }
    if let cue = balls.first(where: { $0.id == 0 }), let s0 = PoolEngine.shots(cueX: cue.x, cueY: cue.y, balls: balls.filter { $0.id != 0 }, legal: PoolEngine.legal(group: m.me)).first {
        line += String(format: " shot=%d->%@ cut%.0f tol%.2f", s0.ball, PoolEngine.pockets[s0.pocket].name, s0.cut, s0.tolerance)
    }
    line += " \(ms)ms"
    print(line)
}
