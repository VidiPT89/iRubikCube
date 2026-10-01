import Foundation

/// The three rotation axes. `x` points to the right face, `y` to the up face
/// and `z` to the front face (a right-handed frame, as seen by the player).
public enum Axis: Int, CaseIterable, Sendable, Codable {
    case x, y, z
}

/// The six faces, in the Kociemba facelet order U R F D L B.
public enum Face: Int, CaseIterable, Sendable, Codable {
    case U, R, F, D, L, B

    public var letter: String {
        switch self {
        case .U: "U"
        case .R: "R"
        case .F: "F"
        case .D: "D"
        case .L: "L"
        case .B: "B"
        }
    }

    public var axis: Axis {
        switch self {
        case .R, .L: .x
        case .U, .D: .y
        case .F, .B: .z
        }
    }

    /// `true` for R, U and F: the faces on the positive side of their axis.
    public var isPositive: Bool { self == .R || self == .U || self == .F }

    public var opposite: Face {
        switch self {
        case .U: .D
        case .D: .U
        case .R: .L
        case .L: .R
        case .F: .B
        case .B: .F
        }
    }

    public var normal: Vec3 {
        switch self {
        case .U: Vec3(0, 1, 0)
        case .R: Vec3(1, 0, 0)
        case .F: Vec3(0, 0, 1)
        case .D: Vec3(0, -1, 0)
        case .L: Vec3(-1, 0, 0)
        case .B: Vec3(0, 0, -1)
        }
    }

    /// Screen "right" when looking straight at the face in the standard net.
    public var right: Vec3 {
        switch self {
        case .U, .F, .D: Vec3(1, 0, 0)
        case .R: Vec3(0, 0, -1)
        case .L: Vec3(0, 0, 1)
        case .B: Vec3(-1, 0, 0)
        }
    }

    /// Screen "down" when looking straight at the face in the standard net.
    public var down: Vec3 {
        switch self {
        case .U: Vec3(0, 0, 1)
        case .D: Vec3(0, 0, -1)
        case .R, .F, .L, .B: Vec3(0, -1, 0)
        }
    }

    public init?(letter: Character) {
        switch letter {
        case "U": self = .U
        case "R": self = .R
        case "F": self = .F
        case "D": self = .D
        case "L": self = .L
        case "B": self = .B
        default: return nil
        }
    }
}

/// The six sticker colours of the standard (Western) colour scheme.
public enum CubeColor: Int, CaseIterable, Sendable, Codable {
    case white, red, green, yellow, orange, blue

    /// Solved-cube colour of each face: white up, green front, red right.
    public static func standard(for face: Face) -> CubeColor {
        switch face {
        case .U: .white
        case .R: .red
        case .F: .green
        case .D: .yellow
        case .L: .orange
        case .B: .blue
        }
    }
}

/// A small integer vector. Sticker and cubie positions use doubled
/// coordinates so that every cube size lands on whole numbers.
public struct Vec3: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(_ x: Int, _ y: Int, _ z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public subscript(axis: Axis) -> Int {
        switch axis {
        case .x: x
        case .y: y
        case .z: z
        }
    }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (k: Int, v: Vec3) -> Vec3 { Vec3(k * v.x, k * v.y, k * v.z) }

    /// Rotates by `quarters` × 90° about `axis`, counter-clockwise when
    /// looking from the positive end of the axis (right-hand rule).
    public func rotated(about axis: Axis, quarters: Int) -> Vec3 {
        var v = self
        let steps = ((quarters % 4) + 4) % 4
        for _ in 0..<steps {
            switch axis {
            case .x: v = Vec3(v.x, -v.z, v.y)
            case .y: v = Vec3(v.z, v.y, -v.x)
            case .z: v = Vec3(-v.y, v.x, v.z)
            }
        }
        return v
    }
}
