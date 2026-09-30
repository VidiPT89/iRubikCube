import Foundation

/// The layer-by-layer stages, in the order they are taught.
public enum BeginnerStage: Int, CaseIterable, Sendable, Codable, Comparable {
    case holdCube, whiteCross, whiteCorners, middleEdges, yellowCross, yellowFace, yellowCorners, yellowEdges, solved

    public static func < (a: BeginnerStage, b: BeginnerStage) -> Bool { a.rawValue < b.rawValue }

    /// The seven teaching stages (without "hold the cube" and "solved").
    public static let teaching: [BeginnerStage] = [
        .whiteCross, .whiteCorners, .middleEdges, .yellowCross, .yellowFace, .yellowCorners, .yellowEdges,
    ]
}

/// One explained chunk of a beginner solution: the turns that place one
/// piece, or one algorithm with the U turns that line it up.
public struct SolveStep: Hashable, Sendable {
    public var stage: BeginnerStage
    public var turns: [Turn]
    /// Colours of the piece being placed (empty on the last layer).
    public var piece: [CubeColor]
    public var algorithm: String?

    public init(stage: BeginnerStage, turns: [Turn], piece: [CubeColor] = [], algorithm: String? = nil) {
        self.stage = stage
        self.turns = turns
        self.piece = piece
        self.algorithm = algorithm
    }
}

public enum BeginnerSolver {

    /// Whole-cube rotations tried, in order, to bring white to the bottom.
    static let holdRotations: [[Turn]] = [
        [], [.rotation(.x, -1)], [.rotation(.x, 1)], [.rotation(.x, 2)], [.rotation(.z, 1)], [.rotation(.z, -1)],
    ]

    /// Rotation that puts the white centre on D.
    public static func holdRotation(for state: CubeState) -> [Turn] {
        holdRotations.first { state.applying($0).center(of: .D) == .white } ?? []
    }

    /// First stage that is not complete yet (evaluated with white at the bottom).
    public static func stage(of state: CubeState) -> BeginnerStage {
        guard state.size == 3 else { return state.isSolved ? .solved : .whiteCross }
        let held = state.applying(holdRotation(for: state))
        for stage in BeginnerStage.teaching where !isComplete(stage, in: held) {
            return stage
        }
        return .solved
    }

    /// Full layer-by-layer solution. Throws if the state is not a real cube.
    public static func solve(_ state: CubeState) throws(CubeValidationError) -> [SolveStep] {
        _ = try CubieCube(state: state)
        var cube = state
        var steps: [SolveStep] = []
        let hold = holdRotation(for: cube)
        if !hold.isEmpty {
            steps.append(SolveStep(stage: .holdCube, turns: hold))
            cube.apply(hold)
        }
        for stage in BeginnerStage.teaching {
            steps += solveStage(stage, cube: &cube)
        }
        return steps
    }

    /// Steps for one stage; `cube` must already hold white at the bottom and
    /// have every earlier stage complete.
    public static func solveStage(_ stage: BeginnerStage, cube: inout CubeState) -> [SolveStep] {
        switch stage {
        case .holdCube, .solved: []
        case .whiteCross: solveCross(&cube)
        case .whiteCorners: solveCorners(&cube)
        case .middleEdges: solveMiddleEdges(&cube)
        case .yellowCross:
            solveLastLayer(&cube, stage: stage, algorithms: [Algorithms.yellowCross], depth: 5)
        case .yellowFace:
            solveLastLayer(&cube, stage: stage, algorithms: [Algorithms.sune, Algorithms.antiSune], depth: 7)
        case .yellowCorners:
            solveLastLayer(&cube, stage: stage, algorithms: [Algorithms.aPermA, Algorithms.aPermB], depth: 5)
        case .yellowEdges:
            solveLastLayer(&cube, stage: stage, algorithms: [Algorithms.uPermA, Algorithms.uPermB], depth: 6)
        }
    }

