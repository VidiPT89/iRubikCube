import Foundation
import Synchronization

/// An N×N×N cube as a flat list of sticker colours.
///
/// Stickers are stored face by face in the order U R F D L B, each face
/// row by row as it appears in the standard net, so a 3×3 state reads
/// exactly like a Kociemba facelet string.
public struct CubeState: Hashable, Sendable, Codable {
    public let size: Int
    public private(set) var stickers: [CubeColor]

    public static let supportedSizes = 2...5

    /// A solved cube in the standard colour scheme.
    public init(size: Int = 3) {
        precondition(Self.supportedSizes.contains(size), "Unsupported cube size \(size)")
        self.size = size
        stickers = Face.allCases.flatMap { face in
            Array(repeating: CubeColor.standard(for: face), count: size * size)
        }
    }

    /// Builds a cube from explicit stickers; returns `nil` if the count is wrong.
    public init?(size: Int, stickers: [CubeColor]) {
        guard Self.supportedSizes.contains(size), stickers.count == 6 * size * size else { return nil }
        self.size = size
        self.stickers = stickers
    }

    public var perFace: Int { size * size }

    public static func index(face: Face, row: Int, col: Int, size: Int) -> Int {
        face.rawValue * size * size + row * size + col
    }

    public subscript(face: Face, row: Int, col: Int) -> CubeColor {
        get { stickers[Self.index(face: face, row: row, col: col, size: size)] }
        set { stickers[Self.index(face: face, row: row, col: col, size: size)] = newValue }
    }

    public func stickers(of face: Face) -> ArraySlice<CubeColor> {
        let start = face.rawValue * perFace
        return stickers[start..<(start + perFace)]
    }

    /// Centre colour of a face. Even cubes have no fixed centre, so the
    /// colour that fills most of the face is returned instead.
    public func center(of face: Face) -> CubeColor {
        if size % 2 == 1 { return self[face, size / 2, size / 2] }
        var counts = [Int](repeating: 0, count: 6)
        for color in stickers(of: face) { counts[color.rawValue] += 1 }
        return CubeColor(rawValue: counts.indices.max { counts[$0] < counts[$1] } ?? 0) ?? .white
    }

    /// Every face shows a single colour (orientation does not matter).
    public var isSolved: Bool {
        Face.allCases.allSatisfy { face in
            let slice = stickers(of: face)
            return slice.allSatisfy { $0 == slice.first }
        }
    }

    // MARK: Turning

    public mutating func apply(_ turn: Turn) {
        guard turn.quarters != 0 else { return }
        let destination = StickerGeometry.of(size).permutation(for: turn)
        var next = stickers
        for i in stickers.indices {
            next[destination[i]] = stickers[i]
        }
        stickers = next
    }

    public mutating func apply(_ turns: [Turn]) {
        for turn in turns { apply(turn) }
    }

    public func applying(_ turn: Turn) -> CubeState {
        var copy = self
        copy.apply(turn)
        return copy
    }

    public func applying(_ turns: [Turn]) -> CubeState {
        var copy = self
        copy.apply(turns)
        return copy
    }

    /// Compact text form, one colour letter per sticker (W R G Y O B).
    public var colorString: String { String(stickers.map(\.letter)) }

    public init?(size: Int, colorString: String) {
        let colors = colorString.compactMap(CubeColor.init(letter:))
        guard colors.count == colorString.count else { return nil }
        self.init(size: size, stickers: colors)
    }
}

/// Where every sticker sits in space, shared by all states of one size.
public final class StickerGeometry: Sendable {
    public let size: Int
    /// Doubled coordinates of each sticker's centre on the cube surface.
    public let positions: [Vec3]
    public let faces: [Face]
    private let lookup: [Vec3: Int]
    private let cache = Mutex<[Turn: [Int]]>([:])

    private static let shared: [Int: StickerGeometry] = Dictionary(
        uniqueKeysWithValues: CubeState.supportedSizes.map { ($0, StickerGeometry(size: $0)) }
    )

    public static func of(_ size: Int) -> StickerGeometry {
        guard let geometry = shared[size] else { preconditionFailure("Unsupported cube size \(size)") }
        return geometry
    }

    private init(size: Int) {
        self.size = size
        var positions: [Vec3] = []
        var faces: [Face] = []
        for face in Face.allCases {
            for row in 0..<size {
                for col in 0..<size {
                    let across = 2 * col - (size - 1)
                    let downward = 2 * row - (size - 1)
                    positions.append(size * face.normal + across * face.right + downward * face.down)
                    faces.append(face)
                }
            }
        }
        self.positions = positions
        self.faces = faces
        var lookup: [Vec3: Int] = [:]
        for (index, position) in positions.enumerated() {
            lookup[position] = index
        }
        self.lookup = lookup
    }

    /// Cubie coordinate (doubled) of the piece a sticker belongs to.
    public func cubie(of sticker: Int) -> Vec3 {
        positions[sticker] - faces[sticker].normal
    }

    /// Layer index of a doubled cubie coordinate along an axis.
    public func layer(ofCoordinate c: Int) -> Int { (c + size - 1) / 2 }

    public func index(of position: Vec3) -> Int? { lookup[position] }

    /// `result[i]` is where sticker `i` travels to under `turn`.
    public func permutation(for turn: Turn) -> [Int] {
        if let cached = cache.withLock({ $0[turn] }) { return cached }
        var destination = Array(positions.indices)
        for (i, position) in positions.enumerated() {
            let layer = layer(ofCoordinate: cubie(of: i)[turn.axis])
            guard turn.layers.contains(layer) else { continue }
            let moved = position.rotated(about: turn.axis, quarters: turn.quarters)
            guard let target = lookup[moved] else { preconditionFailure("Sticker left the cube") }
            destination[i] = target
        }
        cache.withLock { $0[turn] = destination }
        return destination
    }
}
