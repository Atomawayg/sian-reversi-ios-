import ReplayKit
import QuartzCore
import CoreImage
import Photos

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

    // Automatic bug frames: when the app says a board broke the rules, save the frame we just read
    // to Photos (at most one every 20 s, 30 per session) so it can be sent to the developer later.
    private var lastFrame: CVPixelBuffer?
    private let frameLock = NSLock()
    private var lastSave: CFTimeInterval = 0
    private var saves = 0
    private let saveQueue = DispatchQueue(label: "sian.bugframes")
    private static weak var current: SampleHandler?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SampleHandler.current = self
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            SampleHandler.current?.saveBugFrame()
        }, Signal.suspect as CFString, nil, .deliverImmediately)
        Signal.post(Signal.started)
    }

    private func saveBugFrame() {
        let t = CACurrentMediaTime()
        frameLock.lock()
        let pb = lastFrame
        let allowed = pb != nil && saves < 30 && t - lastSave > 20
        if allowed { lastSave = t; saves += 1 }
        frameLock.unlock()
        guard allowed, let pb else { return }
        saveQueue.async {
            let ci = CIImage(cvPixelBuffer: pb)
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let jpg = CIContext(options: [.cacheIntermediates: false]).jpegRepresentation(of: ci, colorSpace: cs, options: [:]) else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpg, options: nil)
            }) { ok, _ in Signal.post(ok ? Signal.frameSaved : Signal.frameSaveFailed) }
        }
    }

    override func broadcastFinished() {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil)
        frameLock.lock(); lastFrame = nil; frameLock.unlock()
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
        frameLock.lock(); lastFrame = pb; frameLock.unlock()
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
