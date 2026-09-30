import Foundation

/// Why a 3×3 colour layout cannot be a real, solvable cube.
public enum CubeValidationError: Error, Equatable, Sendable {
    case wrongColorCount(CubeColor)
    case duplicateCenters
    case invalidCorner
    case invalidEdge
    case duplicateCorner
    case duplicateEdge
    case twistedCorner
    case flippedEdge
    case parity
}

/// 3×3 cube at the piece level: which corner and edge sits in each slot
/// and how it is twisted or flipped. Uses the Kociemba conventions, where
/// `cp[i]` is the corner that has moved into position `i`.
public struct CubieCube: Hashable, Sendable {
    public var cp: [Int]
    public var co: [Int]
    public var ep: [Int]
    public var eo: [Int]

    public static let solved = CubieCube(cp: Array(0..<8), co: Array(repeating: 0, count: 8),
                                         ep: Array(0..<12), eo: Array(repeating: 0, count: 12))

    public init(cp: [Int], co: [Int], ep: [Int], eo: [Int]) {
        self.cp = cp
        self.co = co
        self.ep = ep
        self.eo = eo
    }

    // MARK: Facelet layout (URF, UFL, ULB, UBR, DFR, DLF, DBL, DRB / UR … BR)

    static let cornerFacelets: [[Int]] = [
        [8, 9, 20], [6, 18, 38], [0, 36, 47], [2, 45, 11],
        [29, 26, 15], [27, 44, 24], [33, 53, 42], [35, 17, 51],
    ]
    static let cornerFaces: [[Face]] = [
        [.U, .R, .F], [.U, .F, .L], [.U, .L, .B], [.U, .B, .R],
        [.D, .F, .R], [.D, .L, .F], [.D, .B, .L], [.D, .R, .B],
    ]
    static let edgeFacelets: [[Int]] = [
        [5, 10], [7, 19], [3, 37], [1, 46], [32, 16], [28, 25],
        [30, 43], [34, 52], [23, 12], [21, 41], [50, 39], [48, 14],
    ]
    static let edgeFaces: [[Face]] = [
        [.U, .R], [.U, .F], [.U, .L], [.U, .B], [.D, .R], [.D, .F],
        [.D, .L], [.D, .B], [.F, .R], [.F, .L], [.B, .L], [.B, .R],
    ]

    /// Reads a 3×3 state, naming faces by their current centre colours.
    public init(state: CubeState) throws(CubeValidationError) {
        guard state.size == 3 else { throw .invalidCorner }
        var counts = [Int](repeating: 0, count: 6)
        for color in state.stickers { counts[color.rawValue] += 1 }
        if let bad = counts.firstIndex(where: { $0 != 9 }), let color = CubeColor(rawValue: bad) {
            throw .wrongColorCount(color)
        }
        var faceOf = [Face?](repeating: nil, count: 6)
        for face in Face.allCases {
            let color = state.center(of: face)
            guard faceOf[color.rawValue] == nil else { throw .duplicateCenters }
            faceOf[color.rawValue] = face
        }
        let facelets: [Face] = state.stickers.map { faceOf[$0.rawValue] ?? .U }

        var cp = [Int](repeating: -1, count: 8)
        var co = [Int](repeating: 0, count: 8)
        for i in 0..<8 {
            let slots = Self.cornerFacelets[i]
            guard let ori = (0..<3).first(where: { facelets[slots[$0]] == .U || facelets[slots[$0]] == .D }) else {
                throw .invalidCorner
            }
            let second = facelets[slots[(ori + 1) % 3]]
            let third = facelets[slots[(ori + 2) % 3]]
            guard let piece = (0..<8).first(where: {
                Self.cornerFaces[$0][1] == second && Self.cornerFaces[$0][2] == third
                    && Self.cornerFaces[$0][0] == facelets[slots[ori]]
            }) else { throw .invalidCorner }
            cp[i] = piece
            co[i] = ori
        }

        var ep = [Int](repeating: -1, count: 12)
        var eo = [Int](repeating: 0, count: 12)
        for i in 0..<12 {
            let a = facelets[Self.edgeFacelets[i][0]]
            let b = facelets[Self.edgeFacelets[i][1]]
            if let piece = (0..<12).first(where: { Self.edgeFaces[$0] == [a, b] }) {
                ep[i] = piece
                eo[i] = 0
            } else if let piece = (0..<12).first(where: { Self.edgeFaces[$0] == [b, a] }) {
                ep[i] = piece
                eo[i] = 1
            } else {
                throw .invalidEdge
            }
        }
        self.init(cp: cp, co: co, ep: ep, eo: eo)
        try validate()
    }

