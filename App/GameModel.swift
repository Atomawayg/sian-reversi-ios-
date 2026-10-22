import Foundation
import SwiftUI

final class GameModel: ObservableObject {
    @Published var overlay = Overlay(cells: nil, rec: nil, title: "พร้อม", line: "กด เริ่มใช้งาน แล้วเข้าเกม")
    @Published var activeGame: GameKind? = nil
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
    private let engine = Engine()
    private let checkers = CheckersEngine()
    private var tbLoaded = false
    private var ckPrev: [Int]? = nil
    private let work = DispatchQueue(label: "sian.think", qos: .userInitiated)
    private var gen = 0
    private var computedFor: [Int] = []
    private var lastMsgAt = Date.distantPast
    private var watchdog: Timer?
    private var manualMe = false

    init() {
        pip.onStateChange = { [weak self] on in DispatchQueue.main.async { self?.pipOn = on } }
        GameModel.shared = self
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [Signal.started, Signal.frame, Signal.stopped] + DarwinBoard.names() {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                let n = (name?.rawValue as String?) ?? ""
                DispatchQueue.main.async { GameModel.shared?.signal(n) }
            }, name as CFString, nil, .deliverImmediately)
        }
        show(overlay)
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshDebug()
            self.show(self.overlay)
            let alive = Date().timeIntervalSince(self.lastMsgAt) < 4
            if self.linked != alive {
                self.linked = alive
                if !alive {
                    self.computedFor = []
                    if self.started {
                        self.activeGame = nil
                        self.show(Overlay(cells: nil, rec: nil, title: "⋯", line: "อ่านจออยู่ แต่ยังไม่เห็นกระดาน"))
                        return
                    }
                    self.activeGame = nil
                    self.show(Overlay(cells: nil, rec: nil, title: "หยุดอ่าน", line: "เปิดแอป เซียน แล้วกด เริ่มใช้งาน"))
                }
            }
        }
    }

    static weak var shared: GameModel?

    private var dCells = [Int](repeating: 0, count: 64), dMe = 0, dTurn = false, dValid = false, dGame = GameKind.reversi
    private var lastDarwinCommit = Date.distantPast, lastSocketMsg = Date.distantPast
    private var darwinMsgs = 0

    fileprivate func signal(_ n: String) {
        if n.hasPrefix(DarwinBoard.prefix) {
            let k = String(n.dropFirst(DarwinBoard.prefix.count))
            if k == "commit" {
                darwinMsgs += 1
                lastDarwinCommit = Date()
                let n = dGame.size.w * dGame.size.h
                handle(BoardMessage(valid: dValid, game: dGame, cells: dValid ? Array(dCells.prefix(n)) : [], me: dMe, myTurn: dTurn), viaSocket: false)
            } else if k.hasPrefix("c"), let vi = k.firstIndex(of: "v"),
                      let i = Int(k[k.index(after: k.startIndex)..<vi]), let v = Int(k[k.index(after: vi)...]), i < 64 {
                dCells[i] = v
            } else if k.hasPrefix("me"), let v = Int(k.dropFirst(2)) { dMe = v }
            else if k.hasPrefix("g"), let v = Int(k.dropFirst(1)), let g = GameKind(rawValue: v) { dGame = g }
            else if k.hasPrefix("turn") { dTurn = k == "turn1" }
            else if k.hasPrefix("valid") { dValid = k == "valid1" }
            return
        }
        if n == Signal.started { started = true; frames = 0 }
        if n == Signal.stopped { started = false }
        if n == Signal.frame { frames += 1; started = true }
        refreshDebug()
    }
    private func refreshDebug() {
        debug = "อ่านจอ: \(started ? "ทำงาน" : "ไม่ทำงาน") · ภาพ \(frames) · ข้อมูล \(darwinMsgs)"
    }

    private func show(_ o: Overlay) { var x = o; x.footer = debug; overlay = x; pip.show(x) }

    private static func name(_ i: Int) -> String {
        let letters = Array("ABCDEFGH")
        return "\(letters[i % 8])\(i / 8 + 1)"
    }

    private func handle(_ m: BoardMessage, viaSocket: Bool) {
        lastMsgAt = Date()
        if viaSocket { lastSocketMsg = Date(); msgs += 1 }
        refreshDebug()
        if !linked { linked = true }
        guard m.valid, m.cells.count == m.game.size.w * m.game.size.h else {
            computedFor = []
            activeGame = nil
            show(Overlay(cells: nil, rec: nil, title: "⋯", line: "ยังไม่เห็นกระดาน เปิดหน้าเกมไว้"))
            return
        }
        if activeGame != m.game { activeGame = m.game }
        switch m.game {
        case .checkers: handleCheckers(m); return
        case .connect4, .connect5: handleConnect(m); return
        case .reversi: break
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

    // MARK: หมากฮอส
    /// Turns the colour reading into 1/2 (your man/king) and -1/-2 (opponent), tracking kings between frames:
    /// a piece on its far row is a king, and a king keeps its crown when it moves.
    private func checkersBoard(_ m: BoardMessage) -> (board: [Int], meColor: Int) {
        var meC = m.me
        if meC == 0 { // fallback: whoever has more pieces in the bottom half is you
            var lower = [0, 0, 0]
            for i in 32..<64 where m.cells[i] != 0 { lower[(m.cells[i] - 1) % 2 + 1] += 1 }
            meC = lower[1] >= lower[2] ? 1 : 2
        }
        var nb = [Int](repeating: 0, count: 64)
        for i in 0..<64 where m.cells[i] != 0 {
            let colour = (m.cells[i] - 1) % 2 + 1, crowned = m.cells[i] >= 3
            let mine = colour == meC
            var x = mine ? 1 : -1
            if crowned { x *= 2 }
            if mine && i / 8 == 0 { x = 2 }
            if !mine && i / 8 == 7 { x = -2 }
            nb[i] = x
        }
        if let p = ckPrev {
            let before = p.filter { $0 != 0 }.count, after = nb.filter { $0 != 0 }.count
            if after > before { ckPrev = nil } // new game
        }
        if let p = ckPrev {
            for i in 0..<64 where nb[i] != 0 && p[i] == nb[i] * 2 { nb[i] *= 2 }
            for side in [1, -1] {
                let vac = (0..<64).filter { p[$0] * side > 0 && !(nb[$0] * side > 0) }
                let app = (0..<64).filter { nb[$0] * side > 0 && !(p[$0] * side > 0) }
                if vac.count == 1 && app.count == 1 && abs(p[vac[0]]) == 2 { nb[app[0]] = 2 * side }
            }
        }
        ckPrev = nb
        return (nb, meC)
    }

    private static func ckName(_ s: Int) -> String { "\(8 - s / 8)·\(s % 8 + 1)" }

    private func handleCheckers(_ m: BoardMessage) {
        let (board, meC) = checkersBoard(m)
        let draw = board.map { $0 == 1 ? 1 : ($0 == 2 ? 2 : ($0 == -1 ? 3 : ($0 == -2 ? 4 : 0))) }
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: .checkers, cells: draw, title: "รอ…", line: "ตาคู่แข่ง", meColor: meC))
            return
        }
        let key = [100] + board
        if key == computedFor { return }
        computedFor = key; gen += 1
        let g = gen, ms = thinkMs
        show(Overlay(game: .checkers, cells: draw, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: meC))
        work.async { [weak self] in
            guard let self else { return }
            if !self.tbLoaded, let url = Bundle.main.url(forResource: "hos-tb", withExtension: "bin"), let d = try? Data(contentsOf: url) {
                self.checkers.loadTB(d)
            }
            self.tbLoaded = true
            let r = self.checkers.search(board, side: 1, maxMs: ms)
            let path = r.best.map { self.checkers.path(of: $0, board: board) } ?? []
            let caps = r.best.map { self.checkers.capsSquares($0) } ?? []
            DispatchQueue.main.async {
                guard g == self.gen else { return }
                guard let best = r.best, path.count >= 2 else {
                    self.show(Overlay(game: .checkers, cells: draw, title: "—", line: "ไม่มีตาเดิน", mine: true, meColor: meC)); return
                }
                let MATE = CheckersEngine.MATE
                var verdict: String
                if let tb = r.tb { verdict = tb == 0 ? "เสมอแน่" : (tb < 128 ? "ชนะแน่" : "แพ้ถ้าเขาเล่นถูก") }
                else if r.score > MATE - 1000 { verdict = "ชนะแน่" }
                else if r.score < -MATE + 1000 { verdict = "เสียเปรียบหนัก" }
                else { let s = r.score; verdict = s >= 250 ? "ได้เปรียบมาก" : s >= 80 ? "ได้เปรียบ" : s > -80 ? "สูสี" : s > -250 ? "เสียเปรียบ" : "เสียเปรียบมาก" }
                let what = best.caps != 0 ? "กิน \(caps.count) ตัว" : (best.promo ? "เดิน (เข้าฮอส)" : "เดิน")
                let title = "\(GameModel.ckName(path[0]))→\(GameModel.ckName(path[path.count - 1]))"
                let line = "\(what) · \(verdict)" + (r.depth > 0 && r.depth < 99 ? " · ลึก \(r.depth)" : "")
                self.show(Overlay(game: .checkers, cells: draw, path: path, caps: caps, title: title, line: line, mine: true, meColor: meC))
            }
        }
    }

    // MARK: เรียง 4 / เรียง 5
    private func handleConnect(_ m: BoardMessage) {
        let (cols, rows) = m.game.size
        var reds = 0, yellows = 0
        for v in m.cells { if v == 1 { reds += 1 } else if v == 2 { yellows += 1 } }
        // red always moves first: on your turn, equal counts mean you are red
        var meC = m.me
        if m.myTurn { meC = reds == yellows ? 1 : 2 } else if meC == 0 { meC = reds > yellows ? 2 : 1 }
        let draw = m.cells.map { $0 == 0 ? 0 : ($0 == meC ? 1 : 3) }
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: m.game, cells: draw, title: "รอ…", line: "ตาคู่แข่ง", meColor: meC))
            return
        }
        let key = [200 + m.game.rawValue] + m.cells
        if key == computedFor { return }
        computedFor = key; gen += 1
        let g = gen
        let ms = meC == 2 ? max(thinkMs, 3000) : thinkMs // the second player is behind, so think longer
        show(Overlay(game: m.game, cells: draw, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: meC))
        let K = m.game == .connect4 ? 4 : 5
        let cells = m.cells
        work.async { [weak self] in
            guard let self else { return }
            let e = ConnectEngine(W: cols, H: rows, K: K)
            for c in 0..<cols {
                var r = rows - 1
                while r >= 0 { let v = cells[r * cols + c]; if v == 0 { break }; e.play(c, v == meC ? 1 : -1); r -= 1 }
            }
            let res = e.search(1, ms: ms)
            DispatchQueue.main.async {
                guard g == self.gen else { return }
                guard res.best >= 0 else { self.show(Overlay(game: m.game, cells: draw, title: "—", line: "กระดานเต็ม", meColor: meC)); return }
                let WIN = ConnectEngine.WIN
                var verdict: String
                if res.score > WIN - 1000 { verdict = "ชนะแน่" }
                else if res.score < -(WIN - 1000) { verdict = res.trap > 0 ? "เสียเปรียบ · วางกับดัก" : "แพ้ถ้าเขาเล่นถูก" }
                else { let s = res.score; verdict = s > 60 ? "ได้เปรียบ" : (s < -60 ? "เสียเปรียบ" : "สูสี") }
                let line = verdict + (res.depth > 0 ? " · ลึก \(res.depth)" : "")
                self.show(Overlay(game: m.game, cells: draw, rec: res.best, title: "ช่อง \(res.best + 1)", line: line, mine: true, meColor: meC))
            }
        }
    }

    func setMe(_ c: Int) { me = c; manualMe = c != 0; computedFor = [] }
    func togglePiP() { keepAlive.start(); pip.start() }
}
