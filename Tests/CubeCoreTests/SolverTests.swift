import Foundation
import Testing
@testable import CubeCore

@Suite("Solvers", .serialized)
struct SolverTests {

    @Test("Cubie model agrees with the facelet model")
    func cubieMatchesFacelets() throws {
        for _ in 0..<200 {
            let scramble = Scrambler.scramble(size: 3)
            let state = CubeState().applying(scramble)
            var cubie = CubieCube.solved
            for turn in scramble {
                let positive = turn.layers.contains(2)
                let face = try #require(Face.allCases.first { $0.axis == turn.axis && $0.isPositive == positive })
                let clockwise = positive ? -turn.quarters : turn.quarters
                cubie.apply(face: face, power: clockwise)
            }
            #expect(try CubieCube(state: state) == cubie)
            #expect(cubie.facelets() == state)
        }
    }

    @Test("Coordinates round-trip")
    func coordinates() {
        var cube = CubieCube.solved
        for value in stride(from: 0, to: 2187, by: 37) {
            cube.twist = value
            #expect(cube.twist == value)
        }
        for value in stride(from: 0, to: 2048, by: 31) {
            cube.flip = value
            #expect(cube.flip == value)
        }
        for value in stride(from: 0, to: 11880, by: 97) {
            cube.sliceCoordinate = value
            #expect(cube.sliceCoordinate == value)
        }
        for value in stride(from: 0, to: 20160, by: 101) {
            cube.cornerCoordinate = value
            #expect(cube.cornerCoordinate == value)
            cube.udEdgeCoordinate = value
            #expect(cube.udEdgeCoordinate == value)
        }
        #expect(CubieCube.solved.cornerCoordinate == 0)
        #expect(CubieCube.solved.udEdgeCoordinate == 0)
    }

    @Test("Two-phase solves 1000 random scrambles")
    func twoPhaseThousand() throws {
        var lengths: [Int] = []
        let clock = ContinuousClock()
        _ = TwoPhaseTables.shared
        let elapsed = try clock.measure {
            for _ in 0..<1000 {
                let state = CubeState().applying(Scrambler.scramble(size: 3))
                let solution = try TwoPhaseSolver.solve(state)
                #expect(state.applying(solution).isSolved)
                lengths.append(solution.count)
            }
        }
        let average = Double(lengths.reduce(0, +)) / Double(lengths.count)
        #expect(average <= 22.5, "Average length \(average)")
        #expect(lengths.max() ?? 0 <= 25)
        #expect(elapsed < .seconds(120), "Took \(elapsed)")
    }

    @Test("Two-phase handles rotated cubes and slice moves")
    func rotatedCube() throws {
        let state = CubeState().applying(Notation.turns("x y2 M E' S R U F'"))
        let solution = try TwoPhaseSolver.solve(state)
        #expect(state.applying(solution).isSolved)
    }

    @Test("Solved cube needs no moves")
    func solved() throws {
        #expect(try TwoPhaseSolver.solve(CubeState()).isEmpty)
    }

    @Test("Beginner method solves random scrambles stage by stage")
    func beginner() throws {
        for _ in 0..<150 {
            let state = CubeState().applying(Scrambler.scramble(size: 3))
            let steps = try BeginnerSolver.solve(state)
            var cube = state
            var lastStage = BeginnerStage.holdCube
            for step in steps {
                #expect(step.stage >= lastStage, "Stages must come in order")
                if step.stage > lastStage && lastStage != .holdCube {
                    #expect(BeginnerSolver.isComplete(lastStage, in: cube), "\(lastStage) left incomplete")
                }
                lastStage = step.stage
                cube.apply(step.turns)
            }
            #expect(cube.isSolved)
            #expect(BeginnerSolver.stage(of: cube) == .solved)
        }
    }

    @Test("Where am I: stage detection")
    func stageDetection() {
        #expect(BeginnerSolver.stage(of: CubeState()) == .solved)
        let broken = CubeState().applying(Notation.turns("x2 R U R' U'"))
        #expect(BeginnerSolver.stage(of: broken) == .whiteCorners)
        let lastLayer = CubeState().applying(Notation.turns("x2") + Algorithms.uPermA.turns)
        #expect(BeginnerSolver.stage(of: lastLayer) == .yellowEdges)
    }
}
