import ReplayKit
import QuartzCore

/// Screen-recording extension: reads the board a few times per second and
/// sends it to the app as Darwin notifications (no App Group needed).
class SampleHandler: RPBroadcastSampleHandler {
    private var lastRead: CFTimeInterval = 0
    private var lastSent: CFTimeInterval = 0
    private var prev: BoardMessage?
    private var sent: BoardMessage?
    private var busy = false
    private var glowCells: [Int] = []
    private var lastGlow: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        Signal.post(Signal.started)
    }

    override func broadcastFinished() {
        send(BoardMessage(valid: false, cells: [], me: 0, myTurn: false))
        Signal.post(Signal.stopped)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let t = CACurrentMediaTime()
        if busy || t - lastRead < 0.15 { return }
        lastRead = t
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        defer { busy = false }
        Signal.post(Signal.frame)
        guard var msg = BoardReader.read(pb) else { return }
        if msg.game == .suika && msg.valid { suika(msg, t); return }
        skStableSince = 0; skPrev = nil
        // only trust cells that stayed the same across two frames (discs animate when flipping)
        let stable = prev.map { $0.valid == msg.valid && $0.game == msg.game && $0.cells == msg.cells && $0.me == msg.me } ?? false
        // the legal-move glow pulses, so remember a glow seen in the last second on the same board
        if msg.cells != glowCells { glowCells = msg.cells; lastGlow = 0 }
        if msg.myTurn { lastGlow = t }
        // Plato shows a steady "Your Turn" pill: use it as is (holding it on would think on the opponent's turn)
        if msg.game != .chess && msg.game != .draughts { msg.myTurn = msg.valid && t - lastGlow < 1.2 }
        prev = msg
        if !stable { return }
        if msg != sent || t - lastSent > 1.0 {
            send(msg); sent = msg; lastSent = t
        }
    }

    // Fruit game: only send the jar once every fruit has stopped rolling (same reading for about half a second).
    // Small reading jitter and the held fruit following your finger don't count as movement.
    private var skPrev: BoardMessage?      // the reading the jar has matched since skStableSince
    private var skStableSince: CFTimeInterval = 0
    private func suika(_ msg: BoardMessage, _ t: CFTimeInterval) {
        // compare with the first reading of the quiet spell, so a slow roll can't creep past the tolerance
        if let p = skPrev, SK.same(p.cells, msg.cells) {} else { skPrev = msg; skStableSince = t }
        prev = msg
        guard t - skStableSince >= 0.45 else {
            // still settling: tell the app (myTurn off) so it doesn't keep showing an old answer as current
            if t - lastSent > 1.0, let s = sent, s.game == .suika {
                var w = s; w.myTurn = false
                send(w); lastSent = t
            }
            return
        }
        // the held fruit follows your finger: pass its new spot on a few times a second so the window can say "drop now"
        let moved = sent.map { $0.cells.count == SK.count && abs(($0.cells[SK.heldX] * 14 + $0.cells[SK.heldX + 1]) - (msg.cells[SK.heldX] * 14 + msg.cells[SK.heldX + 1])) >= 2 } ?? true
        if sent == nil || sent!.game != .suika || !SK.same(sent!.cells, msg.cells) || sent!.myTurn != msg.myTurn || t - lastSent > 1.0 || (moved && t - lastSent > 0.3) {
            send(msg); sent = msg; lastSent = t
        }
    }

    private func send(_ m: BoardMessage) {
        DarwinBoard.send(m)
    }
}
