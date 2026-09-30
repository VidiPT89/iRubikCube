import Foundation
import Testing
@testable import CubeCore

@Suite("Moves")
struct MoveTests {

    static let basicTokens = ["R", "L", "U", "D", "F", "B", "M", "E", "S", "x", "y", "z", "Rw", "Uw", "Fw"]

    @Test("Every move done four times is the identity", arguments: [2, 3, 4])
    func fourTimesIsIdentity(size: Int) throws {
        for token in Self.basicTokens {
            if size == 2 && ["M", "E", "S"].contains(token) { continue }
            let turn = try Notation.parseToken(token, size: size)
            var cube = CubeState(size: size).applying(Scrambler.scramble(size: size))
            let start = cube
            for _ in 0..<4 { cube.apply(turn) }
            #expect(cube == start, "\(token) ×4 on \(size)×\(size)")
        }
    }

    @Test("X followed by X' is the identity", arguments: [2, 3, 4])
    func moveThenInverse(size: Int) throws {
        for token in Self.basicTokens {
            if size == 2 && ["M", "E", "S"].contains(token) { continue }
            let turn = try Notation.parseToken(token, size: size)
            let prime = try Notation.parseToken(token + "'", size: size)
            let start = CubeState(size: size).applying(Scrambler.scramble(size: size))
            #expect(start.applying([turn, prime]) == start, "\(token) \(token)' on \(size)×\(size)")
            #expect(prime == turn.inverse)
        }
    }

    @Test("A half turn equals two quarter turns")
    func halfTurn() throws {
        let start = CubeState().applying(Scrambler.scramble())
        for face in Face.allCases {
            #expect(start.applying(.face(face, 2)) == start.applying([.face(face), .face(face)]))
        }
    }

    @Test("R moves the front stickers up")
    func rDirection() {
        let cube = CubeState().applying(.face(.R))
        // Right column of U now shows the front colour (green).
        #expect(cube[.U, 0, 2] == .green)
        #expect(cube[.U, 2, 2] == .green)
        // Right column of F now shows the bottom colour (yellow).
        #expect(cube[.F, 1, 2] == .yellow)
        #expect(cube[.U, 1, 1] == .white)
    }

    @Test("U moves the front stickers to the left")
    func uDirection() {
        let cube = CubeState().applying(.face(.U))
        #expect(cube[.L, 0, 1] == .green)
        #expect(cube[.F, 0, 1] == .red)
    }

    @Test("Sexy move six times is the identity")
    func sexySix() {
        let turns = Array(repeating: Algorithms.sexy.turns, count: 6).flatMap { $0 }
        #expect(CubeState().applying(turns).isSolved)
    }

    @Test("Scrambles follow WCA move rules", arguments: [2, 3, 4])
    func scrambleRules(size: Int) {
        for _ in 0..<200 {
            let turns = Scrambler.scramble(size: size)
            #expect(turns.count == Scrambler.defaultLength(for: size))
            for i in 1..<turns.count {
                let sameFace = turns[i].axis == turns[i - 1].axis
                    && turns[i].layers.contains(size - 1) == turns[i - 1].layers.contains(size - 1)
                #expect(!sameFace, "Same face twice in a row")
                if i >= 2 {
                    #expect(!(turns[i].axis == turns[i - 1].axis && turns[i - 1].axis == turns[i - 2].axis))
                }
            }
        }
    }

    @Test("The daily scramble is the same all day and changes the next day")
    func dailyScramble() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 22))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 8))!
        #expect(Scrambler.daily(for: morning, calendar: calendar) == Scrambler.daily(for: evening, calendar: calendar))
        #expect(Scrambler.daily(for: morning, calendar: calendar) != Scrambler.daily(for: tomorrow, calendar: calendar))
    }

    @Test("Simplify merges and cancels neighbouring turns")
    func simplify() {
        let turns = Notation.turns("U U R R' F2 F2 D")
        #expect(Notation.format(Turn.simplify(turns)) == "U2 D")
    }
}
