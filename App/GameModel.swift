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
    private lazy var c4 = Connect4Solver()
    private var tbLoaded = false
    private let ckTrack = BoardTracker(), rvTrack = BoardTracker(), cnTrack = BoardTracker()
    private let work = DispatchQueue(label: "sian.think", qos: .userInitiated)
    private var gen = 0 { didSet { liveGen.set(gen) } }
    /// `gen` readable from the search thread, so a search for an old board stops at once.
    private let liveGen = SharedInt()
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

    // -1 marks anything that has not arrived yet
    private var dCells = [Int](repeating: -1, count: DarwinBoard.maxCells), dMe = -1, dTurn: Bool? = nil, dValid: Bool? = nil, dGame: GameKind? = nil
    private var dHa = -1, dHb = -1
    private var lastDarwinCommit = Date.distantPast, lastSocketMsg = Date.distantPast
    private var darwinMsgs = 0, darwinBroken = 0

    /// The board from the last burst, or nil when something was lost or reordered on the way.
    private func assembledBurst() -> BoardMessage? {
        guard let valid = dValid, let game = dGame, let turn = dTurn, dMe >= 0, dHa >= 0, dHb >= 0 else { return nil }
        var cells: [Int] = []
        if valid {
            cells = Array(dCells.prefix(game.size.w * game.size.h))
            if cells.contains(-1) { return nil }
        }
        let h = DarwinBoard.checksum(valid: valid, game: game.rawValue, cells: cells, me: dMe, turn: turn)
        guard h == dHa * 16 + dHb else { return nil }
        return BoardMessage(valid: valid, game: game, cells: cells, me: dMe, myTurn: turn)
    }

    fileprivate func signal(_ n: String) {
        if n.hasPrefix(DarwinBoard.prefix) {
            let k = String(n.dropFirst(DarwinBoard.prefix.count))
            // Each cell keeps its latest value; the checksum decides whether the assembled board is exactly
            // what was sent. A lost or late notification fails the check and the next resend repairs it.
            if k == "begin" { return }
            if k == "commit" {
                guard let m = assembledBurst() else { darwinBroken += 1; refreshDebug(); return }
                darwinMsgs += 1
                lastDarwinCommit = Date()
                handle(m, viaSocket: false)
            } else if k.hasPrefix("ha"), let v = Int(k.dropFirst(2)) { dHa = v }
            else if k.hasPrefix("hb"), let v = Int(k.dropFirst(2)) { dHb = v }
            else if k.hasPrefix("c"), let vi = k.firstIndex(of: "v"),
                      let i = Int(k[k.index(after: k.startIndex)..<vi]), let v = Int(k[k.index(after: vi)...]), i < DarwinBoard.maxCells {
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
        debug = "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") · อ่านจอ: \(started ? "ทำงาน" : "ไม่ทำงาน") · ภาพ \(frames) · ข้อมูล \(darwinMsgs) · ตกหล่น \(darwinBroken)"
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
            computedFor = []; poolSound.set(.off)
            activeGame = nil
            show(Overlay(cells: nil, rec: nil, title: "⋯", line: "ยังไม่เห็นกระดาน เปิดหน้าเกมไว้"))
            return
        }
        if activeGame != m.game { activeGame = m.game }
        if m.game != .pool { poolSound.set(.off) }
        switch m.game {
        case .checkers: handleCheckers(m); return
        case .connect4, .connect5: handleConnect(m); return
        case .jackaroo: handleJackaroo(m); return
        case .chess: handleChess(m); return
        case .draughts: handleDraughts(m); return
        case .suika: handleSuika(m); return
        case .pool: handlePool(m); return
        case .reversi: break
        }
        let rv = rvTrack.check(m.cells) { b, p in ReversiRules.successors(b, colour: p + 1) }
        guard rv != .suspicious else { boardInDoubt(.reversi, shown: rvTrack.trusted); return }
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

    /// A reading that no legal move explains: keep the last trusted board on screen, don't let the AI
    /// think on it.
    private func boardInDoubt(_ game: GameKind, meColor: Int = 1, shown: [Int]?) {
        computedFor = []; gen += 1
        show(Overlay(game: game, cells: shown, title: "ตรวจ…", line: "กระดานไม่ตรงกติกา รออ่านใหม่", meColor: meColor))
    }

    // MARK: หมากฮอส
    /// Turns the colour reading into 1/2 (your man/king) and -1/-2 (opponent); a man on its far row is a king.
    /// (The reader sees crowns directly now, so kings are no longer remembered between frames —
    /// that memory kept one misread "king" alive for the rest of the game.)
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
        return (nb, meC)
    }

    private static func ckName(_ s: Int) -> String { "\(8 - s / 8)·\(s % 8 + 1)" }

    private var ckCount = 0                 // your moves so far in the counted ending
    private var ckCountBoard: [Int]? = nil
    private func handleCheckers(_ m: BoardMessage) {
        let (board, meC) = checkersBoard(m)
        let draw = board.map { $0 == 1 ? 1 : ($0 == 2 ? 2 : ($0 == -1 ? 3 : ($0 == -2 ? 4 : 0))) }
        let verdict = ckTrack.check(board) { b, p in CheckersRules.successors(b, side: p == 0 ? 1 : -1) }
        guard verdict != .suspicious else { boardInDoubt(.checkers, meColor: meC, shown: ckTrack.trusted.map { t in t.map { $0 == 1 ? 1 : ($0 == 2 ? 2 : ($0 == -1 ? 3 : ($0 == -2 ? 4 : 0))) } }); return }
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: .checkers, cells: draw, title: "รอ…", line: "ตาคู่แข่ง", meColor: meC))
            return
        }
        let key = [100] + board
        if key == computedFor { return }
        computedFor = key; gen += 1
        // WePlay's count: once it is your king + man against a lone king, each side has 8 more moves
        let mineK = board.filter { $0 == 2 }.count, mineM = board.filter { $0 == 1 }.count
        let theirK = board.filter { $0 == -2 }.count, theirM = board.filter { $0 == -1 }.count
        let counted = theirM == 0 && theirK == 1 && ((mineK == 1 && mineM == 1) || (ckCount > 0 && mineK == 2 && mineM == 0))
        if !counted { ckCount = 0; ckCountBoard = nil }
        else if ckCountBoard != board { ckCount += 1; ckCountBoard = board }
        let countLeft = counted ? max(1, CheckersEngine.countMoves - (ckCount - 1)) : 0
        let g = gen, ms = thinkMs
        show(Overlay(game: .checkers, cells: draw, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: meC))
        work.async { [weak self] in
            guard let self else { return }
            if !self.tbLoaded, let url = Bundle.main.url(forResource: "hos-tb", withExtension: "bin"), let d = try? Data(contentsOf: url) {
                self.checkers.loadTB(d)
            }
            self.tbLoaded = true
            self.checkers.countLeft = countLeft
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
                if countLeft > 0 { verdict += " · นับ \(countLeft) ตา" }
                let title = "\(GameModel.ckName(path[0]))→\(GameModel.ckName(path[path.count - 1]))"
                let line = "\(what) · \(verdict)" + (r.trap > 0 ? " · วางกับดัก" : "") + (r.depth > 0 && r.depth < 99 ? " · ลึก \(r.depth)" : "")
                self.show(Overlay(game: .checkers, cells: draw, path: path, caps: caps, title: title, line: line, mine: true, meColor: meC))
            }
        }
    }

    // MARK: เรียง 4 / เรียง 5
    private func handleConnect(_ m: BoardMessage) {
        let (cols, rows) = m.game.size
        // the reader marks your pieces 1 and the opponent's 2 (matched against the player badges)
        var mineN = 0, oppN = 0
        for v in m.cells { if v == 1 { mineN += 1 } else if v == 2 { oppN += 1 } }
        // whoever moved first is drawn red: on your turn equal counts mean that was you
        let first = m.myTurn ? mineN == oppN : mineN > oppN
        let meC = 1
        let colourForPiP = first ? 1 : 2
        let draw = m.cells.map { $0 == 0 ? 0 : ($0 == meC ? 1 : 3) }
        let v = cnTrack.checkGrowing(m.cells)
        guard v != .suspicious else {
            boardInDoubt(m.game, meColor: colourForPiP, shown: cnTrack.trusted.flatMap { $0.count == m.cells.count ? $0.map { $0 == 0 ? 0 : ($0 == meC ? 1 : 3) } : nil })
            return
        }
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: m.game, cells: draw, title: "รอ…", line: "ตาคู่แข่ง", meColor: colourForPiP))
            return
        }
        let key = [200 + m.game.rawValue] + m.cells
        if key == computedFor { return }
        computedFor = key; gen += 1
        let g = gen
        let ms = first ? thinkMs : max(thinkMs, 3000) // the second player is behind, so think longer
        show(Overlay(game: m.game, cells: draw, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: colourForPiP))
        let K = m.game == .connect4 ? 4 : 5
        let cells = m.cells
        work.async { [weak self] in
            guard let self else { return }
            var res = ConnectResult()
            // 7×6 four-in-a-row: try to solve the position exactly first (perfect play from mid-game on)
            var solved = false
            let tried = K == 4 && cols == 7 && rows == 6 && cells.filter({ $0 != 0 }).count >= 10
            if tried, let a = self.c4.best(cells: cells, ms: ms * 6 / 10) {
                let WIN = ConnectEngine.WIN
                res = ConnectResult(best: a.col, score: a.score > 0 ? WIN - 100 + a.score : (a.score < 0 ? -(WIN - 100) + a.score : 0),
                                    depth: 99, exact: true, trap: 0)
                solved = true
            }
            if !solved {
                let e = ConnectEngine(W: cols, H: rows, K: K)
                for c in 0..<cols {
                    var r = rows - 1
                    while r >= 0 { let v = cells[r * cols + c]; if v == 0 { break }; e.play(c, v == meC ? 1 : -1); r -= 1 }
                }
                res = e.search(1, ms: tried ? ms * 4 / 10 : ms)
            }
            DispatchQueue.main.async {
                guard g == self.gen else { return }
                guard res.best >= 0 else { self.show(Overlay(game: m.game, cells: draw, title: "—", line: "กระดานเต็ม", meColor: colourForPiP)); return }
                let WIN = ConnectEngine.WIN
                var verdict: String
                if res.score > WIN - 1000 { verdict = "ชนะแน่" }
                else if res.score < -(WIN - 1000) { verdict = res.trap > 0 ? "เสียเปรียบ · วางกับดัก" : "แพ้ถ้าเขาเล่นถูก" }
                else if res.exact && res.depth == 99 { verdict = "เสมอแน่ (คำนวณครบ)" }
                else { let s = res.score; verdict = s > 60 ? "ได้เปรียบ" : (s < -60 ? "เสียเปรียบ" : "สูสี") }
                let line = verdict + (res.depth > 0 && res.depth < 99 ? " · ลึก \(res.depth)" : (res.depth == 99 ? " · สมบูรณ์แบบ" : "")) + (m.me == 3 ? "\nเริ่มกลางเกม อาจไม่แม่น" : "")
                self.show(Overlay(game: m.game, cells: draw, rec: res.best, title: "ช่อง \(res.best + 1)", line: line, mine: true, meColor: colourForPiP))
            }
        }
    }

    // MARK: Plato chess
    private let chess = ChessEngine()
    private var chPrev: [Int]? = nil          // last board, standard order a8…h1
    private var chCastle = 15
    private static let chStart = [10, 8, 9, 11, 12, 9, 8, 10] + [Int](repeating: 7, count: 8) + [Int](repeating: 0, count: 32)
        + [Int](repeating: 1, count: 8) + [4, 2, 3, 5, 6, 3, 2, 4]
    private static let glyph = ["", "♙", "♘", "♗", "♖", "♕", "♔", "♟", "♞", "♝", "♜", "♛", "♚"]

    static func sqName(_ i: Int) -> String { "\(Array("abcdefgh")[i % 8])\(8 - i / 8)" }

    private func handleChess(_ m: BoardMessage) {
        let meWhite = m.me != 2
        let std = meWhite ? m.cells : Array(m.cells.reversed())          // screen → a8…h1
        // castling rights: lost for good once a king or rook leaves its home square (reset on a new game)
        if std == GameModel.chStart { chCastle = 15 }
        if std[60] != 6 { chCastle &= ~3 }; if std[63] != 4 { chCastle &= ~1 }; if std[56] != 4 { chCastle &= ~2 }
        if std[4] != 12 { chCastle &= ~12 }; if std[7] != 10 { chCastle &= ~4 }; if std[0] != 10 { chCastle &= ~8 }
        // en passant: the opponent's pawn just made a double step
        var ep = -1
        if let p = chPrev, p != std {
            for f in 0..<8 {
                if meWhite, p[8 + f] == 7, std[8 + f] == 0, p[24 + f] == 0, std[24 + f] == 7 { ep = 16 + f }
                if !meWhite, p[48 + f] == 1, std[48 + f] == 0, p[32 + f] == 0, std[32 + f] == 1 { ep = 40 + f }
            }
        }
        if chPrev != std { chPrev = std }
        let meC = meWhite ? 1 : 2
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: .chess, cells: m.cells, title: "รอ…", line: "ตาคู่แข่ง", meColor: meC)); return
        }
        let key = [600 + meC] + std
        if key == computedFor { return }
        computedFor = key; gen += 1
        // fast answers for the clock: the first move shows within a moment, deeper results replace it
        let g = gen, ms = min(max(thinkMs, 1500), 4000), castle = chCastle
        show(Overlay(game: .chess, cells: m.cells, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: meC))
        let present = { [weak self] (r: ChessEngine.Result, done: Bool) in
            guard let self, g == self.gen else { return }
            guard let mv = r.best else {
                let st = self.chess.status()
                self.show(Overlay(game: .chess, cells: m.cells, title: "—", line: st.check ? "รุกจน" : "ไม่มีตาเดิน", mine: true, meColor: meC)); return
            }
            let toScreen = { (i: Int) in meWhite ? i : 63 - i }
            let piece = std[mv.from]
            var title = "\(GameModel.glyph[piece]) \(GameModel.sqName(mv.from))→\(GameModel.sqName(mv.to))"
            if mv.promo > 0 { title += "=" + GameModel.glyph[mv.promo + (meWhite ? 0 : 6)] }
            var verdict: String
            if let mt = r.mateIn { verdict = mt > 0 ? "รุกจนใน \(mt)" : "โดนรุกจนใน \(-mt)" }
            else { let s = r.score; verdict = s >= 300 ? "ได้เปรียบมาก" : s >= 80 ? "ได้เปรียบ" : s > -80 ? "สูสี" : s > -300 ? "เสียเปรียบ" : "เสียเปรียบมาก" }
            if std[mv.to] != 0 { verdict = "กิน · " + verdict }
            let line = verdict + (r.depth > 0 ? " · ลึก \(r.depth)" : "") + (done ? "" : " …")
            self.show(Overlay(game: .chess, cells: m.cells, path: [toScreen(mv.from), toScreen(mv.to)], title: title, line: line, mine: true, meColor: meC))
        }
        let live = liveGen
        work.async { [weak self] in
            guard let self, live.get() == g else { return }
            let t0 = DispatchTime.now().uptimeNanoseconds
            var lastShown: UInt64 = 0
            self.chess.cancel = { live.get() != g }
            self.chess.setPosition(std, whiteToMove: meWhite, castling: castle, epSquare: ep)
            let r = self.chess.think(ms: ms) { p in
                let now = DispatchTime.now().uptimeNanoseconds
                // first answer after ~0.15 s, then at most every 0.3 s
                if now - t0 > 150_000_000 && now - lastShown > 300_000_000 {
                    lastShown = now
                    DispatchQueue.main.async { present(p, false) }
                }
            }
            DispatchQueue.main.async { present(r, true) }
        }
    }

    // MARK: Plato checkers (English rules)
    private let draughts = DraughtsEngine()
    private var dMine = 0          // your colour this game: 1 red, 2 white
    private var dPrev: [Int]? = nil          // last board, +1/+2 mine, −1/−2 theirs
    private var dKings = Set<Int>()          // squares holding a king, followed from move to move

    private func handleDraughts(_ m: BoardMessage) {
        // your colour: read from the captured-pieces trays; before anything is taken, the colour that
        // started at the bottom (only trusted while most pieces are still on the board)
        let count = m.cells.filter { $0 != 0 }.count
        if m.me == 1 || m.me == 2 { dMine = m.me }
        else if count >= 20 {
            var rowSum = [0.0, 0.0, 0.0], n = [0.0, 0.0, 0.0]
            for i in 0..<64 where m.cells[i] != 0 { let c = (m.cells[i] - 1) % 2 + 1; rowSum[c] += Double(i / 8); n[c] += 1 }
            dMine = (n[1] > 0 ? rowSum[1] / n[1] : 0) > (n[2] > 0 ? rowSum[2] / n[2] : 0) ? 1 : 2
        }
        if dMine == 0 { dMine = 2 }
        let mine = dMine
        var board = [Int](repeating: 0, count: 64)
        for i in 0..<64 where m.cells[i] != 0 {
            let c = (m.cells[i] - 1) % 2 + 1
            board[i] = c == mine ? 1 : -1
        }
        // Kings: a crown seen on screen, a man standing on the far row (it was crowned there), or a king
        // followed from its last square (a crown can be hard to see, so the move tells us instead).
        if count >= 24 || dPrev == nil { dKings = [] }
        var kings = Set<Int>()
        if let p = dPrev {
            for side in [1, -1] {
                let gone = (0..<64).filter { p[$0].signum() == side && board[$0] != side }
                let came = (0..<64).filter { board[$0] == side && p[$0].signum() != side }
                if gone.count == 1 && came.count == 1 && dKings.contains(gone[0]) { kings.insert(came[0]) }
            }
            for k in dKings where p[k].signum() == board[k] && board[k] != 0 { kings.insert(k) }
        }
        for i in 0..<64 where board[i] != 0 {
            if m.cells[i] >= 3 || (board[i] == 1 && i / 8 == 0) || (board[i] == -1 && i / 8 == 7) { kings.insert(i) }
        }
        for k in kings { board[k] *= 2 }
        if board != dPrev { dPrev = board; dKings = kings }
        let draw = board.map { $0 == 1 ? 1 : ($0 == 2 ? 2 : ($0 == -1 ? 3 : ($0 == -2 ? 4 : 0))) }
        let meC = mine == 2 ? 3 : 4        // drawing colours: 3 = you cream / opponent red, 4 = you red / opponent cream
        guard m.myTurn else {
            computedFor = []; gen += 1
            show(Overlay(game: .draughts, cells: draw, title: "รอ…", line: "ตาคู่แข่ง", meColor: meC)); return
        }
        let key = [700] + board
        if key == computedFor { return }
        computedFor = key; gen += 1
        let g = gen, ms = min(max(thinkMs, 1200), 3000)
        show(Overlay(game: .draughts, cells: draw, title: "คิด…", line: "ตาคุณ · AI กำลังคิด", mine: true, meColor: meC))
        let present = { [weak self] (r: DraughtsEngine.Result, done: Bool) in
            guard let self, g == self.gen else { return }
            guard let mv = r.best else { self.show(Overlay(game: .draughts, cells: draw, title: "—", line: "ไม่มีตาเดิน", mine: true, meColor: meC)); return }
            let W = DraughtsEngine.WIN
            var verdict: String
            if r.score > W - 1000 { verdict = "ชนะแน่" } else if r.score < -(W - 1000) { verdict = "แพ้ถ้าเขาเล่นถูก" }
            else { let s = r.score; verdict = s >= 150 ? "ได้เปรียบมาก" : s >= 50 ? "ได้เปรียบ" : s > -50 ? "สูสี" : s > -150 ? "เสียเปรียบ" : "เสียเปรียบมาก" }
            let what = mv.caps.isEmpty ? "เดิน" : "กิน \(mv.caps.count) ตัว"
            let title = "\(GameModel.ckName(mv.path[0]))→\(GameModel.ckName(mv.path[mv.path.count - 1]))"
            self.show(Overlay(game: .draughts, cells: draw, path: mv.path, caps: mv.caps, title: title, line: "\(what) · \(verdict) · ลึก \(r.depth)" + (done ? "" : " …"), mine: true, meColor: meC))
        }
        let live = liveGen
        work.async { [weak self] in
            guard let self, live.get() == g else { return }
            let t0 = DispatchTime.now().uptimeNanoseconds
            var lastShown: UInt64 = 0
            self.draughts.cancel = { live.get() != g }
            self.draughts.set(board)
            let r = self.draughts.think(ms: ms) { p in
                let now = DispatchTime.now().uptimeNanoseconds
                if now - t0 > 150_000_000 && now - lastShown > 300_000_000 {
                    lastShown = now
                    DispatchQueue.main.async { present(p, false) }
                }
            }
            DispatchQueue.main.async { present(r, true) }
        }
    }

    // MARK: Pool (WePlay 8-ball) — mostly by sound, so the floating window can be tucked away
    private let poolSound = PoolSound()
    private var poolBalls: [PoolEngine.Ball] = []      // last cleanly read table
    private var poolMsgs = 0, poolRate = 0, poolRateSince = Date(), poolAppMs = 0.0
    private var poolInZone = false
    private var poolLastLog = ""
    private var poolPlanned: [PoolEngine.Ball] = []   // the table the suggestion below was worked out for
    private var poolPlannedGroup = -1
    private var poolBest: PoolEngine.Shot? = nil, poolNext: PoolEngine.Shot? = nil, poolCueEnd: (Double, Double)? = nil
    private var poolOptions: [PoolEngine.Shot] = []    // every ball that pots straight from here (yours and the others)
    private var poolAims: [(Double, Double)] = []   // the last few aim-circle readings (a sure pot needs it steady)

    private var poolGroup = 0            // your group once it is certain (kept for the whole game)
    private var poolGroupCand = 0, poolGroupCandSince = Date()   // a group the counts agree on, and since when
    private var poolGroupAltSince: Date? = nil                    // since when the counts fit the other group clearly better
    private var poolStillSince = Date()  // when the balls last stopped moving
    private var poolPrev: [PoolEngine.Ball] = []

    /// Your group, from counts only: how many balls your bar holds against how many solids and stripes are on the
    /// table (the bar icons' look is not used any more: on the pink table the phone's capture made stripes read as
    /// solids, and 3 games of 4 came out wrong). Decided once the counts agree for 1 s with the table at rest, then
    /// kept; if later the counts fit the other group clearly better for 3 s it switches. A new rack resets it.
    private func poolGroupNow(_ m: BoardMessage, _ others: [PoolEngine.Ball], still: Bool) -> Int {
        let solids = others.filter { (1...7).contains($0.id) }.count, stripes = others.filter { (9...15).contains($0.id) }.count
        if solids + stripes >= 14 { poolGroup = 0; poolGroupCand = 0; poolGroupAltSince = nil }   // a new game
        let mine = m.cells[PoolCodec.myLeft]
        let ds = abs(mine - solids), dl = abs(mine - stripes)
        if still && mine > 0 {
            // which group the counts point at (a ball hidden for a moment is allowed for: one off still counts
            // when the other group is two further off)
            var cand = 0
            if ds <= 1 && dl >= ds + 2 { cand = 1 } else if dl <= 1 && ds >= dl + 2 { cand = 2 }
            else if ds == 0 && dl >= 1 { cand = 1 } else if dl == 0 && ds >= 1 { cand = 2 }
            if poolGroup == 0 {
                if cand != 0 && cand == poolGroupCand {
                    if Date().timeIntervalSince(poolGroupCandSince) >= 1 { poolGroup = cand }
                } else { poolGroupCand = cand; poolGroupCandSince = Date() }
            } else {
                let better = poolGroup == 1 ? dl + 2 <= ds : ds + 2 <= dl
                if better {
                    if let t = poolGroupAltSince { if Date().timeIntervalSince(t) >= 3 { poolGroup = 3 - poolGroup; poolGroupAltSince = nil } }
                    else { poolGroupAltSince = Date() }
                } else { poolGroupAltSince = nil }
            }
        }
        var g = poolGroup
        // on the 8: none of your group left on the table and none in your bar
        if g == 1 && solids == 0 && mine == 0 { g = 3 }
        if g == 2 && stripes == 0 && mine == 0 { g = 3 }
        // group never known this game (you joined late): the bar showing only the 8 tells
        if g == 0 && m.me == 3 && mine == 0 && (solids == 0 || stripes == 0) { g = 3 }
        return g
    }

    private func handlePool(_ m: BoardMessage) {
        let started = Date()
        defer {
            poolAppMs = poolAppMs * 0.9 + Date().timeIntervalSince(started) * 1000 * 0.1
            poolMsgs += 1
            if Date().timeIntervalSince(poolRateSince) >= 1 { poolRate = poolMsgs; poolMsgs = 0; poolRateSince = Date() }
        }
        let c = m.cells
        let clean = c[PoolCodec.flags] & 1 == 1, hasAim = c[PoolCodec.flags] & 2 == 2, pulling = c[PoolCodec.flags] & 4 == 4
        if clean {
            var bs: [PoolEngine.Ball] = []
            for id in 0...15 where c[PoolCodec.balls + 7 * id] == 1 {
                let p = PoolCodec.get(c, PoolCodec.balls + 7 * id + 1)
                bs.append(PoolEngine.Ball(id: id, x: p.x, y: p.y))
            }
            // balls don't vanish while nothing moves: if this reading is the old one minus a ball or two
            // (the cue stick lying over them while you aim), keep the fuller old one
            let same = bs.allSatisfy { b in poolBalls.contains { $0.id == b.id && abs($0.x - b.x) < 4 && abs($0.y - b.y) < 4 } }
            if !(m.myTurn && same && bs.count < poolBalls.count) { poolBalls = bs }
        }
        let balls = poolBalls
        guard !balls.isEmpty else {
            poolSound.set(.off); computedFor = []
            show(Overlay(game: .pool, title: "⋯", line: "กำลังอ่านโต๊ะ")); return
        }
        let cue = balls.first { $0.id == 0 }
        let others = balls.filter { $0.id != 0 }
        // still or rolling: any ball moved more than a few px since the last reading (or one came or went)
        // (the cue ball gets more slack: under the ball-in-hand hand its place comes from the aim line, a few px loose)
        let movedNow = balls.count != poolPrev.count || !balls.allSatisfy { b in let tol = b.id == 0 ? 8.0 : 4.0; return poolPrev.contains { $0.id == b.id && abs($0.x - b.x) < tol && abs($0.y - b.y) < tol } }
        poolPrev = balls
        if movedNow { poolStillSince = Date() }
        let still = Date().timeIntervalSince(poolStillSince) > 0.35
        let group = poolGroupNow(m, others, still: still)
        let legal = PoolEngine.legal(group: group)
        let groupName = ["โต๊ะเปิด", "คุณ: ลูกเต็ม", "คุณ: ลูกลาย", "คุณ: ลูก 8"][max(0, min(3, group))]
        var view = PoolView(balls: balls, shot: nil, legal: Array(legal))
        guard m.myTurn else {
            poolSound.set(.off); computedFor = []; poolAims = []
            var o = Overlay(game: .pool, title: "รอ…", line: "ตาคู่แข่ง · " + groupName); o.pool = view; show(o); return
        }
        // balls still rolling: nothing to work out yet (it used to change its mind every frame)
        guard still || pulling else {
            poolSound.set(.off); poolAims = []
            var o = Overlay(game: .pool, title: "รอลูกหยุด", line: groupName, mine: true); o.pool = view; show(o); return
        }
        // you choose the ball; the app judges your aim (the game's own line makes that exact) and gives the power
        let mineLeft = others.filter { legal.contains($0.id) }.map { $0.id }.sorted()
        let mineText = group == 3 ? "ของคุณ: ลูก 8" : (group == 0 ? "โต๊ะเปิด" : "ของคุณ: " + mineLeft.map(String.init).joined(separator: " · "))
        var title = "เล็งได้เลย", line = mineText
        // a suggestion (worked out once per resting table): which ball, which pocket, how hard, and the ball after it;
        // and a thin line for every ball that pots straight from where the cue ball is, yours or not
        let moved = poolPlannedGroup != group || balls.count != poolPlanned.count
            || !balls.allSatisfy { b in poolPlanned.contains { $0.id == b.id && abs($0.x - b.x) < 6 && abs($0.y - b.y) < 6 } }
        if moved {
            poolPlanned = balls; poolPlannedGroup = group
            poolBest = nil; poolNext = nil; poolCueEnd = nil; poolOptions = []
            if let cue, !PoolEngine.isBreak(others) {
                if let pl = PoolEngine.plan(cueX: cue.x, cueY: cue.y, balls: others, legal: legal, group: group) {
                    poolBest = pl.first; poolNext = pl.next; poolCueEnd = pl.cueEnd
                } else {
                    poolBest = PoolEngine.shots(cueX: cue.x, cueY: cue.y, balls: others, legal: legal, banks: true).first
                }
                var seen = Set<Int>()
                for sh in PoolEngine.shots(cueX: cue.x, cueY: cue.y, balls: others, legal: Set(others.map { $0.id }), banks: false) where !seen.contains(sh.ball) {
                    seen.insert(sh.ball); poolOptions.append(sh)
                }
            }
        }
        view.shot = poolBest; view.next = poolNext; view.options = poolOptions
        if let e = poolCueEnd { view.cueEndX = e.0; view.cueEndY = e.1 }
        if let s = poolBest {
            title = "\(s.ball) → \(PoolEngine.pockets[s.pocket].name)"
            var bankText = "ชิ่ง · "
            if s.bank, let b = others.first(where: { $0.id == s.ball }) {
                let d = hypot(b.x - s.ghostX, b.y - s.ghostY)
                if let h = PoolEngine.cushionHit(b.x, b.y, (b.x - s.ghostX) / d, (b.y - s.ghostY) / d, balls: balls, skip: b.id) {
                    bankText = "ชิ่ง" + PoolEngine.railSpot(h.0, h.1) + " · "
                    if !hasAim { view.bankX = h.0; view.bankY = h.1 }
                }
            }
            line = (s.bank ? bankText : "") + "แรง \(s.powerPct)" + (poolNext.map { " · ต่อด้วย \($0.ball)" } ?? "") + "\n" + mineText
        } else if cue != nil && !PoolEngine.isBreak(others) {
            title = "เซฟ"
            if let cue, let sb = PoolEngine.safety(cueX: cue.x, cueY: cue.y, balls: others, legal: legal) { line = "ไม่มีลูกลงตรงๆ · แตะลูก \(sb.id) ก่อน\n" + mineText }
        }
        if PoolEngine.isBreak(others) { title = "เบรก"; line = "ยิงตรงกลางลูกหน้าสุด แรงสุด" }
        else if cue == nil { title = "วางลูกขาว"; line = mineText }
        // your aim: draw where the balls go; one long tone when it pots one of your balls cleanly
        if hasAim, let cue {
            let a = PoolCodec.get(c, PoolCodec.aim)
            view.aimX = a.x; view.aimY = a.y
            let dir = PoolCodec.dir(c)
            // the ring can flick between two spots a few px apart (by a cushion): trust it once three readings agree
            poolAims.append((a.x, a.y)); if poolAims.count > 3 { poolAims.removeFirst() }
            let steady = pulling || (poolAims.count == 3 && poolAims.allSatisfy { abs($0.0 - a.x) <= 4 && abs($0.1 - a.y) <= 4 })
            let v = PoolEngine.judge(cueX: cue.x, cueY: cue.y, aimX: a.x, aimY: a.y, balls: others, legal: legal, dir: dir)
            if v.ball >= 0, let b = others.first(where: { $0.id == v.ball }) {
                view.objPath = PoolEngine.objectPath(b.x, b.y, gx: a.x, gy: a.y, balls: balls, skip: b.id, dir: dir)
                view.cuePath = PoolEngine.cuePath(cueX: cue.x, cueY: cue.y, gx: a.x, gy: a.y, bx: b.x, by: b.y, balls: balls, dir: dir)
            }
            // how far the cue may turn and still pot (the meter and the pocket close-up), and which way to turn
            var turnHint = ""
            if v.ball >= 0, let b = others.first(where: { $0.id == v.ball }),
               let w = PoolEngine.potWindow(cueX: cue.x, cueY: cue.y, aimX: a.x, aimY: a.y, target: b, balls: balls, dir: dir) {
                view.win = w; view.target = b.id
                let mid = (w.lo + w.hi) / 2, half = (w.hi - w.lo) / 2
                if abs(mid) > max(0.05, half * 0.35) {
                    turnHint = (mid > 0 ? "หมุนไม้ ↻ ตามเข็ม" : "หมุนไม้ ↺ ทวนเข็ม") + (abs(mid) - half > 0 ? "" : " นิดเดียว")
                } else if w.lo <= 0 && w.hi >= 0 {
                    turnHint = "กลางหลุมแล้ว"
                }
            }
            // the pocket close-up whenever your line ends by a pocket, even if no turn of the cue pots it
            if view.win == nil, v.ball >= 0, view.objPath.count >= 4 {
                let ex = view.objPath[view.objPath.count - 2], ey = view.objPath[view.objPath.count - 1]
                if let k = PoolEngine.holes.indices.min(by: { hypot(PoolEngine.holes[$0].x - ex, PoolEngine.holes[$0].y - ey) < hypot(PoolEngine.holes[$1].x - ex, PoolEngine.holes[$1].y - ey) }),
                   hypot(PoolEngine.holes[k].x - ex, PoolEngine.holes[k].y - ey) < 130 {
                    view.zoomPocket = k; view.target = v.ball
                }
            }
            let cleanPot = v.ball >= 0 && v.pocket >= 0 && !v.foul && !v.scratch && v.off < 0.75   // the game's own line makes the edge of the mouth trustworthy
            // never a sure pot on a guessed direction: on a thin cut the game's line is too short to read, and a few px
            // of ring error then turn the ball by 10° or more (an 8 shown as dropping went wide by 14°)
            let good = cleanPot && dir != nil && steady
            view.pots = good
            view.risky = !good && v.ball >= 0 && v.pocket >= 0 && !v.foul && !v.scratch
            var bankText = "ชิ่ง · "
            if v.bank && v.pocket >= 0 && view.objPath.count >= 4 && PoolEngine.onRail(view.objPath[2], view.objPath[3]) {
                let hx = view.objPath[2], hy = view.objPath[3]
                view.bankX = hx; view.bankY = hy
                bankText = "ชิ่ง" + PoolEngine.railSpot(hx, hy) + " · "
            }
            if good {
                title = "✓ \(v.ball) → \(PoolEngine.pockets[v.pocket].name)"
                line = (v.bank ? bankText : "") + "แรง \(v.powerPct)" + (turnHint.isEmpty ? "" : " · " + turnHint) + "\n" + mineText
                if pulling {
                    // pulling the power bar: tone off, one blip when it reaches the strength
                    poolSound.set(.off)
                    let pct = c[PoolCodec.power] * 14 + c[PoolCodec.power + 1]
                    let inZone = abs(pct - v.powerPct) <= 4
                    if inZone && !poolInZone { poolSound.ding() }
                    poolInZone = inZone
                    line += " · ตอนนี้ \(pct)"
                } else {
                    poolInZone = false
                    poolSound.set(.tone(660))
                }
            } else {
                poolSound.set(.off); poolInZone = false
                if v.ball >= 0 && (v.foul || v.scratch) {
                    if v.foul { title = "\(v.ball) ไม่ใช่ของคุณ" }
                    line = (v.foul ? "ฟาวล์ · " : "ลูกขาวจะตกตาม\n") + mineText
                } else if let w = view.win {
                    // your line misses or only just drops: which pocket it is near and which way to turn
                    title = "\(v.ball) → \(PoolEngine.pockets[w.pocket].name)" + (v.pocket >= 0 ? " เสี่ยง" : "?")
                    let why = cleanPot ? (dir == nil ? "ช็อตบาง มองไม่เห็นเส้นของเกม" : "รอวงเล็งนิ่ง") : (v.pocket >= 0 ? "เฉียดจมูกหลุม" : "")
                    line = (cleanPot || turnHint.isEmpty ? why : turnHint) + (v.pocket >= 0 ? " · แรง \(v.powerPct)" : "") + "\n" + mineText
                }
            }
        } else {
            poolSound.set(.off); poolAims = []
        }
        var o = Overlay(game: .pool, title: title, line: line, mine: true); o.pool = view
        show(o)
        if logOn {
            // one line per change: what was read, what the app made of it, what it suggested
            func f(_ v: Double) -> String { String(Int(v.rounded())) }
            var t = "P turn=\(m.myTurn ? 1 : 0) bar=\(m.me) mine=\(c[PoolCodec.myLeft]) group=\(group) balls=" + balls.map { "\($0.id):\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
            if let a = view.aimX, let b = view.aimY { t += " aim=\(f(a)),\(f(b))" }
            if let d = PoolCodec.dir(c) { t += String(format: " dir=%.1f", d * 180 / Double.pi) }
            if let s = poolBest { t += " best=\(s.ball)>\(s.pocket)@\(s.powerPct)" + (poolNext.map { " next=\($0.ball)" } ?? "") }
            if let w = view.win { t += String(format: " win=%d:%.2f..%.2f", w.pocket, w.lo, w.hi) }
            if pulling { t += " power=\(c[PoolCodec.power] * 14 + c[PoolCodec.power + 1])" }
            t += " says=\(title)|" + line.replacingOccurrences(of: "\n", with: " / ")
            if !view.objPath.isEmpty { t += " path=" + view.objPath.map(f).joined(separator: ",") }
            if t != poolLastLog {
                poolLastLog = t
                // speed: screen reading (ms, readings/s) in the recorder, handling here (ms, updates/s)
                log(t + String(format: " rd=%dms/%d ap=%.1fms/%d", PoolCodec.two(c, PoolCodec.readMs), PoolCodec.two(c, PoolCodec.readRate), poolAppMs, poolRate))
            }
        }
    }

    // MARK: Fruit game (WePlay Frog Watermelon)
    private let suika = SuikaEngine()
    private var skComputed: [Int] = []
    private var skAnswer: (x: Double, line: String, land: [Int])? = nil

    /// The answer for this jar, with a title that follows the held fruit: which way to move it, or "drop now".
    private func skOverlay(_ cells: [Int]) -> Overlay {
        guard let a = skAnswer, let st = SK.decode(cells) else { return Overlay(game: .suika, cells: cells, title: "คิด…", line: "", mine: true) }
        let pos = (a.x - SK.left) / (SK.right - SK.left) * 10
        let off = a.x - st.heldX
        let title = abs(off) <= 14 ? "ปล่อย!" : (off < 0 ? "◀ " : "") + String(format: "%.1f", pos) + (off > 0 ? " ▶" : "")
        var o = Overlay(game: .suika, cells: cells, title: title, line: a.line, mine: true)
        o.drop = Int(a.x); o.land = a.land
        return o
    }

    private func handleSuika(_ m: BoardMessage) {
        guard let st = SK.decode(m.cells) else { return }
        guard m.myTurn, st.held >= 0 else {
            computedFor = []; skComputed = []; skAnswer = nil; gen += 1
            show(Overlay(game: .suika, cells: m.cells, title: "รอ…", line: "รอผลไม้หยุดกลิ้ง"))
            return
        }
        if !skComputed.isEmpty && SK.same(skComputed, m.cells) {
            // same jar: keep the answer, only the held fruit moved
            if skAnswer != nil { let o = skOverlay(m.cells); if o != overlay { show(o) } }
            return
        }
        skComputed = m.cells; skAnswer = nil
        gen += 1
        let g = gen, live = liveGen, ms = thinkMs
        show(Overlay(game: .suika, cells: m.cells, title: "คิด…", line: "AI กำลังลองปล่อยทุกจุด", mine: true))
        work.async { [weak self] in
            guard let self else { return }
            let r = self.suika.think(st, ms: ms, cancel: { live.get() != g })
            DispatchQueue.main.async {
                guard g == self.gen, let r else { return }
                var line: String
                if let top = r.merges.max() {
                    line = "รวมได้ → " + SK.names[min(top, SK.types - 1)] + (r.merges.count > 1 ? " (\(r.merges.count) ครั้ง)" : "")
                } else {
                    line = "วางรอคู่"
                }
                if r.fill > 0.85 { line += "\nระวัง ใกล้เส้นแล้ว" }
                else if st.next >= 0 { line += "\nลูกต่อไป: " + SK.names[st.next] }
                self.skAnswer = (r.x, line, r.land.map { [Int($0.x), Int($0.y)] } ?? [])
                self.show(self.skOverlay(self.skComputed))
            }
        }
    }

    // MARK: Jackaroo
    private static let jkColourName = ["", "เขียว", "แดง", "ฟ้า", "ส้ม"]

    private func handleJackaroo(_ m: BoardMessage) {
        let cells = m.cells
        var colourSeat = [Int](repeating: -1, count: 5)
        for s in 0..<4 { let c = cells[JK.seats + s]; if c > 0 { colourSeat[c] = s } }
        var st = [[Int]](repeating: [], count: 4)
        for t in 0..<76 { let c = cells[JK.track + t]; if c > 0, colourSeat[c] >= 0 { st[colourSeat[c]].append(t) } }
        for s in 0..<4 { for k in 0..<4 { if cells[JK.lanes + 4 * s + k] > 0 { st[s].append(100 + k) } } }
        for s in 0..<4 { st[s] = Array((st[s] + [-1, -1, -1, -1]).prefix(4)) }
        var hand: [String] = [], playable: [Bool] = []
        for k in 0..<5 {
            let r = cells[JK.hand + k]
            if r > 0 && r < JK.rankNames.count { hand.append(JK.rankNames[r]); playable.append(cells[JK.playable + k] == 1) }
        }
        if false {   // Jackaroo log retired (the log now records pool)
            let rd = cells.prefix(JK.seats).map { String($0) }.joined()
            let line = "B \(rd) s=\(cells[JK.seats..<JK.hand].map(String.init).joined()) h=" + zip(hand, playable).map { $0 + ($1 ? "*" : "") }.joined(separator: ",") + " t=\(m.myTurn ? 1 : 0) d=\(cells[JK.discard])"
            if line != jkLastLog { jkLastLog = line; log(line) }
        }
        var base = Overlay(game: .jackaroo, cells: cells, title: "รอ…", line: "ตาคนอื่น", meColor: cells[JK.seats + 3])
        base.hand = hand
        let board = Array(cells[0..<JK.hand])
        if m.myTurn && !hand.isEmpty { jkTurnAt = Date() }
        // step 2: the suggested card has left your hand (you confirmed it) and the stones haven't moved yet
        if let l = jkLock, l.board == board, !l.discard, l.overlay.stage >= 1, !l.overlay.marks.isEmpty {
            var rest = l.ranks
            if let i = rest.firstIndex(of: l.rank) { rest.remove(at: i) }
            if hand.sorted() == rest {
                var o = l.overlay
                o.stage = 2; o.pick = -1; o.hand = hand
                jkTurnAt = Date()
                if o != overlay { show(o) }
                return
            }
        }
        if !m.myTurn, let l = jkLock, l.board == board, Date().timeIntervalSince(jkTurnAt) < 2.5 {
            return   // a flicker in the turn signal: keep showing the answer
        }
        guard m.myTurn, !hand.isEmpty else {
            // not your turn: keep a ready answer in case the game makes you discard
            if jkLock != nil && jkLock!.board != board { jkLock = nil }
            if hand.count > 0, jkLock == nil {
                // think about the discard properly (same way as on your turn), once per board + hand
                let pkey = [400] + board + hand.map { JK.rankNames.firstIndex(of: $0) ?? 0 }
                if pkey == jkPassiveKey, let o = jkPassive { if o != overlay { show(o) }; return }
                jkPassiveKey = pkey; jkPassive = nil
                computedFor = []; gen += 1
                let g = gen
                show(base)
                let snap = base
                work.async { [weak self] in
                    guard let self else { return }
                    let ci = JackarooEngine.bestDiscard(st, hand: hand, me: 3, samples: 96, plies: 15)
                    DispatchQueue.main.async {
                        guard g == self.gen else { return }
                        var o = snap
                        o.title = "ตาคนอื่น"
                        o.line = "ถ้าต้องทิ้ง → \(hand[ci])"
                        self.jkPassive = o
                        self.show(o)
                    }
                }
                return
            }
            computedFor = []; gen += 1
            show(base); return
        }
        let discardMode = cells[JK.discard] == 1
        // same board, same cards: keep the answer we already gave (no flip-flopping while you tap cards)
        // the key includes which cards are white: the game lights them up a moment after your turn starts
        let handKey = zip(hand, playable).map { $0 + ($1 ? "*" : "") }.sorted()
        if let l = jkLock, l.board == board, l.hand == handKey, l.discard == discardMode {
            var o = l.overlay
            if let i = hand.firstIndex(of: l.rank) { o.pick = i }
            o.hand = hand
            if o != overlay { show(o) }
            return
        }
        let key = [300, discardMode ? 1 : 0] + board + hand.map { JK.rankNames.firstIndex(of: $0) ?? 0 } + playable.map { $0 ? 1 : 0 }
        if key == computedFor { return }
        computedFor = key; gen += 1
        let g = gen
        base.title = "คิด…"; base.line = "ตาคุณ"; base.mine = true
        show(base)
        let snap = base
        work.async { [weak self] in
            guard let self else { return }
            var best: JKMove?
            if discardMode {
                let ci = JackarooEngine.bestDiscard(st, hand: hand, me: 3)
                best = JKMove(card: ci, rank: hand[ci], kind: .discard)
            } else {
                best = JackarooEngine.bestDeep(st, hand: hand, playable: playable, me: 3)
            }
            // every card grey but stones could still move: the game hasn't lit the cards yet, so wait
            let notLitYet = !discardMode && best?.kind == .discard && !playable.contains(true)
                && !JackarooEngine.generate(st, hand: hand, me: 3).filter({ $0.kind != .force }).isEmpty
            DispatchQueue.main.async {
                guard g == self.gen, let mv = best else { return }
                if notLitYet { var w = snap; w.title = "รอ…"; w.line = "รอเกมเปิดไพ่"; self.show(w); return }
                var o = snap
                o.pick = mv.card
                var (title, line) = GameModel.describe(mv, st: st, cells: cells)
                let plan = GameModel.steps(mv, st: st, cells: cells)
                o.steps = plan.steps; o.tags = plan.tags; o.marks = plan.marks; o.swap = mv.kind == .swap
                o.stage = 1
                switch mv.kind {
                case .place: o.action = mv.rank == "A" ? "New stone" : "ออกลูก"
                case .a1: o.action = "Move 1"
                case .a11: o.action = "Move 11"
                case .fwd: o.action = "เดิน \(mv.steps)"
                case .back: o.action = "ถอย 4"
                case .any5: o.action = mv.moves.first.map { $0.seat == 3 || ($0.seat == 1 && !st[3].contains(where: { $0 < 100 })) } == false ? "ดันลูกนี้ 5" : "เดิน 5"
                case .split: o.action = "แบ่ง \(mv.steps)+\(7 - mv.steps)"
                case .swap: o.action = "สลับ"
                case .force: o.action = "บังคับทิ้ง"
                case .discard: o.action = "ทิ้ง"
                }
                if discardMode || mv.kind == .discard {
                    title = "ทิ้งใบนี้"; line = ""
                    o.steps = []; o.tags = []; o.marks = []; o.arrows = []
                    o.action = "ทิ้งใบนี้"; o.stage = 0
                }
                o.title = title; o.line = line
                self.log("A \(mv.rank) \(mv.kind) | " + (o.steps.isEmpty ? title + " | " + line.replacingOccurrences(of: "\n", with: " / ") : o.steps.joined(separator: " / ")))
                o.arrows = mv.moves.flatMap { mvv -> [Int] in
                    func code(_ p: Int) -> Int { p < 0 ? 200 + mvv.seat : (p >= 100 ? 100 + 4 * mvv.seat + (p - 100) : p) }
                    return [code(mvv.from), code(mvv.to)]
                }
                self.jkLock = JKLock(board: board, hand: handKey, ranks: hand.sorted(), rank: mv.rank, discard: discardMode, overlay: o)
                self.show(o)
            }
        }
    }

    private struct JKLock { let board: [Int]; let hand: [String]; let ranks: [String]; let rank: String; let discard: Bool; let overlay: Overlay }
    private var jkLock: JKLock? = nil
    // MARK: game log (settings → บันทึกเกมพูล): what was read and suggested, to check against the real shots
    @Published var logOn = UserDefaults.standard.bool(forKey: "poolLog") { didSet { UserDefaults.standard.set(logOn, forKey: "poolLog"); if logOn { log("--- เริ่มบันทึก \(Date())") } } }
    private var jkLastLog = ""
    static var logURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sian-pool-log.txt") }
    private static let logTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.S"; return f }()
    func log(_ text: String) {
        guard logOn else { return }
        let line = GameModel.logTime.string(from: Date()) + " " + text + "\n"
        let url = GameModel.logURL
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            if let sz = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, sz > 8_000_000,
               let d = try? Data(contentsOf: url) { try? d.suffix(4_000_000).write(to: url) }
        } else { try? line.data(using: .utf8)!.write(to: url) }
    }
    func clearLog() { try? FileManager.default.removeItem(at: GameModel.logURL); jkLastLog = ""; objectWillChange.send() }
    var logSize: String {
        let b = (try? FileManager.default.attributesOfItem(atPath: GameModel.logURL.path)[.size] as? Int) ?? 0
        return b == 0 ? "ยังไม่มีบันทึก" : String(format: "%.1f KB", Double(b) / 1024)
    }

    /// The advice as taps: step 0 is the card, then one "colour|which stone|what to do" per stone.
    static func steps(_ mv: JKMove, st: [[Int]], cells: [Int]) -> (steps: [String], tags: [String], marks: [Int]) {
        func colour(_ seat: Int) -> String { jkColourName[max(0, min(4, cells[JK.seats + seat]))] }
        let iControl = st[3].contains(where: { $0 < 100 }) ? 3 : 1
        func which(_ seat: Int, _ from: Int) -> String {
            let pre = seat == iControl ? "" : (seat == 1 ? "เพื่อน " : colour(seat) + " ")
            if from < 0 { return "ลูกใหม่" }
            if from >= 100 { return pre + "ในเส้นชัย" }
            let onTrack = st[seat].filter { $0 >= 0 && $0 < 100 }
            if onTrack.count <= 1 { return pre + "ลูกนี้" }
            let d = JackarooEngine.dist(seat, from)
            let ahead = onTrack.filter { JackarooEngine.dist(seat, $0) > d }.count
            if ahead == 0 { return pre + "หน้าสุด" }
            if ahead == onTrack.count - 1 { return pre + "หลังสุด" }
            return pre + "ตัวที่ \(ahead + 1)"
        }
        func code(_ seat: Int, _ p: Int) -> Int { p < 0 ? 200 + seat : (p >= 100 ? 100 + 4 * seat + (p - 100) : p) }
        func step(_ seat: Int, _ from: Int, _ act: String) -> String { "\(cells[JK.seats + seat])|\(which(seat, from))|\(act)" }
        var steps = ["กดไพ่ \(mv.rank) (ใบที่ \(mv.card + 1))"]
        var marks: [Int] = []
        var tags: [String] = []
        let f = mv.moves.first
        switch mv.kind {
        case .place:
            if let f { steps.append(step(f.seat, -1, mv.rank == "A" ? "New stone" : "ออกลูก")); marks.append(code(f.seat, f.from)) }
        case .a1, .a11:
            if let f { steps.append(step(f.seat, f.from, "Move \(mv.kind == .a1 ? 1 : 11)")); marks.append(code(f.seat, f.from)) }
        case .fwd, .back, .any5:
            if let f {
                let n = mv.kind == .back ? "ถอย 4 ช่อง" : (mv.kind == .any5 ? "เดิน 5 ช่อง" : "เดิน \(mv.steps) ช่อง")
                steps.append(step(f.seat, f.from, n)); marks.append(code(f.seat, f.from))
            }
        case .split:
            for (k, mm) in mv.moves.prefix(2).enumerated() {
                steps.append(step(mm.seat, mm.from, "เดิน \(k == 0 ? mv.steps : 7 - mv.steps) ช่อง")); marks.append(code(mm.seat, mm.from))
            }
        case .swap:
            if mv.moves.count >= 2 {
                steps.append(step(mv.moves[0].seat, mv.moves[0].from, "กดลูกนี้ก่อน")); marks.append(code(mv.moves[0].seat, mv.moves[0].from))
                steps.append(step(mv.moves[1].seat, mv.moves[1].from, "⇄ สลับกัน")); marks.append(code(mv.moves[1].seat, mv.moves[1].from))
            }
        case .force: steps.append("0|ไพ่ 10|บังคับทิ้ง")
        case .discard: break
        }
        for s in mv.captures { tags.append(s == 1 || s == 3 ? "ตีลูกเพื่อนกลับบ้าน" : "💥 ตี\(colour(s))กลับบ้าน") }
        if mv.moves.contains(where: { $0.to >= 100 && $0.from < 100 }) { tags.append("🏁 เข้าเส้นชัย") }
        if mv.kind == .any5 || mv.kind == .swap, let mm = mv.moves.first(where: { $0.seat != 3 }) {
            tags.append(mm.seat == 1 ? "🤝 ช่วยเพื่อน" : "😈 ก่อกวน\(colour(mm.seat))")
        }
        return (steps, tags, marks)
    }

    private var jkPassiveKey: [Int] = []
    private var jkPassive: Overlay? = nil

    /// Why this card goes: what the cards you keep can do on this board.
    static func discardReason(_ st: [[Int]], hand: [String], ci: Int) -> String {
        let me = 3
        let ctrl = st[me].contains(where: { $0 < 100 }) ? me : 1
        let atHome = st[ctrl].contains(-1)
        func use(_ c: String) -> String? {
            let ms = JackarooEngine.generate(st, hand: [c], me: me).filter { $0.kind != .force }
            if ms.contains(where: { m in m.moves.contains { $0.to >= 100 && $0.from < 100 } }) { return "\(c) พาเข้าเส้นชัย" }
            if ms.contains(where: { !$0.captures.isEmpty && !$0.captures.contains(1) && !$0.captures.contains(3) }) { return "\(c) ตีลูกศัตรู" }
            if (c == "K" || c == "A") && atHome { return "\(c) ไว้ออกลูกใหม่" }
            if c == "J" && ms.contains(where: { $0.kind == .swap }) { return "J ไว้สลับลูก" }
            if c == "4" && !ms.isEmpty { return "4 ถอยลัดเข้าบ้าน" }
            if c == "7" && !ms.isEmpty { return "7 แบ่งเดินได้" }
            return nil
        }
        var keeps: [String] = []
        var seen = Set<String>()
        for (i, c) in hand.enumerated() where i != ci && seen.insert(c).inserted { if let u = use(c) { keeps.append(u) } }
        let why = use(hand[ci]) == nil ? "\(hand[ci]) ใช้ประโยชน์น้อยสุดตอนนี้" : "\(hand[ci]) เสียน้อยสุด"
        return keeps.isEmpty ? why : why + " · เก็บ " + keeps.prefix(2).joined(separator: ", ")
    }
    private var jkTurnAt = Date.distantPast

    private static func handNames(_ cells: [Int]) -> [String] {
        (0..<5).compactMap { k in let r = cells[JK.hand + k]; return r > 0 && r < JK.rankNames.count ? JK.rankNames[r] : nil }
    }

    /// Plain Thai instructions for a move.
    private static func describe(_ mv: JKMove, st: [[Int]], cells: [Int]) -> (String, String) {
        func colour(_ seat: Int) -> String { jkColourName[max(0, min(4, cells[JK.seats + seat]))] }
        func which(_ seat: Int, _ from: Int) -> String {
            if from < 0 { return "ลูกใหม่" }
            if from >= 100 { return "ลูกในช่องเส้นชัย" }
            let onTrack = st[seat].filter { $0 >= 0 && $0 < 100 }
            if onTrack.count <= 1 { return "ลูก\(colour(seat))" }
            let d = JackarooEngine.dist(seat, from)
            let ahead = onTrack.filter { JackarooEngine.dist(seat, $0) > d }.count
            if ahead == 0 { return "ลูก\(colour(seat))หน้าสุด" }
            if ahead == onTrack.count - 1 { return "ลูก\(colour(seat))หลังสุด" }
            return "ลูก\(colour(seat))ตัวที่ \(ahead + 1) นับจากหน้า"
        }
        var extra: [String] = []
        if mv.moves.contains(where: { $0.to >= 100 && $0.from < 100 }) { extra.append("เข้าเส้นชัย 🏁") }
        for s in mv.captures {
            extra.append(s == 1 || s == 3 ? "ตีลูก\(colour(s))(เพื่อน) กลับบ้าน" : "ตีลูก\(colour(s))กลับบ้าน 💥")
        }
        for mm in mv.moves where mm.seat != 3 {
            if mv.kind == .any5 || mv.kind == .swap {
                extra.append(mm.seat == 1 ? "ช่วยดันลูกเพื่อน 🤝" : "ก่อกวนลูก\(colour(mm.seat)) 😈")
                break
            }
        }
        let first = mv.moves.first
        var title: String
        var detail = ""
        switch mv.kind {
        case .place: title = mv.rank == "A" ? "กด New stone" : "ออกลูกใหม่"; detail = "วางลูกที่ช่องออกตัว"
        case .a1: title = "กด Move 1"; detail = which(first!.seat, first!.from)
        case .a11: title = "กด Move 11"; detail = which(first!.seat, first!.from)
        case .fwd: title = "เดิน \(mv.steps) ช่อง"; detail = which(first!.seat, first!.from)
        case .back: title = "ถอยหลัง 4 ช่อง"; detail = which(first!.seat, first!.from)
        case .any5:
            if first!.seat == 3 || (first!.seat == 1 && !st[3].contains(where: { $0 < 100 })) { title = "เดิน 5 ช่อง"; detail = which(first!.seat, first!.from) }
            else { title = "ดันลูก\(colour(first!.seat)) 5 ช่อง"; detail = first!.seat == 1 ? "ช่วยลูกเพื่อน" : "เลือกลูกของ\(colour(first!.seat))" }
        case .split:
            title = "แบ่ง \(mv.steps) + \(7 - mv.steps)"
            detail = "\(which(mv.moves[0].seat, mv.moves[0].from)) \(mv.steps) · \(which(mv.moves[1].seat, mv.moves[1].from)) \(7 - mv.steps)"
        case .swap:
            title = "สลับกับลูก\(colour(mv.moves[1].seat))"
            detail = "ใช้\(which(first!.seat, first!.from))"
        case .force: title = "ให้คนถัดไปทิ้งไพ่"; detail = "เลือกตัวเลือกบังคับทิ้งไพ่"
        case .discard:
            title = "ทิ้งไพ่ใบนี้"
            let keep = Set(["K", "A"]).intersection(Set(handNames(cells)))
            detail = keep.isEmpty || keep.contains(mv.rank) ? "ไม่มีใบที่ลงได้ · ใบนี้มีประโยชน์น้อยสุด" : "ไม่มีใบที่ลงได้ · เก็บ \(keep.sorted().joined(separator: ", ")) ไว้"
        }
        let line = ([detail] + extra).filter { !$0.isEmpty }.joined(separator: "\n")
        return (title, line)
    }

    func setMe(_ c: Int) { me = c; manualMe = c != 0; computedFor = [] }
    func togglePiP() { keepAlive.start(); pip.start() }
}

/// An Int shared between the main thread and the search thread.
final class SharedInt {
    private var v = 0
    private let lock = NSLock()
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return v }
    func set(_ x: Int) { lock.lock(); v = x; lock.unlock() }
}
