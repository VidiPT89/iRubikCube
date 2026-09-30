import Foundation

/// Small, fast, seedable generator (SplitMix64), so a daily challenge is the
/// same on every device.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// WCA-style random-move scrambles: no face turned twice in a row and no
/// three turns on the same axis in a row (so `R L R` never appears).
public enum Scrambler {

    public static func defaultLength(for size: Int) -> Int {
        switch size {
        case 2: 11
        case 3: 25
        default: 40
        }
    }

    public static func scramble(size: Int = 3, length: Int? = nil) -> [Turn] {
        var rng = SystemRandomNumberGenerator()
        return scramble(size: size, length: length, using: &rng)
    }

    public static func scramble<G: RandomNumberGenerator>(size: Int, length: Int? = nil,
                                                          using rng: inout G) -> [Turn] {
        let count = length ?? defaultLength(for: size)
        // 2×2 scrambles only need three faces; the others would just rotate the puzzle.
        let faces: [Face] = size == 2 ? [.R, .U, .F] : Face.allCases
        let allowWide = size >= 4
        var result: [Turn] = []
        var history: [Face] = []

        while result.count < count {
            guard let face = faces.randomElement(using: &rng) else { break }
            if let last = history.last {
                if last == face { continue }
                if history.count >= 2, history[history.count - 2].axis == face.axis, last.axis == face.axis {
                    continue
                }
            }
            let amount = [1, 2, -1].randomElement(using: &rng) ?? 1
            let wide = allowWide && face.isPositive && Int.random(in: 0..<3, using: &rng) == 0
            var turn = Turn.face(face, amount, size: size)
            if wide {
                turn = Turn(axis: face.axis,
                            layers: LayerSet([size - 1, size - 2]),
                            quarters: -amount)
            }
            result.append(turn)
            history.append(face)
        }
        return result
    }

    /// Scramble of the day, identical for everybody on the same calendar date.
    public static func daily(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Turn] {
        var rng = SeededGenerator(seed: dailySeed(for: date, calendar: calendar))
        return scramble(size: 3, length: 20, using: &rng)
    }

    public static func dailySeed(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = (parts.year ?? 2026) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
        return UInt64(key) &* 0x2545_F491_4F6C_DD1D
    }
}
