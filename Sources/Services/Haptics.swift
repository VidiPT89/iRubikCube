import CoreHaptics
import UIKit

/// Core Haptics patterns, with simple impacts on devices without an engine.
@MainActor
final class Haptics {

    enum Pattern {
        /// Each 90° step of a layer.
        case detent
        /// A layer settling into place.
        case snap
        case warning
        /// Long celebratory pattern when the cube is solved.
        case solved
        case tap
    }

    var isEnabled = true
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notifier = UINotificationFeedbackGenerator()

    func start() {
        guard supportsHaptics, engine == nil else { return }
        engine = try? CHHapticEngine()
        // iOS stops the engine whenever the app loses the foreground.
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
    }

    func stop() {
        engine?.stop()
        engine = nil
    }

    func play(_ pattern: Pattern) {
        guard isEnabled else { return }
        switch pattern {
        case .detent: custom([(0, 0.45, 0.9)], fallback: { light.impactOccurred(intensity: 0.6) })
        case .snap: custom([(0, 0.75, 0.55)], fallback: { medium.impactOccurred() })
        case .tap: light.impactOccurred(intensity: 0.5)
        case .warning: notifier.notificationOccurred(.warning)
        case .solved:
            let beats: [(TimeInterval, Float, Float)] = [
                (0, 1, 0.6), (0.12, 0.8, 0.5), (0.24, 1, 0.7), (0.42, 1, 1),
            ]
            custom(beats, rumble: 0.55, fallback: { notifier.notificationOccurred(.success) })
        }
    }

    private func custom(_ taps: [(TimeInterval, Float, Float)], rumble: TimeInterval = 0, fallback: () -> Void) {
        guard supportsHaptics, let engine else {
            fallback()
            return
        }
        var events = taps.map { time, intensity, sharpness in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        if rumble > 0 {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ], relativeTime: 0, duration: rumble))
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else {
            fallback()
            return
        }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
