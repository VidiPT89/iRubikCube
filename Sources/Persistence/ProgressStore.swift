import CubeCore
import Foundation
import Observation

enum Achievement: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstCross, firstSolve, underTwoMinutes, underOneMinute, weekStreak
    case graduate, dailyChallenge, bigCube, scanner

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .firstCross: "plus.circle.fill"
        case .firstSolve: "cube.fill"
        case .underTwoMinutes: "timer"
        case .underOneMinute: "bolt.fill"
        case .weekStreak: "flame.fill"
        case .graduate: "graduationcap.fill"
        case .dailyChallenge: "calendar.badge.checkmark"
        case .bigCube: "square.grid.4x3.fill"
        case .scanner: "camera.viewfinder"
        }
    }
}

/// Lessons, achievements, streak and daily results. Small enough to live in
/// user defaults and to sync through iCloud key-value storage.
@Observable
@MainActor
final class ProgressStore {

    struct Snapshot: Codable, Equatable {
        var completedLessons: Set<String> = []
        var achievements: [String: Date] = [:]
        var activeDays: Set<String> = []
        var dailyTimes: [String: Double] = [:]
    }

    private(set) var completedLessons: Set<LessonID> = []
    private(set) var achievements: [Achievement: Date] = [:]
    private(set) var activeDays: Set<String> = []
    private(set) var dailyTimes: [String: Double] = [:]

    static let storageKey = "progress.v1"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: ((Data) -> Void)?
    @ObservationIgnored var calendar = Calendar(identifier: .gregorian)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            load(snapshot)
        }
    }

    var snapshot: Snapshot {
        Snapshot(completedLessons: Set(completedLessons.map(\.rawValue)),
                 achievements: Dictionary(uniqueKeysWithValues: achievements.map { ($0.key.rawValue, $0.value) }),
                 activeDays: activeDays,
                 dailyTimes: dailyTimes)
    }

    private func load(_ snapshot: Snapshot) {
        completedLessons = Set(snapshot.completedLessons.compactMap(LessonID.init(rawValue:)))
        achievements = Dictionary(uniqueKeysWithValues: snapshot.achievements.compactMap { key, date in
            Achievement(rawValue: key).map { ($0, date) }
        })
        activeDays = snapshot.activeDays
        dailyTimes = snapshot.dailyTimes
    }

    /// Merges progress from another device: nothing learnt is ever lost.
    func merge(_ data: Data) {
        guard let remote = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        var merged = snapshot
        merged.completedLessons.formUnion(remote.completedLessons)
        merged.achievements.merge(remote.achievements) { min($0, $1) }
        merged.activeDays.formUnion(remote.activeDays)
        merged.dailyTimes.merge(remote.dailyTimes) { min($0, $1) }
        guard merged != snapshot else { return }
        load(merged)
        persist()
    }

    func reset() {
        load(Snapshot())
        persist()
    }

    /// Clears solve-related progress only (used by "reset statistics").
    func resetStatistics() {
        dailyTimes = [:]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
        onChange?(data)
    }

    // MARK: Events

    /// Marks a lesson as done; returns achievements unlocked by it.
    @discardableResult
    func completeLesson(_ lesson: LessonID, on date: Date = .now) -> [Achievement] {
        completedLessons.insert(lesson)
        var unlocked = markActive(on: date)
        if lesson == .whiteCross { unlocked += unlock(.firstCross, on: date) }
        let beginner = LessonID.allCases.filter { $0.section != .cfop }
        if beginner.allSatisfy(completedLessons.contains) { unlocked += unlock(.graduate, on: date) }
        persist()
        return unlocked
    }

    func uncompleteLesson(_ lesson: LessonID) {
        completedLessons.remove(lesson)
        persist()
    }

    /// Records a finished solve; returns achievements unlocked by it.
    @discardableResult
    func recordSolve(time: TimeInterval, size: Int, isDaily: Bool, on date: Date = .now) -> [Achievement] {
        var unlocked = markActive(on: date)
        unlocked += unlock(.firstSolve, on: date)
        if size == 3 && time < 120 { unlocked += unlock(.underTwoMinutes, on: date) }
        if size == 3 && time < 60 { unlocked += unlock(.underOneMinute, on: date) }
        if size >= 4 { unlocked += unlock(.bigCube, on: date) }
        if isDaily {
            let key = dayKey(date)
            dailyTimes[key] = min(dailyTimes[key] ?? .infinity, time)
            unlocked += unlock(.dailyChallenge, on: date)
        }
        persist()
        return unlocked
    }

    @discardableResult
    func recordScan(on date: Date = .now) -> [Achievement] {
        let unlocked = unlock(.scanner, on: date)
        persist()
        return unlocked
    }

    private func markActive(on date: Date) -> [Achievement] {
        activeDays.insert(dayKey(date))
        return streak(asOf: date) >= 7 ? unlock(.weekStreak, on: date) : []
    }

    private func unlock(_ achievement: Achievement, on date: Date) -> [Achievement] {
        guard achievements[achievement] == nil else { return [] }
        achievements[achievement] = date
        return [achievement]
    }

    // MARK: Queries

    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Consecutive active days ending today (or yesterday, if today is still empty).
    func streak(asOf date: Date = .now) -> Int {
        var day = date
        if !activeDays.contains(dayKey(day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  activeDays.contains(dayKey(yesterday)) else { return 0 }
            day = yesterday
        }
        var count = 0
        while activeDays.contains(dayKey(day)), count < 3650 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func dailyTime(on date: Date = .now) -> Double? { dailyTimes[dayKey(date)] }

    /// Share of lessons completed, 0…1.
    var lessonProgress: Double {
        Double(completedLessons.count) / Double(LessonID.allCases.count)
    }
}
