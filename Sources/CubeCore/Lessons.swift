import Foundation

/// The course, in teaching order. Texts live in the app; this file only
/// knows what each lesson practises and how to set up its cube.
public enum LessonID: String, CaseIterable, Sendable, Codable, Identifiable {
    case anatomy, notation
    case whiteCross, whiteCorners, middleEdges, yellowCross, yellowFace, yellowCorners, yellowEdges
    case f2l, oll, pll

    public var id: String { rawValue }

    public enum Section: Int, CaseIterable, Sendable {
        case basics, beginner, cfop
    }

    public var section: Section {
        switch self {
        case .anatomy, .notation: .basics
        case .f2l, .oll, .pll: .cfop
        default: .beginner
        }
    }

    /// The beginner stage a lesson teaches, if any.
    public var stage: BeginnerStage? {
        switch self {
        case .whiteCross: .whiteCross
        case .whiteCorners: .whiteCorners
        case .middleEdges: .middleEdges
        case .yellowCross: .yellowCross
        case .yellowFace: .yellowFace
        case .yellowCorners: .yellowCorners
        case .yellowEdges: .yellowEdges
        default: nil
        }
    }

    public var algorithms: [Algorithm] {
        switch self {
        case .anatomy, .notation, .whiteCross: []
        case .whiteCorners: [Algorithms.sexy]
        case .middleEdges: [Algorithms.rightInsert, Algorithms.leftInsert]
        case .yellowCross: [Algorithms.yellowCross]
        case .yellowFace: [Algorithms.sune, Algorithms.antiSune]
        case .yellowCorners: [Algorithms.aPermA, Algorithms.aPermB]
        case .yellowEdges: [Algorithms.uPermA, Algorithms.uPermB]
        case .f2l: [Algorithms.sexy, Algorithms.rightInsert, Algorithms.leftInsert]
        case .oll: Algorithms.ollEdges + Algorithms.ollCorners
        case .pll: Algorithms.pllCorners + Algorithms.pllEdges
        }
    }

    public var hasPractice: Bool { section != .basics }
}

/// Sets up practice cubes, checks when a lesson's goal is reached and
/// suggests the next moves.
public enum LessonCoach {

    /// A cube (white at the bottom) that needs exactly this lesson's step.
    public static func practiceCase<G: RandomNumberGenerator>(for lesson: LessonID, using rng: inout G) -> CubeState? {
        guard lesson.hasPractice else { return nil }
        for _ in 0..<50 {
            let cube = makeCase(for: lesson, using: &rng)
            if !isGoalReached(lesson, in: cube) { return cube }
        }
        return nil
    }

    public static func practiceCase(for lesson: LessonID) -> CubeState? {
        var rng = SystemRandomNumberGenerator()
        return practiceCase(for: lesson, using: &rng)
    }

    private static func makeCase<G: RandomNumberGenerator>(for lesson: LessonID, using rng: inout G) -> CubeState {
        let held = CubeState(size: 3).applying(.rotation(.x, 2))
        switch lesson {
        case .oll:
            let edges = Algorithms.ollEdges.randomElement(using: &rng) ?? Algorithms.ollLine
            let corners = Algorithms.ollCorners.randomElement(using: &rng) ?? Algorithms.sune
            var turns = inverse(of: corners.turns) + randomAdjustment(using: &rng)
            if Bool.random(using: &rng) { turns += inverse(of: edges.turns) }
            return held.applying(randomAdjustment(using: &rng) + turns)
        case .pll:
            let corners = Algorithms.pllCorners.randomElement(using: &rng) ?? Algorithms.pllT
            let edges = Algorithms.pllEdges.randomElement(using: &rng) ?? Algorithms.uPermA
            var turns = inverse(of: edges.turns) + randomAdjustment(using: &rng)
            if Bool.random(using: &rng) { turns += inverse(of: corners.turns) }
            return held.applying(randomAdjustment(using: &rng) + turns)
        default:
            var cube = CubeState(size: 3).applying(Scrambler.scramble(size: 3, using: &rng))
            cube.apply(BeginnerSolver.holdRotation(for: cube))
            let target: BeginnerStage = lesson == .f2l ? .whiteCorners : (lesson.stage ?? .whiteCross)
            for stage in BeginnerStage.teaching where stage < target {
                _ = BeginnerSolver.solveStage(stage, cube: &cube)
            }
            return cube
        }
    }

    public static func isGoalReached(_ lesson: LessonID, in cube: CubeState) -> Bool {
        let held = cube.applying(BeginnerSolver.holdRotation(for: cube))
        switch lesson {
        case .anatomy, .notation: return true
        case .f2l: return BeginnerSolver.isComplete(.middleEdges, in: held)
        case .oll: return BeginnerSolver.isComplete(.yellowFace, in: held)
        case .pll: return held.isSolved
        default: return BeginnerSolver.isComplete(lesson.stage ?? .solved, in: held)
        }
    }

    /// Suggested moves from `cube` until the lesson's goal is reached.
    public static func suggestion(for lesson: LessonID, from cube: CubeState) -> [Turn] {
        guard cube.size == 3, (try? CubieCube(state: cube)) != nil, !isGoalReached(lesson, in: cube) else { return [] }
        var working = cube
        var turns = BeginnerSolver.holdRotation(for: working)
        working.apply(turns)

        switch lesson {
        case .oll where BeginnerSolver.isComplete(.middleEdges, in: working):
            turns += lastLayer(working, algorithms: lesson.algorithms, depth: 4) { BeginnerSolver.isComplete(.yellowFace, in: $0) }
            return turns
        case .pll where BeginnerSolver.isComplete(.yellowFace, in: working):
            turns += lastLayer(working, algorithms: lesson.algorithms, depth: 5) { $0.isSolved }
            return turns
        default:
            break
        }

        let target: BeginnerStage = switch lesson {
        case .f2l: .middleEdges
        case .oll: .yellowFace
        case .pll: .yellowEdges
        default: lesson.stage ?? .yellowEdges
        }
        let current = BeginnerSolver.stage(of: working)
        for stage in BeginnerStage.teaching where stage >= current && stage <= target {
            turns += BeginnerSolver.solveStage(stage, cube: &working).flatMap(\.turns)
        }
        return turns
    }

    private static func lastLayer(_ cube: CubeState, algorithms: [Algorithm], depth: Int,
                                  goal: (CubeState) -> Bool) -> [Turn] {
        let macros = BeginnerSolver.adjustments + algorithms.map { BeginnerSolver.Macro(turns: $0.turns, algorithm: $0.id) }
        return Turn.simplify(BeginnerSolver.macroSearch(cube, macros: macros, maxDepth: depth, goal: goal)?.flatMap(\.turns) ?? [])
    }

    static func inverse(of turns: [Turn]) -> [Turn] { turns.reversed().map(\.inverse) }

    private static func randomAdjustment<G: RandomNumberGenerator>(using rng: inout G) -> [Turn] {
        let amount = Int.random(in: 0..<4, using: &rng)
        return amount == 0 ? [] : [.face(.U, amount == 3 ? -1 : amount)]
    }
}

/// WCA-style averages: drop the best and worst, average the rest.
public enum Statistics {
    public static func average(of count: Int, in times: [TimeInterval]) -> TimeInterval? {
        guard count >= 3, times.count >= count else { return nil }
        let window = times.suffix(count).sorted()
        let trimmed = window.dropFirst().dropLast()
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    public static func best(in times: [TimeInterval]) -> TimeInterval? { times.min() }

    public static func mean(of times: [TimeInterval]) -> TimeInterval? {
        times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
    }
}
