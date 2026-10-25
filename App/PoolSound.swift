import AVFoundation

/// Sounds for aiming in pool, so the floating window can be tucked away: silence = not yet,
/// one long tone = this aim pots a ball, a blip when the power bar is pulled far enough, and Thai speech
/// (the tone waits while the voice speaks, so they never overlap).
/// Plays over the game's own sound (the audio session mixes with others).
final class PoolSound: NSObject, AVSpeechSynthesizerDelegate {
    enum Mode: Equatable { case off, tone(Double), beeps(Double, Double), warn }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let speech = AVSpeechSynthesizer()
    private var started = false
    private var mode: Mode = .off
    private var lastSaid = "", lastSaidAt = Date.distantPast

    // read by the audio thread
    private final class State { var freq = 0.0; var on = 1.0; var off = 0.0; var ding = 0; var mute = false }
    private let st = State()

    private func start() {
        guard !started else { return }
        let sr = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        var phase = 0.0, t = 0.0, amp = 0.0, dphase = 0.0
        let s = st
        let n = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frames) {
                var f = s.freq
                var gate = f > 0 && !s.mute         // the tone waits while the voice speaks
                if s.off > 0 { gate = gate && t.truncatingRemainder(dividingBy: s.on + s.off) < s.on }
                if s.ding > 0 { f = 1760; gate = true; s.ding -= 1 }
                let target = gate ? 0.35 : 0.0
                amp += (target - amp) * 0.004          // soft edges, no clicks
                if f > 0 { dphase = 2 * Double.pi * f / sr }
                phase += dphase; if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                let v = Float(sin(phase) * amp)
                for b in buf { b.mData?.assumingMemoryBound(to: Float.self)[i] = v }
                t += 1 / sr
            }
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return }
        node = n
        started = true
    }

    func set(_ m: Mode) {
        if m == mode { return }
        start()
        mode = m
        switch m {
        case .off: st.freq = 0
        case .tone(let f): st.freq = f; st.off = 0
        case .beeps(let f, let gap): st.freq = f; st.on = 0.07; st.off = gap
        case .warn: st.freq = 330; st.on = 0.06; st.off = 0.09
        }
    }

    /// short high blip (power bar reached the right spot)
    func ding() { start(); st.ding = 44100 / 12 }

    /// Thai speech; the same words are not repeated within `again` seconds
    func say(_ text: String, again: Double = 6) {
        if text == lastSaid && Date().timeIntervalSince(lastSaidAt) < again { return }
        lastSaid = text; lastSaidAt = Date()
        start()
        speech.delegate = self
        st.mute = true
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "th-TH")
        u.rate = 0.55
        speech.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { if !synthesizer.isSpeaking { st.mute = false } }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { if !synthesizer.isSpeaking { st.mute = false } }
}
