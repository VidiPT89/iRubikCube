import CubeCore
import Foundation
import Observation
import SwiftUI

/// A short banner at the top of the screen (achievements, confirmations).
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var systemImage: String
}

/// App-wide services and preferences, shared through the environment.
@Observable
@MainActor
final class AppModel {
    let settings: AppSettings
    let progress: ProgressStore
    @ObservationIgnored let sound = SoundEngine()
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored private let cloud = CloudSync()
    @ObservationIgnored private var started = false
    @ObservationIgnored private let defaults: UserDefaults

    var toast: Toast?
    var presentationDepth = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var queuedToasts: [Toast] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
        progress = ProgressStore(defaults: defaults)
    }

    var language: AppLanguage { settings.language }

    func t(_ key: String) -> String { Strings.t(key, language) }

    func t(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: t(key), locale: language.locale, arguments: arguments)
    }

    /// Starts sound, haptics and iCloud; warms the solver tables up.
    func start() {
        guard !started else { return }
        started = true
        settings.onChange = { [weak self] data in self?.cloud.push(data, for: AppSettings.storageKey) }
        progress.onChange = { [weak self] data in self?.cloud.push(data, for: ProgressStore.storageKey) }
        cloud.onRemoteChange = { [weak self] key, data in
            guard let self else { return }
            if key == AppSettings.storageKey { self.settings.apply(data) }
            if key == ProgressStore.storageKey { self.progress.merge(data) }
        }
        cloud.start()
        if let remote = cloud.pull(ProgressStore.storageKey) { progress.merge(remote) }
        if let remote = cloud.pull(AppSettings.storageKey), defaults.data(forKey: AppSettings.storageKey) == nil {
            settings.apply(remote)
        }
        Task { await TwoPhaseTables.prepare() }
    }

    func becameActive() {
        sound.start()
        haptics.start()
    }

    func resignedActive() {
        sound.stop()
        haptics.stop()
    }

    func play(_ effect: Sound) {
        guard settings.sound else { return }
        sound.play(effect)
    }

    func feel(_ pattern: Haptics.Pattern) {
        guard settings.haptics else { return }
        haptics.play(pattern)
    }

    // MARK: Toasts

    /// Queues a banner; banners are shown one after another.
    func show(_ toast: Toast) {
        queuedToasts.append(toast)
        if toastTask == nil { showNextToast() }
    }

    private func showNextToast() {
        guard !queuedToasts.isEmpty else { return }
        let next = queuedToasts.removeFirst()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { toast = next }
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self.toast = nil }
            try? await Task.sleep(for: .seconds(0.4))
            self.toastTask = nil
            self.showNextToast()
        }
    }

    /// Celebrates newly unlocked achievements, one banner each.
    func announce(_ achievements: [Achievement]) {
        guard !achievements.isEmpty else { return }
        play(.achievement)
        for achievement in achievements {
            show(Toast(title: t("achievements.unlocked"),
                       message: t("achievement.\(achievement.rawValue).title"),
                       systemImage: achievement.systemImage))
        }
    }
}

enum Links {
    static let website = URL(string: "https://ividi.dev/")!
    static let github = URL(string: "https://github.com/VidiPT89/")!
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
