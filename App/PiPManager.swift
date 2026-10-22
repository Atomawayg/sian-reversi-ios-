import AVKit
import UIKit

/// Floating window over other apps, built on Picture in Picture with a
/// sample-buffer layer that we fill with rendered frames.
final class PiPManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let layer = AVSampleBufferDisplayLayer()
    private(set) var controller: AVPictureInPictureController?
    private var current: Overlay?
    private var timer: Timer?
    var onStateChange: ((Bool) -> Void)?

    override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        controller = c
        // keep the window fed even when nothing changes
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let o = self.current else { return }
            Renderer.pulse.toggle()
            self.enqueue(o)
        }
    }

    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    func show(_ o: Overlay) {
        current = o
        enqueue(o)
    }

    func start() {
        guard let c = controller else { return }
        if c.isPictureInPictureActive { c.stopPictureInPicture() } else { c.startPictureInPicture() }
    }

    private func enqueue(_ o: Overlay) {
        guard let pb = Renderer.pixelBuffer(o) else { return }
        var fd: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fd)
        guard let format = fd else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 1),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sbOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sbOut)
        guard let sb = sbOut else { return }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        DispatchQueue.main.async {
            if self.layer.status == .failed { self.layer.flush() }
            self.layer.enqueue(sb)
        }
    }

    // MARK: playback delegate (a "live" stream that is always playing)
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }

    // MARK: delegate
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onStateChange?(true) }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onStateChange?(false) }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) { onStateChange?(false) }
}

/// Hosts the sample-buffer layer inside the app (PiP needs it on screen to start).
final class PiPHostView: UIView {
    let pipLayer: AVSampleBufferDisplayLayer
    init(layer: AVSampleBufferDisplayLayer) {
        pipLayer = layer
        super.init(frame: .zero)
        self.layer.addSublayer(layer)
        backgroundColor = .black
        self.layer.cornerRadius = 14
        self.layer.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); pipLayer.frame = bounds }
}
