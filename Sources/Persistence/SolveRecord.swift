import Foundation
import SwiftData

/// One finished solve in Play mode.
@Model
final class SolveRecord {
    var date: Date
    var duration: TimeInterval
    var moveCount: Int
    var size: Int
    var scramble: String
    var solution: String
    var isDaily: Bool

    init(date: Date = .now, duration: TimeInterval, moveCount: Int, size: Int,
         scramble: String, solution: String, isDaily: Bool = false) {
        self.date = date
        self.duration = duration
        self.moveCount = moveCount
        self.size = size
        self.scramble = scramble
        self.solution = solution
        self.isDaily = isDaily
    }
}

enum SolveStore {
    /// Falls back to an in-memory store instead of crashing if the file is damaged.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([SolveRecord.self])
        if !inMemory {
            try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema)) {
                return container
            }
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not create even an in-memory store: \(error)")
        }
    }
}
