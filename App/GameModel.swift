import Foundation
import SwiftUI

final class GameModel: ObservableObject {
    @Published var overlay = Overlay(cells: nil, rec: nil, title: "พร้อม", line: "กดปุ่ม 1 และ 2 ด้านล่าง แล้วเปิดเกม")
    @Published var pipOn = false
    @Published var linked = false
    @Published var me = 0
    @Published var debug = "รอการอ่านจอ"
    private var frames = 0, msgs = 0, started = false, netState = "-"
    @Published var thinkMs = UserDefaults.standard.integer(forKey: "thinkMs") == 0 ? 1000 : UserDefaults.standard.integer(forKey: "thinkMs") {
        didSet { UserDefaults.standard.set(thinkMs, forKey: "thinkMs") }
    }

    let pip = PiPManager()
    private let keepAlive = KeepAlive()
    private let receiver = Receiver()
    private let engine = Engine()
    private let work = DispatchQueue(label: "sian.think", qos: .userInitiated)
    private var gen = 0
    private var computedFor: [Int] = []
    private var lastMsgAt = Date.distantPast
    private var watchdog: Timer?
    private var manualMe = false

    init() {
        pip.onStateChange = { [weak self] on in DispatchQueue.main.async { self?.pipOn = on } }
        receiver.onMessage = { [weak self] m in DispatchQueue.main.async { self?.handle(m) } }
        receiver.onStatus = { [weak self] s in DispatchQueue.main.async { self?.netState = s; self?.refreshDebug() } }
        receiver.start()
        GameModel.shared = self
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [Signal.started, Signal.frame, Signal.stopped] {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                let n = (name?.rawValue as String?) ?? ""
                DispatchQueue.main.async { GameModel.shared?.signal(n) }
            }, name as CFString, nil, .deliverImmediately)
        }
        show(overlay)
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let alive = Date().timeIntervalSince(self.lastMsgAt) < 4
            if self.linked != alive {
                self.linked = alive
                if !alive {
                    self.computedFor = []
                    if self.started {
                        self.show(Overlay(cells: nil, rec: nil, title: "⋯", line: "อ่านจออยู่ แต่ยังไม่เห็นกระดาน"))
                        return
                    }
                    self.show(Overlay(cells: nil, rec: nil, title: "หยุดอ่าน", line: "การอ่านหน้าจอหยุดอยู่ กดปุ่ม 2 ในแอปอีกครั้ง"))
                }
            }
        }
    }

    static weak var shared: GameModel?

    fileprivate func signal(_ n: String) {
        if n == Signal.started { started = true; frames = 0 }
        if n == Signal.stopped { started = false }
        if n == Signal.frame { frames += 1; started = true }
        refreshDebug()
    }
    private func refreshDebug() {
        debug = "อ่านจอ: \(started ? "ทำงาน" : "ไม่ทำงาน") · ภาพ \(frames) · ข้อมูล \(msgs) · net \(netState)"
    }

    private func show(_ o: Overlay) { overlay = o; pip.show(o) }

    private static func name(_ i: Int) -> String {
        let letters = Array("ABCDEFGH")
        return "\(letters[i % 8])\(i / 8 + 1)"
    }

    private func handle(_ m: BoardMessage) {
        lastMsgAt = Date()
        msgs += 1; refreshDebug()
        if !linked { linked = true }
        guard m.valid, m.cells.count == 64 else {
            computedFor = []
            show(Overlay(cells: nil, rec: nil, title: "⋯", line: "ยังไม่เห็นกระดาน เปิดหน้าเกมไว้"))
            return
        }
        if m.me != 0 && !manualMe { me = m.me }
        guard me != 0 else {
            show(Overlay(cells: m.cells, rec: nil, title: "?", line: "อ่านสีของคุณไม่ได้ เลือกสีในแอป"))
            return
        }
        guard m.myTurn else {
            computedFor = []
            gen += 1
            show(Overlay(cells: m.cells, rec: nil, title: "รอ…", line: "ตาคู่แข่ง"))
            return
        }
        if m.cells == computedFor { return }
        computedFor = m.cells
        gen += 1
        let g = gen
        let myColor = Int8(me)
        show(Overlay(cells: m.cells, rec: nil, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true))
        var board = [Int8](repeating: 3, count: 100)
        for r in 0..<8 { for c in 0..<8 { board[(r + 1) * 10 + c + 1] = Int8(m.cells[r * 8 + c]) } }
        let ms = thinkMs
        work.async { [weak self] in
            guard let self else { return }
            let res = self.engine.think(board, me: myColor, timeMs: ms)
            DispatchQueue.main.async {
                guard g == self.gen else { return }
                self.present(res, cells: m.cells)
            }
        }
    }

    private func present(_ r: ThinkResult, cells: [Int]) {
        guard r.best > 0 else {
            show(Overlay(cells: cells, rec: nil, title: "ข้าม", line: "คุณไม่มีที่ลง", mine: true))
            return
        }
        let i = (r.best / 10 - 1) * 8 + (r.best % 10 - 1)
        var line: String
        if r.exact {
            line = r.score > 0 ? "ชนะ +\(r.score) แต้ม" : (r.score < 0 ? "แพ้ \(-r.score) (เสียน้อยสุด)" : "เสมอ")
        } else if r.score >= 19000 { line = "ชนะแน่นอน" }
        else if r.score <= -19000 { line = "แพ้ทุกทาง" }
        else {
            let s = r.score
            let t = s > 150 ? "ได้เปรียบมาก" : s > 50 ? "ได้เปรียบ" : s > -50 ? "สูสี" : s > -150 ? "เสียเปรียบ" : "เสียเปรียบมาก"
            line = "\(t) · ลึก \(r.depth)"
        }
        show(Overlay(cells: cells, rec: i, title: GameModel.name(i), line: line, mine: true))
    }

    func setMe(_ c: Int) { me = c; manualMe = c != 0; computedFor = [] }
    func togglePiP() { keepAlive.start(); pip.start() }
}
