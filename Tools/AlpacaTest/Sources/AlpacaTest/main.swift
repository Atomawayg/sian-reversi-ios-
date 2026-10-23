import Foundation

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
        if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { if !cur.isEmpty { fields.append(cur); cur = "" } } else { cur.append(Character(UnicodeScalar(c))) }
    }
    guard fields.count == 4, let w = Int(fields[1]), let h = Int(fields[2]) else { return nil }
    return (w, h, Array(bytes[i...]))
}

let names = ["cheese", "milk", "corn", "gem", "sprout", "beanie", "peas", "kebab", "mitten", "cake", "fork", "steak", "socks", "carrot", "cotton", "yarn"]
for path in CommandLine.arguments.dropFirst() {
    guard let (w, h, px) = loadPPM(path) else { print("\(path): cannot read"); continue }
    let s = BoardReader.Sampler(w: w, h: h) { x, y in let k = (y * w + x) * 3; return (Double(px[k]), Double(px[k + 1]), Double(px[k + 2])) }
    let t0 = Date()
    let scr = AlpacaReader.screen(s)
    let m = AlpacaReader.read(s)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    let c = m.cells
    var open: [String] = [], known: [String] = [], cov = 0
    var tiles: [AlpacaTile] = []
    for n in 0..<AL.maxTiles {
        let at = AL.tiles + 5 * n, st = c[at + 3]
        if st == 0 { break }
        if st == AL.open { open.append(names[c[at + 4]]) } else { cov += 1; if st == AL.coveredKnown { known.append(names[c[at + 4]]) } }
        tiles.append(AlpacaTile(k: c[at] * 18 + c[at + 1], j: c[at + 2], type: st == AL.coveredUnknown ? -1 : c[at + 4], layer: st == AL.open ? 1000 : 999 - n))
    }
    let rack = (0..<7).compactMap { c[AL.rack + $0] > 0 ? c[AL.rack + $0] - 1 : nil }
    let held = (0..<3).compactMap { c[AL.held + $0] > 0 ? c[AL.held + $0] - 1 : nil }
    for (h, t) in held.enumerated() { tiles.append(AlpacaTile(k: -100 - 10 * h, j: -100, type: t, layer: 2000, held: true)) }
    let t1 = Date()
    let p = AlpacaEngine().plan(tiles: tiles, rack: rack)
    let pms = Int(Date().timeIntervalSince(t1) * 1000)
    print("\((path as NSString).lastPathComponent) screen=\(scr) flags=\(c[AL.flags]) open \(open.count) covered \(cov) known \(known.sorted()) rack \(rack.map { names[$0] }) held \(held.map { names[$0] }) | open \(open.sorted()) | plan \(p.moves.map { names[tiles[$0].type] }) jam=\(p.jam) | read \(ms)ms plan \(pms)ms")
}
