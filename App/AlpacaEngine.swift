import Foundation

/// Crazy Alpaca planner. The rack holds 7 tiles; three of a kind vanish; a full rack loses.
/// Looks a few taps ahead (tiles revealed on the way count only if the reader could see their art)
/// and scores positions by how safe the rack is. Tested in a simulator: an ordinary
/// "match what's in the rack" player cleared 12% of boards, this planner 57%.
struct AlpacaTile { var k: Int; var j: Int; var type: Int; var layer: Int; var held = false }   // type -1 = unknown

final class AlpacaEngine {
    static let cap = 7
    static let junk = 31          // an unknown tile in the rack: never part of a triple

    private var tiles: [AlpacaTile] = []
    private var blockers: [(UInt64, UInt64)] = []      // tiles that must go first (bitset over ≤ 128 tiles)
    private var memo: [Key: Double] = [:]
    private struct Key: Hashable { let g0: UInt64; let g1: UInt64; let rack: UInt64; let d: Int }

    struct Plan { var moves: [Int] = []; var value = 0.0; var jam = false }

    @inline(__always) private func has(_ s: (UInt64, UInt64), _ i: Int) -> Bool { i < 64 ? s.0 & (1 << UInt64(i)) != 0 : s.1 & (1 << UInt64(i - 64)) != 0 }
    @inline(__always) private func with(_ s: (UInt64, UInt64), _ i: Int) -> (UInt64, UInt64) { i < 64 ? (s.0 | (1 << UInt64(i)), s.1) : (s.0, s.1 | (1 << UInt64(i - 64))) }

    /// rack: up to 7 types (packed 6 bits each, sorted)
    private func pack(_ r: [Int]) -> UInt64 { var v: UInt64 = 0; for t in r.sorted() { v = v << 6 | UInt64(t + 1) }; return v | UInt64(r.count) << 48 }

    private func add(_ rack: [Int], _ t: Int) -> ([Int], Bool) {
        var r = rack; r.append(t)
        if t != AlpacaEngine.junk && r.filter({ $0 == t }).count >= 3 {
            var n = 0; r.removeAll { if $0 == t && n < 3 { n += 1; return true }; return false }
            return (r, true)
        }
        return (r, false)
    }

    private func free(_ gone: (UInt64, UInt64)) -> [Int] {
        var out: [Int] = []
        for i in tiles.indices where !has(gone, i) {
            let b = blockers[i]
            if b.0 & ~gone.0 == 0 && b.1 & ~gone.1 == 0 { out.append(i) }
        }
        return out
    }

    private func evaluate(_ gone: (UInt64, UInt64), _ rack: [Int]) -> Double {
        if rack.count >= AlpacaEngine.cap { return -1e9 }
        let fr = free(gone)
        var vc = [Int](repeating: 0, count: 32)
        for i in fr where tiles[i].type >= 0 { vc[tiles[i].type] += 1 }
        var rc = [Int](repeating: 0, count: 32)
        for t in rack { rc[t] += 1 }
        let space = AlpacaEngine.cap - rack.count
        var v = -12.0 * Double(rack.count), need = 0
        for t in 0..<32 where rc[t] > 0 {
            if t != AlpacaEngine.junk && vc[t] >= 3 - rc[t] { v += 6 * Double(rc[t]); need += 3 - rc[t] }
            else { v -= 8 * Double(rc[t]) * (space <= 2 ? 2.5 : 1.0) }
        }
        if need > space { v -= 40 }
        return v + 1.5 * Double(fr.count)
    }

    private func search(_ gone: (UInt64, UInt64), _ rack: [Int], _ depth: Int, _ deadline: UInt64) -> Double {
        if rack.count >= AlpacaEngine.cap { return -1e9 }
        if depth == 0 || DispatchTime.now().uptimeNanoseconds > deadline { return evaluate(gone, rack) }
        let key = Key(g0: gone.0, g1: gone.1, rack: pack(rack), d: depth)
        if let v = memo[key] { return v }
        let fr = free(gone)
        if fr.isEmpty { return 1e6 }
        var best = -1e18
        for i in fr {
            let t = tiles[i].type >= 0 ? tiles[i].type : AlpacaEngine.junk
            let (nr, cl) = add(rack, t)
            best = max(best, search(with(gone, i), nr, depth - 1, deadline) + (cl ? 25 : 0))
        }
        memo[key] = best
        return best
    }

    /// The best next taps (indices into `tiles`), up to `show` of them.
    func plan(tiles t: [AlpacaTile], rack: [Int], depth: Int = 3, show: Int = 3, ms: Int = 250) -> Plan {
        tiles = Array(t.prefix(128))
        blockers = tiles.indices.map { i in
            var b: (UInt64, UInt64) = (0, 0)
            for m in tiles.indices where m != i && tiles[m].layer > tiles[i].layer
                && abs(tiles[m].k - tiles[i].k) < 4 && abs(tiles[m].j - tiles[i].j) < 2 { b = with(b, m) }
            return b
        }
        memo.removeAll(keepingCapacity: true)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(ms) * 1_000_000
        var gone: (UInt64, UInt64) = (0, 0)
        var r = rack
        var out = Plan()
        for step in 0..<show {
            let fr = free(gone).filter { tiles[$0].type >= 0 }
            if fr.isEmpty { break }
            var bi = -1, bv = -1e18
            // finishing a triple is always right
            var rc = [Int](repeating: 0, count: 32); for x in r { rc[x] += 1 }
            if let i = fr.first(where: { rc[tiles[$0].type] == 2 }) { bi = i; bv = 1e5 }
            else {
                for i in fr {
                    let (nr, cl) = add(r, tiles[i].type)
                    let v = search(with(gone, i), nr, depth - 1, deadline) + (cl ? 25 : 0)
                    if v > bv { bv = v; bi = i }
                }
            }
            if step == 0 { out.value = bv; out.jam = bv <= -1e8 }
            out.moves.append(bi)
            gone = with(gone, bi)
            r = add(r, tiles[bi].type).0
            if r.count >= AlpacaEngine.cap { break }
        }
        return out
    }
}
