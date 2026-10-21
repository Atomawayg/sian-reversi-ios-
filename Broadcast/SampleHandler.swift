import ReplayKit
import Network
import QuartzCore

/// Screen-recording extension: reads the board a few times per second and
/// sends it to the app over UDP on localhost (no App Group needed).
class SampleHandler: RPBroadcastSampleHandler {
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "sian.send")
    private var lastRead: CFTimeInterval = 0
    private var lastSent: CFTimeInterval = 0
    private var prev: BoardMessage?
    private var sent: BoardMessage?
    private var busy = false
    private var glowCells: [Int] = []
    private var lastGlow: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Link.port)!, using: .udp)
        c.start(queue: queue)
        conn = c
        Signal.post(Signal.started)
    }

    override func broadcastFinished() {
        send(BoardMessage(valid: false, cells: [], me: 0, myTurn: false))
        Signal.post(Signal.stopped)
        conn?.cancel()
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
        let stable = prev.map { $0.valid == msg.valid && $0.cells == msg.cells && $0.me == msg.me } ?? false
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
        guard let data = try? JSONEncoder().encode(m) else { return }
        conn?.send(content: data, completion: .contentProcessed { _ in })
        RawUDP.send(data)
    }
}
