import Foundation

/// WePlay "Frog Watermelon" (a Suika-style merge game): drop fruits into a jar, two of a kind merge into the next.
/// All geometry is in screen pixels of a 1179×2556 iPhone screenshot.
enum SK {
    // message layout (cells, each 0…13)
    static let held = 0          // fruit Will is holding: type + 1, 0 none
    static let next = 1          // next fruit (centre of the wheel): type + 1, 0 unknown
    static let heldX = 2         // 2 cells: x of the held fruit (base 14)
    static let n = 4             // 2 cells: number of fruits in the jar
    static let fruits = 6        // 5 cells per fruit: type + 1, x (2 cells), y (2 cells)
    static let maxFruits = 40
    static let count = fruits + 5 * maxFruits

    // jar geometry
    // the glass is drawn 26 px thick inside its white outline: fruits rest 26 px in from the drawn edge
    // (a pear sits at y 2323 over a drawn floor at 2349; a dekopon leans on the left wall at x 108)
    static let left = 108.0      // physics wall, left
    static let right = 1070.0    // physics wall, right
    static let floor = 2323.0    // where fruits rest
    static let dead = 1002.0     // dashed line at the top of the jar
    static let dropY = 905.0     // centre of the fruit Will holds
    static let top = 800.0       // top of the area that is read

    /// radius of each fruit type (cherry … watermelon), measured on the game screen
    static let radius: [Double] = [35, 48, 63, 75, 92, 121, 138, 168, 200, 235, 280]
    static let names = ["เชอร์รี่", "สตรอว์เบอร์รี่", "องุ่น", "ส้มเหลือง", "ส้มจิ้งจอก", "แอปเปิ้ล", "สาลี่", "พีช", "สับปะรด", "เมลอน", "แตงโม"]
    static let types = 11

    // positions travel as two base-14 digits (0…195)
    static func qx(_ x: Double) -> Int { max(0, min(195, Int(((x - left) / (right - left) * 195).rounded()))) }
    static func qy(_ y: Double) -> Int { max(0, min(195, Int(((y - top) / (floor + 7 - top) * 195).rounded()))) }
    static func ux(_ q: Int) -> Double { left + Double(q) / 195 * (right - left) }
    static func uy(_ q: Int) -> Double { top + Double(q) / 195 * (floor + 7 - top) }

    struct Fruit: Equatable { var t: Int; var x: Double; var y: Double }
    struct State { var held: Int; var heldX: Double; var next: Int; var fruits: [Fruit]; var total = 0 }

    static func encode(held h: Int, heldX hxPos: Double, next nx: Int, fruits fl: [Fruit]) -> [Int] {
        var c = [Int](repeating: 0, count: count)
        c[SK.held] = h >= 0 ? h + 1 : 0
        c[SK.next] = nx >= 0 ? nx + 1 : 0
        let hx = qx(hxPos); c[SK.heldX] = hx / 14; c[SK.heldX + 1] = hx % 14
        let fs = Array(fl.prefix(maxFruits))
        let total = min(195, fl.count)   // the real count (only the first maxFruits are listed): shows when the jar holds more
        c[n] = total / 14; c[n + 1] = total % 14
        for (k, f) in fs.enumerated() {
            let b = SK.fruits + 5 * k
            let x = qx(f.x), y = qy(f.y)
            c[b] = f.t + 1; c[b + 1] = x / 14; c[b + 2] = x % 14; c[b + 3] = y / 14; c[b + 4] = y % 14
        }
        return c
    }

    static func decode(_ c: [Int]) -> State? {
        guard c.count == count else { return nil }
        let k = min(maxFruits, c[n] * 14 + c[n + 1])
        var fs: [Fruit] = []
        for i in 0..<k {
            let b = fruits + 5 * i
            let t = c[b] - 1
            if t < 0 || t >= types { continue }
            fs.append(Fruit(t: t, x: ux(c[b + 1] * 14 + c[b + 2]), y: uy(c[b + 3] * 14 + c[b + 4])))
        }
        return State(held: c[held] - 1, heldX: ux(c[heldX] * 14 + c[heldX + 1]), next: c[next] - 1, fruits: fs, total: c[n] * 14 + c[n + 1])
    }

    /// Same jar (and same held / next fruit) give or take a couple of steps of position: the reading jitters a little.
    /// The held fruit's x is ignored because it follows your finger.
    static func same(_ a: [Int], _ b: [Int], tol: Int = 2) -> Bool {
        guard a.count == count, b.count == count, a[held] == b[held], a[next] == b[next], a[n] == b[n], a[n + 1] == b[n + 1] else { return false }
        let k = min(maxFruits, a[n] * 14 + a[n + 1])
        // fruits may come out in a different order: match each one to an unused fruit of the same type nearby
        var used = [Bool](repeating: false, count: k)
        for i in 0..<k {
            let p = fruits + 5 * i
            let ax = a[p + 1] * 14 + a[p + 2], ay = a[p + 3] * 14 + a[p + 4]
            var ok = false
            for j in 0..<k where !used[j] {
                let q = fruits + 5 * j
                if b[q] != a[p] { continue }
                let bx = b[q + 1] * 14 + b[q + 2], by = b[q + 3] * 14 + b[q + 4]
                if abs(ax - bx) <= tol && abs(ay - by) <= tol { used[j] = true; ok = true; break }
            }
            if !ok { return false }
        }
        return true
    }
}
