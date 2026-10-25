import ReplayKit
import QuartzCore

/// Screen-recording extension: reads the board a few times per second and
/// sends it to the app as Darwin notifications (no App Group needed).
class SampleHandler: RPBroadcastSampleHandler {
    private var lastRead: CFTimeInterval = 0
    private var lastSent: CFTimeInterval = 0
    private var lastFull: CFTimeInterval = 0
    private var poolMode = false
    private var prev: BoardMessage?
    private var sent: BoardMessage?
    private var busy = false
    private var glowCells: [Int] = []
    private var lastGlow: CFTimeInterval = 0
    private var readMs = 0.0, reads = 0, rate = 0, rateSince: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        _ = ClipRecorder.shared   // starts listening for the app's record switch
        Signal.post(Signal.started)
    }

    override func broadcastFinished() {
        ClipRecorder.shared.finish()
        send(BoardMessage(valid: false, cells: [], me: 0, myTurn: false))
        Signal.post(Signal.stopped)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        ClipRecorder.shared.add(sampleBuffer)
        let t = CACurrentMediaTime()
        // pool reads every frame it can (the aim moves under your finger); the board games every 0.15 s
        if busy || t - lastRead < (poolMode ? 0 : 0.15) { return }
        lastRead = t
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        defer { busy = false }
        Signal.post(Signal.frame)
        let t0 = CACurrentMediaTime()
        guard var msg = BoardReader.read(pb) else { return }
        // how long a reading takes and how many a second (shown in the pool log)
        readMs = readMs * 0.9 + (CACurrentMediaTime() - t0) * 1000 * 0.1
        reads += 1
        if t - rateSince >= 1 { rate = reads; reads = 0; rateSince = t }
        if msg.game == .suika && msg.valid { suika(msg, t); return }
        // pool: the aim and the power bar move all the time and the app keeps the last clean table itself,
        // so pass every reading on at once (the sound has to follow your finger)
        if msg.game == .pool && msg.valid {
            prev = msg; poolMode = true
            // timing goes out with the full board only (it changes every frame)
            func stamp(_ m: inout BoardMessage, _ ms: Int, _ r: Int) {
                guard m.cells.count >= PoolCodec.count else { return }
                m.cells[PoolCodec.readMs] = ms / 14; m.cells[PoolCodec.readMs + 1] = ms % 14
                m.cells[PoolCodec.readRate] = r / 14; m.cells[PoolCodec.readRate + 1] = r % 14
            }
            if let s = sent, s.game == .pool, s.cells.count >= PoolCodec.count {
                stamp(&msg, PoolCodec.two(s.cells, PoolCodec.readMs), PoolCodec.two(s.cells, PoolCodec.readRate))
            }
            // full board once a second, otherwise just the cells that moved (the aim, the power bar)
            if t - lastFull > 1.0 || sent?.game != .pool {
                stamp(&msg, min(195, Int(readMs.rounded())), min(195, rate))
                DarwinBoard.send(msg); lastFull = t; sent = msg; lastSent = t
            }
            else if msg != sent { DarwinBoard.send(msg, since: sent); sent = msg; lastSent = t }
            return
        }
        poolMode = false
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
