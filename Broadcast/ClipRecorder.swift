import AVFoundation
import Photos
import QuartzCore

/// Records what the screen reader sees to a half-size H.264 clip (frame times exact, for measuring speeds, banks and
/// spin) and saves it to Photos when stopped. The app switches it on and off with Darwin notifications (an app and
/// its extension share no files here), and hears back whether it was saved.
final class ClipRecorder {
    static let shared = ClipRecorder()
    private let lock = NSLock()
    private var want = false
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var url: URL?
    private var began: CFTimeInterval = 0
    static let maxSeconds = 180.0

    private init() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [Signal.clipStart, Signal.clipStop] {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let n = name?.rawValue as String? else { return }
                if n == Signal.clipStart { ClipRecorder.shared.setWant(true) }
                if n == Signal.clipStop { ClipRecorder.shared.setWant(false) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }

    func setWant(_ on: Bool) { lock.lock(); want = on; lock.unlock() }

    /// Every video frame from ReplayKit passes through here.
    func add(_ sb: CMSampleBuffer) {
        lock.lock(); let on = want; lock.unlock()
        if on, writer == nil { begin(sb) }
        guard let w = writer, let i = input else { return }
        if !on || CACurrentMediaTime() - began > ClipRecorder.maxSeconds { finish(); return }
        if w.status == .writing && i.isReadyForMoreMediaData { i.append(sb) }
        if w.status == .failed { writer = nil; input = nil; setWant(false); Signal.post(Signal.clipFailed) }
    }

    private func begin(_ sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let w = CVPixelBufferGetWidth(pb) / 4 * 2, h = CVPixelBufferGetHeight(pb) / 4 * 2   // half size, even
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("sian-clip-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: u)
        guard let wr = try? AVAssetWriter(outputURL: u, fileType: .mp4) else { setWant(false); Signal.post(Signal.clipFailed); return }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoExpectedSourceFrameRateKey: 60,
                                              AVVideoMaxKeyFrameIntervalKey: 60]]
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        inp.expectsMediaDataInRealTime = true
        guard wr.canAdd(inp) else { setWant(false); Signal.post(Signal.clipFailed); return }
        wr.add(inp)
        guard wr.startWriting() else { setWant(false); Signal.post(Signal.clipFailed); return }
        wr.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
        writer = wr; input = inp; url = u; began = CACurrentMediaTime()
        Signal.post(Signal.clipRecording)
    }

    func finish() {
        guard let w = writer, let i = input, let u = url else { return }
        writer = nil; input = nil; url = nil
        setWant(false)
        i.markAsFinished()
        w.finishWriting {
            guard w.status == .completed else { Signal.post(Signal.clipFailed); return }
            let st = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            guard st == .authorized || st == .limited else { Signal.post(Signal.clipNoAccess); return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u)
            }) { ok, _ in
                try? FileManager.default.removeItem(at: u)
                Signal.post(ok ? Signal.clipSaved : Signal.clipFailed)
            }
        }
    }
}
