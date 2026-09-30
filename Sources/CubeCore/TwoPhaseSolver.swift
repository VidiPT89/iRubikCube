import Foundation

/// Kociemba's two-phase algorithm. Phase one brings the cube into the
/// subgroup ⟨U, D, R2, F2, L2, B2⟩; phase two solves it with those moves only.
/// Usually finds a solution of 22 moves or fewer in well under a second.
public enum TwoPhaseSolver {

    /// Returns the face turns that solve a 3×3 `state`, in the frame given by
    /// its current centres.
    public static func solve(_ state: CubeState, maxLength: Int = 22,
                             timeLimit: Duration = .seconds(1.5)) throws(CubeValidationError) -> [Turn] {
        let cube = try CubieCube(state: state)
        let tables = TwoPhaseTables.shared
        if cube == .solved { return [] }

        let attempts: [(Int, Duration?)] = [(maxLength, timeLimit), (maxLength + 3, timeLimit), (30, nil)]
        for (length, limit) in attempts {
            let search = TwoPhaseSearch(tables: tables, maxTotal: length, timeLimit: limit)
            if let moves = search.run(cube) {
                return moves.map { index in
                    let face = Face.allCases[index / 3]
                    let amount = [1, 2, -1][index % 3]
                    return Turn.face(face, amount)
                }
            }
        }
        preconditionFailure("A valid cube always has a solution of 30 moves or fewer")
    }
}

final class TwoPhaseSearch {
    private let t: TwoPhaseTables
    private let maxTotal: Int
    private let deadline: ContinuousClock.Instant?
    private var path1 = [Int](repeating: 0, count: 32)
    private var path2 = [Int](repeating: 0, count: 32)
    private var solution: [Int]?
    private var nodes = 0
    private var timedOut = false
    private var start = (twist: 0, flip: 0, slice: 0, corner: 0, urToUl: 0, ubToDf: 0, parity: 0)

    init(tables: TwoPhaseTables, maxTotal: Int, timeLimit: Duration?) {
        t = tables
        self.maxTotal = maxTotal
        deadline = timeLimit.map { ContinuousClock.now + $0 }
    }

    func run(_ cube: CubieCube) -> [Int]? {
        start = (cube.twist, cube.flip, cube.sliceCoordinate, cube.cornerCoordinate,
                 cube.urToUl, cube.ubToDf, cube.cornerParity)
        for depth in 0...min(12, maxTotal) {
            if phase1(twist: start.twist, flip: start.flip, slice: start.slice,
                      depth: 0, remaining: depth, lastFace: -1) {
                return solution
            }
            if timedOut { return nil }
        }
        return nil
    }

    private func checkClock() -> Bool {
        nodes += 1
        if nodes & 0x3FF == 0, let deadline, ContinuousClock.now > deadline {
            timedOut = true
        }
        return timedOut
    }

    /// Two turns in a row on the same face, or on opposite faces in the
    /// "wrong" order, only repeat work.
    @inline(__always)
    private func isRedundant(face: Int, after lastFace: Int) -> Bool {
        lastFace >= 0 && (face == lastFace || face == lastFace - 3)
    }

    private func phase1(twist: Int, flip: Int, slice: Int, depth: Int, remaining: Int, lastFace: Int) -> Bool {
        if checkClock() { return false }
        if remaining == 0 {
            guard twist == 0, flip == 0, slice / 24 == t.goalSlice1 else { return false }
            // A phase-one path ending in a phase-two move is covered by a shorter one.
            if depth > 0, TwoPhaseTables.isPhase2Move[path1[depth - 1]] { return false }
            return startPhase2(length1: depth)
        }
        for face in 0..<6 where !isRedundant(face: face, after: lastFace) {
            for power in 0..<3 {
                let m = face * 3 + power
                let nextTwist = Int(t.twistMove[twist * 18 + m])
                let nextFlip = Int(t.flipMove[flip * 18 + m])
                let nextSlice = Int(t.sliceMove[slice * 18 + m])
                let slice1 = nextSlice / 24
                let estimate = max(Int(t.pruneSliceTwist[nextTwist * TwoPhaseTables.slice1Count + slice1]),
                                   Int(t.pruneSliceFlip[nextFlip * TwoPhaseTables.slice1Count + slice1]))
                if estimate > remaining - 1 { continue }
                path1[depth] = m
                if phase1(twist: nextTwist, flip: nextFlip, slice: nextSlice,
                          depth: depth + 1, remaining: remaining - 1, lastFace: face) {
                    return true
                }
                if timedOut { return false }
            }
        }
        return false
    }

    private func startPhase2(length1: Int) -> Bool {
        var corner = start.corner
        var slice = start.slice
        var urToUl = start.urToUl
        var ubToDf = start.ubToDf
        var parity = start.parity
        for i in 0..<length1 {
            let m = path1[i]
            corner = Int(t.cornerMove[corner * 18 + m])
            slice = Int(t.sliceMove[slice * 18 + m])
            urToUl = Int(t.urToUlMove[urToUl * 18 + m])
            ubToDf = Int(t.ubToDfMove[ubToDf * 18 + m])
            parity ^= TwoPhaseTables.parityFlip[m]
        }
        guard let edges = CubieCube.mergedUDEdges(urToUl: urToUl, ubToDf: ubToDf), edges < 20160 else {
            return false
        }
        let slice2 = slice - t.goalSlice1 * 24
        let limit = min(maxTotal >= 30 ? 18 : 12, maxTotal - length1)
        let estimate = phase2Estimate(corner: corner, edges: edges, slice2: slice2, parity: parity)
        guard estimate <= limit else { return false }
        let lastFace = length1 > 0 ? path1[length1 - 1] / 3 : -1
        for depth in estimate...limit {
            if phase2(corner: corner, edges: edges, slice2: slice2, parity: parity,
                      depth: 0, remaining: depth, lastFace: lastFace) {
                solution = Array(path1[0..<length1]) + Array(path2[0..<depth])
                return true
            }
            if timedOut { return false }
        }
        return false
    }

    @inline(__always)
    private func phase2Estimate(corner: Int, edges: Int, slice2: Int, parity: Int) -> Int {
        max(Int(t.pruneCornerSlice[((slice2 * 20160 + corner) << 1) | parity]),
            Int(t.pruneEdgeSlice[((slice2 * 20160 + edges) << 1) | parity]))
    }

    private func phase2(corner: Int, edges: Int, slice2: Int, parity: Int,
                        depth: Int, remaining: Int, lastFace: Int) -> Bool {
        if remaining == 0 {
            return corner == 0 && edges == 0 && slice2 == 0
        }
        if checkClock() { return false }
        let base = t.goalSlice1 * 24
        for m in TwoPhaseTables.phase2Moves {
            let face = m / 3
            if isRedundant(face: face, after: lastFace) { continue }
            let nextCorner = Int(t.cornerMove[corner * 18 + m])
            let nextEdges = Int(t.udEdgeMove[edges * 18 + m])
            let nextSlice = Int(t.sliceMove[(base + slice2) * 18 + m]) - base
            let nextParity = parity ^ TwoPhaseTables.parityFlip[m]
            let estimate = phase2Estimate(corner: nextCorner, edges: nextEdges, slice2: nextSlice, parity: nextParity)
            if estimate > remaining - 1 { continue }
            path2[depth] = m
            if phase2(corner: nextCorner, edges: nextEdges, slice2: nextSlice, parity: nextParity,
                      depth: depth + 1, remaining: remaining - 1, lastFace: face) {
                return true
            }
        }
        return false
    }
}
