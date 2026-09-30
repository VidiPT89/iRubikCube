import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case pt, en

    var id: String { rawValue }

    /// PT-PT, never pt-BR, so dates and numbers read like Portugal.
    var locale: Locale { self == .pt ? Locale(identifier: "pt_PT") : Locale(identifier: "en_GB") }

    var nativeName: String { self == .pt ? "Português" : "English" }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("pt") == true ? .pt : .en
    }
}

enum Appearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

enum AnimationSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case slow, normal, fast

    var id: String { rawValue }

    /// Seconds for a quarter turn.
    var quarterTurn: Double {
        switch self {
        case .slow: 0.42
        case .normal: 0.26
        case .fast: 0.15
        }
    }
}

/// Every preference, saved locally and mirrored to iCloud.
@Observable
@MainActor
final class AppSettings {

    struct Snapshot: Codable, Equatable {
        var language: AppLanguage
        var appearance: Appearance
        var animationSpeed: AnimationSpeed
        var inspection: Bool
        var sound: Bool
        var haptics: Bool
        var highContrast: Bool
        var showNotationPanel: Bool
    }

    var language: AppLanguage { didSet { persist() } }
    var appearance: Appearance { didSet { persist() } }
    var animationSpeed: AnimationSpeed { didSet { persist() } }
    var inspection: Bool { didSet { persist() } }
    var sound: Bool { didSet { persist() } }
    var haptics: Bool { didSet { persist() } }
    var highContrast: Bool { didSet { persist() } }
    var showNotationPanel: Bool { didSet { persist() } }

    static let storageKey = "settings.v1"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isApplying = false
    /// Called with the encoded settings after every change (iCloud push).
    @ObservationIgnored var onChange: ((Data) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        language = saved?.language ?? AppLanguage.systemDefault
        appearance = saved?.appearance ?? .system
        animationSpeed = saved?.animationSpeed ?? .normal
        inspection = saved?.inspection ?? false
        sound = saved?.sound ?? true
        haptics = saved?.haptics ?? true
        highContrast = saved?.highContrast ?? false
        showNotationPanel = saved?.showNotationPanel ?? true
    }

    var snapshot: Snapshot {
        Snapshot(language: language, appearance: appearance, animationSpeed: animationSpeed,
                 inspection: inspection, sound: sound, haptics: haptics,
                 highContrast: highContrast, showNotationPanel: showNotationPanel)
    }

    /// Applies settings that arrived from another device.
    func apply(_ data: Data) {
        guard let remote = try? JSONDecoder().decode(Snapshot.self, from: data), remote != snapshot else { return }
        isApplying = true
        language = remote.language
        appearance = remote.appearance
        animationSpeed = remote.animationSpeed
        inspection = remote.inspection
        sound = remote.sound
        haptics = remote.haptics
        highContrast = remote.highContrast
        showNotationPanel = remote.showNotationPanel
        isApplying = false
        persist()
    }

    private func persist() {
        guard !isApplying, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
        onChange?(data)
    }

    var cubeScheme: CubeScheme { highContrast ? .highContrast : .standard }
}
