import AVFoundation

/// Plays silence so iOS keeps the app running in the background while the
/// floating window is up (otherwise the app can be suspended and stop updating).
final class KeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    func start() {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buf.frameLength = 44100 // zero-filled = silence
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.01
        do { try engine.start() } catch { return }
        player.scheduleBuffer(buf, at: nil, options: .loops)
        player.play()
        running = true
    }
}