    // MARK: Stage goals

    static let sideFaces: [Face] = [.F, .R, .B, .L]
    static let crossEdges: [[Face]] = sideFaces.map { [.D, $0] }
    static let bottomCorners: [[Face]] = (0..<4).map { [.D, sideFaces[$0], sideFaces[($0 + 1) % 4]] }
    static let middleEdges: [[Face]] = (0..<4).map { [sideFaces[$0], sideFaces[($0 + 1) % 4]] }
    static let topEdges: [[Face]] = sideFaces.map { [.U, $0] }
    static let topCorners: [[Face]] = (0..<4).map { [.U, sideFaces[$0], sideFaces[($0 + 1) % 4]] }

    public static func isComplete(_ stage: BeginnerStage, in cube: CubeState) -> Bool {
        switch stage {
        case .holdCube: return cube.center(of: .D) == .white
        case .whiteCross: return crossEdges.allSatisfy(cube.isPieceSolved)
        case .whiteCorners: return isComplete(.whiteCross, in: cube) && bottomCorners.allSatisfy(cube.isPieceSolved)
        case .middleEdges: return isComplete(.whiteCorners, in: cube) && middleEdges.allSatisfy(cube.isPieceSolved)
        case .yellowCross:
            let top = cube.center(of: .U)
            return isComplete(.middleEdges, in: cube)
                && topEdges.allSatisfy { cube[cube.stickerIndex(of: $0, on: .U)] == top }
        case .yellowFace:
            let top = cube.center(of: .U)
            return isComplete(.middleEdges, in: cube) && cube.stickers(of: .U).allSatisfy { $0 == top }
        case .yellowCorners:
            return isComplete(.yellowFace, in: cube) && topCorners.allSatisfy(cube.isPieceSolved)
        case .yellowEdges, .solved:
            return cube.isSolved
        }
    }

    // MARK: Cross (tracked stickers, IDA*)

    static let faceTurns: [Turn] = Face.allCases.flatMap { face in [1, 2, -1].map { Turn.face(face, $0) } }

    private static func solveCross(_ cube: inout CubeState) -> [SolveStep] {
        let geometry = StickerGeometry.of(3)
        let permutations = faceTurns.map(geometry.permutation(for:))
        var steps: [SolveStep] = []
        var targets: [Int] = []
        var distances: [[UInt8]] = []

        for edge in crossEdges {
            let side = edge[1]
            let colors = [cube.center(of: .D), cube.center(of: side)]
            let target = cube.stickerIndex(of: edge, on: .D)
            targets.append(target)
            distances.append(stickerDistances(to: target, permutations: permutations))
            if cube.isPieceSolved(edge) { continue }

            var positions: [Int] = []
            for (i, done) in crossEdges.prefix(targets.count).enumerated() {
                let pieceColors = [cube.center(of: .D), cube.center(of: done[1])]
                positions.append(cube.locateSticker(color: pieceColors[0], partner: pieceColors[1]) ?? targets[i])
            }
            let path = idaStar(positions: positions, targets: targets, distances: distances,
                               permutations: permutations, maxDepth: 10) ?? []
            let turns = path.map { faceTurns[$0] }
            cube.apply(turns)
            steps.append(SolveStep(stage: .whiteCross, turns: turns, piece: colors))
        }
        return steps
    }

    /// Moves needed to bring a single sticker to `target`, for every start.
    static func stickerDistances(to target: Int, permutations: [[Int]]) -> [UInt8] {
        var distance = [UInt8](repeating: .max, count: 54)
        distance[target] = 0
        var frontier = [target]
        var depth: UInt8 = 0
        while !frontier.isEmpty {
            var next: [Int] = []
            for index in frontier {
                for permutation in permutations where distance[permutation[index]] == .max {
                    distance[permutation[index]] = depth + 1
                    next.append(permutation[index])
                }
            }
            frontier = next
            depth += 1
        }
        return distance
    }

