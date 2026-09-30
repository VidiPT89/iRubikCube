import Foundation

/// A named algorithm, written for white on the bottom and yellow on top.
public struct Algorithm: Hashable, Sendable, Identifiable {
    public let id: String
    public let notation: String

    public init(id: String, notation: String) {
        self.id = id
        self.notation = notation
    }

    public var turns: [Turn] { Notation.turns(notation) }

    /// The same algorithm performed as if `front` were the front face, with
    /// `right` on its right (used to reach the other three slots).
    public func turns(front: Face, right: Face) -> [Turn] {
        Notation.turns(Self.relabel(notation, front: front, right: right))
    }

    static func relabel(_ notation: String, front: Face, right: Face) -> String {
        let map: [Character: Character] = [
            "F": Character(front.letter), "R": Character(right.letter),
            "B": Character(front.opposite.letter), "L": Character(right.opposite.letter),
        ]
        return String(notation.map { map[$0] ?? $0 })
    }
}

public enum Algorithms {
    // Beginner method
    public static let sexy = Algorithm(id: "sexy", notation: "R U R' U'")
    public static let rightInsert = Algorithm(id: "rightInsert", notation: "U R U' R' U' F' U F")
    public static let leftInsert = Algorithm(id: "leftInsert", notation: "U' L' U L U F U' F'")
    public static let yellowCross = Algorithm(id: "yellowCross", notation: "F R U R' U' F'")
    public static let sune = Algorithm(id: "sune", notation: "R U R' U R U2 R'")
    public static let antiSune = Algorithm(id: "antiSune", notation: "R U2 R' U' R U' R'")
    public static let aPermA = Algorithm(id: "aPermA", notation: "R' F R' B2 R F' R' B2 R2")
    public static let aPermB = Algorithm(id: "aPermB", notation: "R2 B2 R F R' B2 R F' R")
    public static let uPermA = Algorithm(id: "uPermA", notation: "R U' R U R U R U' R' U' R2")
    public static let uPermB = Algorithm(id: "uPermB", notation: "R2 U R U R' U' R' U' R' U R'")

    // 2-look OLL
    public static let ollLine = Algorithm(id: "ollLine", notation: "F R U R' U' F'")
    public static let ollAngle = Algorithm(id: "ollAngle", notation: "f R U R' U' f'")
    public static let ollH = Algorithm(id: "ollH", notation: "R U R' U R U' R' U R U2 R'")
    public static let ollPi = Algorithm(id: "ollPi", notation: "R U2 R2 U' R2 U' R2 U2 R")
    public static let ollHeadlights = Algorithm(id: "ollHeadlights", notation: "R2 D R' U2 R D' R' U2 R'")
    public static let ollT = Algorithm(id: "ollT", notation: "r U R' U' r' F R F'")
    public static let ollBowtie = Algorithm(id: "ollBowtie", notation: "F' r U R' U' r' F R")

    // 2-look PLL
    public static let pllT = Algorithm(id: "pllT", notation: "R U R' U' R' F R2 U' R' U' R U R' F'")
    public static let pllY = Algorithm(id: "pllY", notation: "F R U' R' U' R U R' F' R U R' U' R' F R F'")
    public static let pllH = Algorithm(id: "pllH", notation: "M2 U M2 U2 M2 U M2")
    public static let pllZ = Algorithm(id: "pllZ", notation: "M' U M2 U M2 U M' U2 M2")

    public static let ollEdges = [ollLine, ollAngle]
    public static let ollCorners = [sune, antiSune, ollH, ollPi, ollHeadlights, ollT, ollBowtie]
    public static let pllCorners = [pllT, pllY]
    public static let pllEdges = [uPermA, uPermB, pllH, pllZ]

    public static let all: [Algorithm] = [
        sexy, rightInsert, leftInsert, yellowCross, sune, antiSune, aPermA, aPermB, uPermA, uPermB,
        ollAngle, ollH, ollPi, ollHeadlights, ollT, ollBowtie, pllT, pllY, pllH, pllZ,
    ]

    public static func named(_ id: String) -> Algorithm? { all.first { $0.id == id } }
}

extension Turn {
    /// Merges neighbouring turns of the same layers (`U U` → `U2`, `R R'` → nothing).
    public static func simplify(_ turns: [Turn]) -> [Turn] {
        var result: [Turn] = []
        for turn in turns {
            if let last = result.last, last.axis == turn.axis, last.layers == turn.layers {
                result.removeLast()
                let merged = Turn(axis: turn.axis, layers: turn.layers, quarters: last.quarters + turn.quarters)
                if merged.quarters != 0 { result.append(merged) }
            } else {
                result.append(turn)
            }
        }
        return result
    }
}
