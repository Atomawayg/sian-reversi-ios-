import Foundation

// Same sampler as the app's BoardReader (that file needs CoreVideo, which Linux lacks).
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
            while y <= y1 {
                var x = x0
                while x <= x1 { let p = get(x, y); r += p.0; g += p.1; b += p.2; n += 1; x += step }
                y += step
            }
            return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
        }
    }
}

var notes: [String] = []
func note(_ s: String) { notes.append(s); print(s) }
// GitHub keeps only 10 notices per step: pack everything into at most 9
func flush() {
    let per = (notes.count + 8) / 9
    for k in stride(from: 0, to: notes.count, by: max(1, per)) { print("::notice::" + notes[k..<min(notes.count, k + per)].joined(separator: " ║ ")) }
}
func ms(_ t0: UInt64) -> Int { Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000) }

func load(_ name: String) -> BoardReader.Sampler {
    let d = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: "Tools/SuikaTest/\(name).rgb")))
    let w = 1179, h = d.count / 3 / 1179
    return BoardReader.Sampler(w: w, h: h) { x, y in
        let i = (y * w + x) * 3
        return (Double(d[i]), Double(d[i + 1]), Double(d[i + 2]))
    }
}

do {
    let m2 = BoardReader.readSuika(load("IMG_new1"))
    let s2 = SK.decode(m2.cells)!
    note("new1: suika \(BoardReader.looksLikeSuika(load("IMG_new1"))) · held \(s2.held >= 0 ? SK.names[s2.held] : "-") at \(Int(s2.heldX)) · next \(s2.next >= 0 ? SK.names[s2.next] : "-") · jar " + s2.fruits.map { "\(SK.names[$0.t]) (\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " · "))
}
for n in ["IMG_8763", "IMG_8735", "IMG_8758"] {
    note("\(n) looksLikeSuika = \(BoardReader.looksLikeSuika(load(n)))")
}

let s = load("IMG_8758")
var t0 = DispatchTime.now().uptimeNanoseconds
let m = BoardReader.readSuika(s)
note("read in \(ms(t0)) ms, valid \(m.valid) myTurn \(m.myTurn)")
let st = SK.decode(m.cells)!
note("held \(st.held >= 0 ? SK.names[st.held] : "-") at x \(Int(st.heldX)) · next \(st.next >= 0 ? SK.names[st.next] : "-") · \(st.fruits.count) fruits")
note("jar: " + st.fruits.map { "\(SK.names[$0.t]) (\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " · "))
note("same as itself: \(SK.same(m.cells, m.cells))")

let e = SuikaEngine()
for budget in [500, 1000, 2000] {
    t0 = DispatchTime.now().uptimeNanoseconds
    if let r = e.think(st, ms: budget, cancel: { false }) {
        let pos = (r.x - SK.left) / (SK.right - SK.left) * 10
        note("think \(budget) ms → took \(ms(t0)) ms · drop x \(Int(r.x)) (\(String(format: "%.1f", pos))/10) · merges \(r.merges.map { SK.names[min($0, 10)] }) · fill \(String(format: "%.2f", r.fill)) · depth \(r.depth) · land \(r.land.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "merged") · next at \(r.nextX.map { String(Int($0)) } ?? "-")")
    }
}

for n in ["recbig", "recmelon", "recpine"] {
    let v = BoardReader.readSuika(load(n)); let q = SK.decode(v.cells)!
    var c = [Int](repeating: 0, count: SK.types); for f in q.fruits { c[f.t] += 1 }
    note("\(n): \(q.fruits.count) fruits · " + (0..<SK.types).filter { c[$0] > 0 }.map { "\(SK.names[$0])×\(c[$0])" }.joined(separator: " "))
}
// physics sanity: a cherry dropped into an empty jar rests on the floor
var b = [SuikaEngine.Body(t: 0, x: 500, y: SK.dropY)]
var made: [Int] = []
t0 = DispatchTime.now().uptimeNanoseconds
SuikaEngine.simulate(&b, created: &made)
note("empty jar: cherry lands at y \(Int(b[0].y)) (floor - r = \(Int(SK.floor - SK.radius[0]))) in \(ms(t0)) ms")

// a cherry already on the floor: the AI should drop the held cherry onto it
let one = SK.State(held: 0, heldX: 589, next: 2, fruits: [SK.Fruit(t: 0, x: 300, y: SK.floor - 35)])
if let r = e.think(one, ms: 800, cancel: { false }) { note("cherry on floor at x 300 → drop x \(Int(r.x)), merges \(r.merges)") }

// two grapes apart on the floor and a grape in hand
let two = SK.State(held: 2, heldX: 589, next: 0, fruits: [SK.Fruit(t: 2, x: 200, y: SK.floor - 63), SK.Fruit(t: 5, x: 900, y: SK.floor - 121)])
if let r = e.think(two, ms: 800, cancel: { false }) { note("grape at 200 + apple at 900, holding grape → drop x \(Int(r.x)), merges \(r.merges)") }

// a row that merges in a chain: pear, apple, persimmon, dekopon, grape — holding a grape
var chain: [SK.Fruit] = []
var x = SK.left
for t in [6, 5, 4, 3, 2] { x += SK.radius[t]; chain.append(SK.Fruit(t: t, x: x, y: SK.floor - SK.radius[t])); x += SK.radius[t] + 2 }
let ch = SK.State(held: 2, heldX: 589, next: 0, fruits: chain)
t0 = DispatchTime.now().uptimeNanoseconds
if let r = e.think(ch, ms: 1500, cancel: { false }) { note("row pear…grape, holding grape → drop x \(Int(r.x)) (grape at \(Int(chain[4].x))), merges \(r.merges.map { SK.names[min($0, 10)] }) in \(ms(t0)) ms") }

// round trip of the message encoding
let enc = SK.encode(held: 3, heldX: 444, next: 1, fruits: st.fruits)
let dec = SK.decode(enc)!
var maxErr = 0.0
for (a, c) in zip(st.fruits, dec.fruits) { maxErr = max(maxErr, abs(a.x - c.x), abs(a.y - c.y)) }
note("encode/decode: \(dec.fruits.count) fruits, held \(dec.held), next \(dec.next), heldX \(Int(dec.heldX)), max drift \(String(format: "%.1f", maxErr)) px")


// why one spot over another: this drop alone, at the grape and at the AI's spot
do {
    var base = st.fruits.map { SuikaEngine.Body(t: $0.t, x: $0.x, y: $0.y) }
    var none: [Int] = []
    SuikaEngine.simulate(&base, created: &none, merge: false, maxT: 1.5, damp: 0.6)
    var moved = 0.0
    for (a, c) in zip(st.fruits, base) { moved = max(moved, hypot(a.x - c.x, a.y - c.y)) }
    var out = "settle moved ≤\(Int(moved))px"
    for x in [690.0, 706, 720, 760, 810, 850] {
        let t = SuikaEngine.drop(base, st.held, x)
        let e = SuikaEngine.eval(t.jar)
        let made = t.jar.filter { $0.t == 3 }.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined()
        out += " | x\(Int(x)): v1 \(String(format: "%.1f", t.v1)) eval \(String(format: "%.1f", e.v)) travel \(Int(t.travel)) made \(t.created) deko \(made)"
    }
    note(out)
}
flush()