    private static func idaStar(positions: [Int], targets: [Int], distances: [[UInt8]],
                                permutations: [[Int]], maxDepth: Int) -> [Int]? {
        func estimate(_ p: [Int]) -> Int {
            p.indices.reduce(0) { max($0, Int(distances[$1][p[$1]])) }
        }
        var path: [Int] = []

        func search(_ p: [Int], remaining: Int, lastFace: Int) -> Bool {
            let h = estimate(p)
            if h == 0 { return true }
            if h > remaining { return false }
            for move in 0..<permutations.count {
                let face = move / 3
                if face == lastFace || face == lastFace - 3 { continue }
                let next = p.map { permutations[move][$0] }
                path.append(move)
                if search(next, remaining: remaining - 1, lastFace: face) { return true }
                path.removeLast()
            }
            return false
        }

        for bound in estimate(positions)...maxDepth where search(positions, remaining: bound, lastFace: -1) {
            return path
        }
        return nil
    }

    // MARK: Macro search (corners, middle edges, last layer)

    struct Macro {
        let turns: [Turn]
        let permutation: [Int]
        let isAdjustment: Bool
        let algorithm: String?

        init(turns: [Turn], isAdjustment: Bool = false, algorithm: String? = nil) {
            self.turns = turns
            self.isAdjustment = isAdjustment
            self.algorithm = algorithm
            let geometry = StickerGeometry.of(3)
            var composed = Array(0..<54)
            for turn in turns {
                let step = geometry.permutation(for: turn)
                composed = composed.map { step[$0] }
            }
            permutation = composed
        }

        func applied(to cube: CubeState) -> CubeState {
            var stickers = cube.stickers
            for i in stickers.indices { stickers[permutation[i]] = cube.stickers[i] }
            return CubeState(size: 3, stickers: stickers) ?? cube
        }
    }

    static let adjustments: [Macro] = [1, 2, -1].map { Macro(turns: [.face(.U, $0)], isAdjustment: true) }

    static func macroSearch(_ cube: CubeState, macros: [Macro], maxDepth: Int,
                            goal: (CubeState) -> Bool) -> [Macro]? {
        var path: [Macro] = []
        func search(_ state: CubeState, remaining: Int, lastWasAdjustment: Bool) -> Bool {
            if goal(state) { return true }
            guard remaining > 0 else { return false }
            for macro in macros {
                if macro.isAdjustment && lastWasAdjustment { continue }
                path.append(macro)
                if search(macro.applied(to: state), remaining: remaining - 1, lastWasAdjustment: macro.isAdjustment) {
                    return true
                }
                path.removeLast()
            }
            return false
        }
        for depth in 0...maxDepth where search(cube, remaining: depth, lastWasAdjustment: false) {
            return path
        }
        return nil
    }

    private static func solveCorners(_ cube: inout CubeState) -> [SolveStep] {
        var macros = adjustments
        for k in 0..<4 {
            let front = sideFaces[k]
            let right = sideFaces[(k + 1) % 4]
            let once = Algorithms.sexy.turns(front: front, right: right)
            for repeats in 1...5 {
                macros.append(Macro(turns: Array(repeating: once, count: repeats).flatMap { $0 },
                                    algorithm: Algorithms.sexy.id))
            }
        }
        var solved = crossEdges
        var steps: [SolveStep] = []
        for corner in bottomCorners {
            solved.append(corner)
            let keep = solved
            let colors = corner.map { cube.center(of: $0) }
            guard !cube.isPieceSolved(corner),
                  let path = macroSearch(cube, macros: macros, maxDepth: 3, goal: { state in keep.allSatisfy(state.isPieceSolved) })
            else { continue }
            let turns = Turn.simplify(path.flatMap(\.turns))
            cube.apply(turns)
            steps.append(SolveStep(stage: .whiteCorners, turns: turns, piece: colors, algorithm: Algorithms.sexy.id))
        }
        return steps
    }

