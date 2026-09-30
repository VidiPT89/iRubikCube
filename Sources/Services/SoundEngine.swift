import AVFoundation

/// Everything the app can play.
enum Sound: CaseIterable, Sendable {
    case turn, snap, tap, correct, wrong, solved, achievement, whoosh, tick
}

/// A tiny synthesiser: every sound is rendered into a PCM buffer on first
/// use, so the app ships no audio files at all.
///
/// Talking to the system audio service can stall, so none of it happens on
/// the main thread or at launch.
@MainActor
final class SoundEngine {
    var isEnabled = true
    private let core = SoundCore()

    func start() { core.run { $0.start() } }
    func stop() { core.run { $0.stop() } }

    func play(_ sound: Sound) {
        guard isEnabled else { return }
        core.run { $0.play(sound) }
    }
}

/// The audio graph. Every member is touched only on `queue`.
private final class SoundCore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.ividi.irubikcube.audio", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    /// One format for the connections and the buffers; a mismatch crashes.
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isRunning = false
    private var lastPlayed: [Sound: CFTimeInterval] = [:]

    func run(_ work: @escaping @Sendable (SoundCore) -> Void) {
        queue.async { work(self) }
    }

    private func prepare() -> AVAudioEngine {
        if let engine { return engine }
        let engine = AVAudioEngine()
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
        for sound in Sound.allCases { buffers[sound] = render(sound) }

        let center = NotificationCenter.default
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.run { $0.restart() }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard type == .ended else { return }
            self?.run { $0.restart() }
        }
        self.engine = engine
        return engine
    }

    private func restart() {
        guard isRunning, let engine, !engine.isRunning else { return }
        isRunning = false
        start()
    }

    func start() {
        guard !isRunning else { return }
        let engine = prepare()
        // Ambient, so the app never silences the player's own music.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        do {
            try engine.start()
            isRunning = true
            voices.forEach { $0.play() }
        } catch {
            isRunning = false
        }
    }

    func stop() {
        guard isRunning, let engine else { return }
        voices.forEach { $0.stop() }
        engine.pause()
        isRunning = false
    }

    func play(_ sound: Sound) {
        guard isRunning, let buffer = buffers[sound] else { return }
        let now = CACurrentMediaTime()
        // Fast bursts of the same sound (scrambles) would only turn to mush.
        if let last = lastPlayed[sound], now - last < 0.035 { return }
        lastPlayed[sound] = now
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !voice.isPlaying { voice.play() }
    }

    // MARK: Synthesis

    private struct Note {
        var start: Double
        var frequency: Double
        var duration: Double
        var volume: Double
        var bright: Double = 0.2
    }

    private func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        switch sound {
        case .turn: return click(pitch: 1, length: 0.07, body: 180)
        case .snap: return click(pitch: 0.75, length: 0.09, body: 120)
        case .tick: return click(pitch: 1.4, length: 0.035, body: 260)
        case .tap: return tones([Note(start: 0, frequency: 1320, duration: 0.05, volume: 0.18)])
        case .whoosh: return noiseSweep(length: 0.35)
        case .correct:
            return tones([Note(start: 0, frequency: 784, duration: 0.12, volume: 0.25),
                          Note(start: 0.08, frequency: 1175, duration: 0.18, volume: 0.25)])
        case .wrong:
            return tones([Note(start: 0, frequency: 330, duration: 0.16, volume: 0.22, bright: 0.05),
                          Note(start: 0.1, frequency: 262, duration: 0.2, volume: 0.2, bright: 0.05)])
        case .achievement:
            return tones([1047, 1319, 1568, 2093].enumerated().map {
                Note(start: Double($0.offset) * 0.07, frequency: $0.element, duration: 0.3, volume: 0.18, bright: 0.35)
            })
        case .solved:
            let melody: [(Double, Double, Double)] = [
                (0, 523, 0.16), (0.12, 659, 0.16), (0.24, 784, 0.16), (0.36, 1047, 0.5),
                (0.36, 659, 0.5), (0.36, 784, 0.5), (0.62, 1319, 0.55),
            ]
            return tones(melody.map { Note(start: $0.0, frequency: $0.1, duration: $0.2, volume: 0.2, bright: 0.3) })
        }
    }

    /// Plastic click: a short filtered noise burst over a quick low thump.
    private func click(pitch: Double, length: Double, body: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 0x1234_5678
        var filtered = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            filtered += (noise - filtered) * 0.55 * pitch
            let crack = filtered * exp(-t * 90 / pitch) * 0.55
            let thump = sin(2 * .pi * body * pitch * t) * exp(-t * 55) * 0.35
            data[i] = Float(crack + thump)
        }
        return buffer
    }

    private func noiseSweep(length: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 0x9E37_79B9
        var low = 0.0
        for i in 0..<Int(frames) {
            let progress = Double(i) / Double(frames)
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            low += (noise - low) * (0.05 + progress * 0.4)
            data[i] = Float(low * sin(.pi * progress) * 0.35)
        }
        return buffer
    }

    private func tones(_ notes: [Note]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = (notes.map { $0.start + $0.duration }.max() ?? 0.1) + 0.05
        let frames = AVAudioFrameCount(rate * total)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        for note in notes {
            let start = Int(note.start * rate)
            let count = Int(note.duration * rate)
            for j in 0..<count where start + j < Int(frames) {
                let t = Double(j) / rate
                let attack = min(1, t / 0.008)
                let release = exp(-t * 7 / note.duration)
                let wave = sin(2 * .pi * note.frequency * t)
                    + note.bright * sin(4 * .pi * note.frequency * t)
                    + note.bright * 0.4 * sin(6 * .pi * note.frequency * t)
                data[start + j] += Float(wave * attack * release * note.volume)
            }
        }
        return buffer
    }
}