    public func validate() throws(CubeValidationError) {
        if Set(ep).count != 12 { throw .duplicateEdge }
        if eo.reduce(0, +) % 2 != 0 { throw .flippedEdge }
        if Set(cp).count != 8 { throw .duplicateCorner }
        if co.reduce(0, +) % 3 != 0 { throw .twistedCorner }
        if Self.parity(of: ep) != Self.parity(of: cp) { throw .parity }
    }

    /// Facelets of this cube with each face painted in `colors[face]`.
    public func facelets(colors: (Face) -> CubeColor = CubeColor.standard(for:)) -> CubeState {
        var faces = [Face](repeating: .U, count: 54)
        for face in Face.allCases {
            faces[face.rawValue * 9 + 4] = face
        }
        for i in 0..<8 {
            for k in 0..<3 {
                faces[Self.cornerFacelets[i][(k + co[i]) % 3]] = Self.cornerFaces[cp[i]][k]
            }
        }
        for i in 0..<12 {
            for k in 0..<2 {
                faces[Self.edgeFacelets[i][(k + eo[i]) % 2]] = Self.edgeFaces[ep[i]][k]
            }
        }
        guard let state = CubeState(size: 3, stickers: faces.map(colors)) else {
            preconditionFailure("A 3×3 always has 54 facelets")
        }
        return state
    }

    // MARK: Multiplication

    public mutating func multiply(_ b: CubieCube) {
        var ncp = cp, nco = co, nep = ep, neo = eo
        for i in 0..<8 {
            ncp[i] = cp[b.cp[i]]
            nco[i] = (co[b.cp[i]] + b.co[i]) % 3
        }
        for i in 0..<12 {
            nep[i] = ep[b.ep[i]]
            neo[i] = (eo[b.ep[i]] + b.eo[i]) % 2
        }
        cp = ncp
        co = nco
        ep = nep
        eo = neo
    }

    public mutating func cornerMultiply(_ b: CubieCube) {
        var ncp = cp, nco = co
        for i in 0..<8 {
            ncp[i] = cp[b.cp[i]]
            nco[i] = (co[b.cp[i]] + b.co[i]) % 3
        }
        cp = ncp
        co = nco
    }

    public mutating func edgeMultiply(_ b: CubieCube) {
        var nep = ep, neo = eo
        for i in 0..<12 {
            nep[i] = ep[b.ep[i]]
            neo[i] = (eo[b.ep[i]] + b.eo[i]) % 2
        }
        ep = nep
        eo = neo
    }

    /// The six face quarter turns U R F D L B, derived from the facelet model
    /// so both representations can never disagree.
    public static let moves: [CubieCube] = Face.allCases.map { face in
        let state = CubeState(size: 3).applying(.face(face))
        do {
            return try CubieCube(state: state)
        } catch {
            preconditionFailure("A single face turn is always a valid cube")
        }
    }

    public mutating func apply(face: Face, power: Int) {
        for _ in 0..<(((power % 4) + 4) % 4) {
            multiply(Self.moves[face.rawValue])
        }
    }

    static func parity(of perm: [Int]) -> Int {
        var inversions = 0
        for i in perm.indices {
            for j in (i + 1)..<perm.count where perm[i] > perm[j] {
                inversions += 1
            }
        }
        return inversions % 2
    }

    public var cornerParity: Int { Self.parity(of: cp) }
}