    private static func solveMiddleEdges(_ cube: inout CubeState) -> [SolveStep] {
        var macros = adjustments
        for k in 0..<4 {
            let front = sideFaces[k]
            let right = sideFaces[(k + 1) % 4]
            macros.append(Macro(turns: Algorithms.rightInsert.turns(front: front, right: right),
                                algorithm: Algorithms.rightInsert.id))
            macros.append(Macro(turns: Algorithms.leftInsert.turns(front: front, right: right),
                                algorithm: Algorithms.leftInsert.id))
        }
        var solved = crossEdges + bottomCorners
        var steps: [SolveStep] = []
        for edge in middleEdges {
            solved.append(edge)
            let keep = solved
            let colors = edge.map { cube.center(of: $0) }
            guard !cube.isPieceSolved(edge),
                  let path = macroSearch(cube, macros: macros, maxDepth: 4, goal: { state in keep.allSatisfy(state.isPieceSolved) })
            else { continue }
            let turns = Turn.simplify(path.flatMap(\.turns))
            cube.apply(turns)
            let algorithm = path.last { !$0.isAdjustment }?.algorithm
            steps.append(SolveStep(stage: .middleEdges, turns: turns, piece: colors, algorithm: algorithm))
        }
        return steps
    }

    /// Solves a last-layer stage with U turns plus the given algorithms,
    /// one explained step per algorithm.
    static func solveLastLayer(_ cube: inout CubeState, stage: BeginnerStage,
                               algorithms: [Algorithm], depth: Int) -> [SolveStep] {
        guard !isComplete(stage, in: cube) else { return [] }
        let macros = adjustments + algorithms.map { Macro(turns: $0.turns, algorithm: $0.id) }
        guard let path = macroSearch(cube, macros: macros, maxDepth: depth, goal: { isComplete(stage, in: $0) }) else {
            return []
        }
        var steps: [SolveStep] = []
        var pending: [Turn] = []
        for macro in path {
            if macro.isAdjustment {
                pending += macro.turns
            } else {
                steps.append(SolveStep(stage: stage, turns: Turn.simplify(pending + macro.turns), algorithm: macro.algorithm))
                pending = []
            }
        }
        if !pending.isEmpty {
            if steps.isEmpty {
                steps.append(SolveStep(stage: stage, turns: pending))
            } else {
                steps[steps.count - 1].turns = Turn.simplify(steps[steps.count - 1].turns + pending)
            }
        }
        for step in steps { cube.apply(step.turns) }
        return steps
    }
}

// MARK: - Piece helpers (3×3)

extension CubeState {

    /// Index of the sticker on `face` of the piece touching `faces`.
    public func stickerIndex(of faces: [Face], on face: Face) -> Int {
        let geometry = StickerGeometry.of(size)
        let reach = size - 1
        var cubie = Vec3(0, 0, 0)
        for f in faces { cubie = cubie + reach * f.normal }
        guard let index = geometry.index(of: cubie + face.normal) else {
            preconditionFailure("No sticker on \(face) for piece \(faces)")
        }
        return index
    }

    public subscript(index: Int) -> CubeColor { stickers[index] }

    /// Each sticker of the piece matches the centre of its face.
    public func isPieceSolved(_ faces: [Face]) -> Bool {
        faces.allSatisfy { self[stickerIndex(of: faces, on: $0)] == center(of: $0) }
    }

    /// Index of the `color` sticker on the edge whose other sticker is `partner`.
    public func locateSticker(color: CubeColor, partner: CubeColor) -> Int? {
        for edge in CubieCube.edgeFacelets {
            if stickers[edge[0]] == color && stickers[edge[1]] == partner { return edge[0] }
            if stickers[edge[1]] == color && stickers[edge[0]] == partner { return edge[1] }
        }
        return nil
    }
}
