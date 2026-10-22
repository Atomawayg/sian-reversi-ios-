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
        if busy || t - lastRead < 0.25 { return }
        lastRead = t
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        defer { busy = false }
        Signal.post(Signal.frame)
        guard var msg = BoardReader.read(pb) else { return }
        // only trust cells that stayed the same across two frames (discs animate when flipping)
        let stable = prev.map { $0.valid == msg.valid && $0.game == msg.game && $0.cells == msg.cells && $0.me == msg.me } ?? false
        // the legal-move glow pulses, so remember a glow seen in the last second on the same board
        if msg.cells != glowCells { glowCells = msg.cells; lastGlow = 0 }
        if msg.myTurn { lastGlow = t }
        msg.myTurn = msg.valid && t - lastGlow < 1.2
        prev = msg
        if !stable { return }
        if msg != sent || t - lastSent > 1.0 {
            send(msg); sent = msg; lastSent = t
        }
    }

    private func send(_ m: BoardMessage) {
        DarwinBoard.send(m)
    }
}
