import Testing
@testable import CubeCore

@Suite("Validation")
struct ValidationTests {

    private func swapStickers(_ state: CubeState, _ a: Int, _ b: Int) -> CubeState {
        var stickers = state.stickers
        stickers.swapAt(a, b)
        return CubeState(size: 3, stickers: stickers)!
    }

    @Test("A twisted corner is impossible")
    func twisted() {
        let corner = CubieCube.cornerFacelets[0]
        var stickers = CubeState().stickers
        let (a, b, c) = (stickers[corner[0]], stickers[corner[1]], stickers[corner[2]])
        stickers[corner[0]] = c
        stickers[corner[1]] = a
        stickers[corner[2]] = b
        let state = CubeState(size: 3, stickers: stickers)!
        #expect(throws: CubeValidationError.twistedCorner) { try CubieCube(state: state) }
    }

    @Test("A flipped edge is impossible")
    func flipped() {
        let edge = CubieCube.edgeFacelets[0]
        let state = swapStickers(CubeState(), edge[0], edge[1])
        #expect(throws: CubeValidationError.flippedEdge) { try CubieCube(state: state) }
    }

    @Test("Two swapped edges break parity")
    func parity() {
        var cube = CubieCube.solved
        cube.ep.swapAt(0, 1)
        #expect(throws: CubeValidationError.parity) { try cube.validate() }
        #expect(throws: CubeValidationError.parity) { try CubieCube(state: cube.facelets()) }
    }

    @Test("Wrong colour counts are caught")
    func colourCount() {
        var stickers = CubeState().stickers
        stickers[0] = .red
        let state = CubeState(size: 3, stickers: stickers)!
        #expect(throws: CubeValidationError.wrongColorCount(.white)) { try CubieCube(state: state) }
    }

    @Test("Two centres of the same colour are caught")
    func centres() {
        let state = swapStickers(CubeState(), 4, 10)
        #expect(throws: CubeValidationError.self) { try CubieCube(state: state) }
    }

    @Test("Non-existent pieces are caught")
    func impossiblePiece() {
        // White on both stickers of an edge and green twice elsewhere.
        var stickers = CubeState().stickers
        let edge = CubieCube.edgeFacelets[1]
        let other = CubieCube.edgeFacelets[3]
        stickers[edge[1]] = .white
        stickers[other[0]] = .green
        let state = CubeState(size: 3, stickers: stickers)!
        #expect(throws: CubeValidationError.self) { try CubieCube(state: state) }
    }

    @Test("Scrambled cubes are always valid")
    func scrambledValid() throws {
        for _ in 0..<100 {
            _ = try CubieCube(state: CubeState().applying(Scrambler.scramble()))
        }
    }
}

@Suite("Lessons")
struct LessonTests {

    @Test("Each practice lesson sets up its own case", arguments: LessonID.allCases.filter(\.hasPractice))
    func casesAreReady(lesson: LessonID) throws {
        for _ in 0..<15 {
            let cube = try #require(LessonCoach.practiceCase(for: lesson))
            _ = try CubieCube(state: cube)
            #expect(cube.center(of: .D) == .white, "White held at the bottom")
            #expect(!LessonCoach.isGoalReached(lesson, in: cube))
            if let stage = lesson.stage {
                #expect(BeginnerSolver.stage(of: cube) == stage, "Earlier stages must be done")
            }
            if lesson == .oll || lesson == .pll {
                #expect(BeginnerSolver.isComplete(.middleEdges, in: cube), "F2L stays solved")
            }
            if lesson == .pll {
                #expect(BeginnerSolver.isComplete(.yellowFace, in: cube), "Last layer stays oriented")
            }
            let suggestion = LessonCoach.suggestion(for: lesson, from: cube)
            #expect(!suggestion.isEmpty)
            #expect(LessonCoach.isGoalReached(lesson, in: cube.applying(suggestion)), "\(lesson) suggestion reaches the goal")
        }
    }

    @Test("Last-layer algorithms keep the first two layers", arguments: Algorithms.all.filter { $0.id != "sexy" && !$0.id.contains("Insert") })
    func algorithmsKeepF2L(algorithm: Algorithm) {
        let held = CubeState().applying(.rotation(.x, 2))
        let after = held.applying(algorithm.turns)
        #expect(BeginnerSolver.isComplete(.middleEdges, in: after), "\(algorithm.id)")
        #expect(!after.isSolved, "\(algorithm.id) should change something")
    }

    @Test("PLL algorithms keep the last layer oriented", arguments: Algorithms.pllCorners + Algorithms.pllEdges + [Algorithms.aPermA, Algorithms.aPermB])
    func pllKeepsOrientation(algorithm: Algorithm) {
        let held = CubeState().applying(.rotation(.x, 2))
        #expect(BeginnerSolver.isComplete(.yellowFace, in: held.applying(algorithm.turns)), "\(algorithm.id)")
    }

    @Test("Averages drop the best and the worst time")
    func averages() {
        let times: [Double] = [10, 12, 11, 30, 9]
        #expect(Statistics.average(of: 5, in: times) == 11)
        #expect(Statistics.average(of: 12, in: times) == nil)
        #expect(Statistics.best(in: times) == 9)
    }
}
