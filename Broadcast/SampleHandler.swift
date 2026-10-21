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

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Link.port)!, using: .udp)
        c.start(queue: queue)
        conn = c
    }

    override func broadcastFinished() {
        send(BoardMessage(valid: false, cells: [], me: 0, myTurn: false))
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
        guard let msg = BoardReader.read(pb) else { return }
        // only trust a reading that stayed the same across two frames (discs animate when flipping)
        let stable = (msg == prev)
        prev = msg
        if !stable { return }
        if msg != sent || t - lastSent > 1.5 {
            send(msg); sent = msg; lastSent = t
        }
    }

    private func send(_ m: BoardMessage) {
        guard let data = try? JSONEncoder().encode(m) else { return }
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }
}
