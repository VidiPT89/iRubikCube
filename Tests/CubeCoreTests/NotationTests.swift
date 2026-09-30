import Testing
@testable import CubeCore

@Suite("Notation")
struct NotationTests {

    @Test("Parses faces, primes and doubles")
    func basics() throws {
        let turns = try Notation.parse("R U R' U' F2 B2'")
        #expect(turns == [.face(.R), .face(.U), .face(.R, -1), .face(.U, -1), .face(.F, 2), .face(.B, 2)])
    }

    @Test("Parses slices and rotations")
    func slicesAndRotations() throws {
        let turns = try Notation.parse("M E S x y' z2")
        #expect(turns.count == 6)
        #expect(turns[0] == Turn(axis: .x, layers: .single(1), quarters: 1))
        #expect(turns[3] == .rotation(.x))
        #expect(turns[4] == .rotation(.y, -1))
        #expect(turns[5].isWholeCube(size: 3))
    }

    @Test("M follows L, E follows D, S follows F")
    func sliceDirections() throws {
        let m = try Notation.parseToken("M", size: 3)
        let l = Turn.face(.L)
        #expect(m.quarters == l.quarters)
        let s = try Notation.parseToken("S", size: 3)
        #expect(s.quarters == Turn.face(.F).quarters)
    }

    @Test("Tolerates extra spaces, new lines, brackets and typographic primes")
    func whitespace() throws {
        let turns = try Notation.parse("  R   U’\n (R' U')  ")
        #expect(turns.count == 4)
        #expect(turns[1] == .face(.U, -1))
    }

    @Test("Wide moves: Rw, r and 3Rw")
    func wide() throws {
        #expect(try Notation.parseToken("Rw", size: 3) == Turn(axis: .x, layers: LayerSet([1, 2]), quarters: -1))
        #expect(try Notation.parseToken("r", size: 3) == Notation.parseToken("Rw", size: 3))
        #expect(try Notation.parseToken("3Rw", size: 4) == Turn(axis: .x, layers: LayerSet([1, 2, 3]), quarters: -1))
        #expect(try Notation.parseToken("2R", size: 4) == Turn(axis: .x, layers: .single(2), quarters: -1))
    }

    @Test("Rejects unknown tokens", arguments: ["Q", "R3", "RR", "w", "2x", "M4", ""])
    func errors(token: String) {
        #expect(throws: Notation.ParseError.self) { try Notation.parseToken(token, size: 3) }
    }

    @Test("Rejects slices on a 2×2")
    func sliceOnTwo() {
        #expect(throws: Notation.ParseError.self) { try Notation.parseToken("M", size: 2) }
    }

    @Test("Formatting round-trips", arguments: [2, 3, 4])
    func roundTrip(size: Int) throws {
        for _ in 0..<50 {
            let turns = Scrambler.scramble(size: size)
            let text = Notation.format(turns, size: size)
            #expect(try Notation.parse(text, size: size) == turns, "\(text)")
        }
        var tokens = ["R", "L'", "U2", "x", "y'", "z2", "Rw", "Lw'"]
        if size >= 3 { tokens += ["M", "E'", "S2"] }
        for token in tokens {
            let turn = try Notation.parseToken(token, size: size)
            #expect(try Notation.parseToken(Notation.format(turn, size: size), size: size) == turn, "\(token)")
        }
    }

    @Test("Inner layers of a 4×4 are named from the closer face")
    func innerLayers() {
        #expect(Notation.format(Turn(axis: .x, layers: .single(2), quarters: -1), size: 4) == "2R")
        #expect(Notation.format(Turn(axis: .x, layers: .single(1), quarters: 1), size: 4) == "2L")
        #expect(Notation.format(Turn(axis: .y, layers: LayerSet([1, 2]), quarters: 1), size: 4) == "E")
    }
}
