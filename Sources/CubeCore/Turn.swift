import Foundation

/// A set of layer indices along one axis. Layer 0 is on the negative side
/// (L, D or B) and layer `size - 1` on the positive side (R, U or F).
public struct LayerSet: Hashable, Sendable, Codable {
    public var mask: UInt16

    public init(mask: UInt16) { self.mask = mask }

    public init<S: Sequence>(_ layers: S) where S.Element == Int {
        mask = layers.reduce(0) { $0 | (1 << UInt16($1)) }
    }

    public static func single(_ layer: Int) -> LayerSet { LayerSet([layer]) }
    public static func all(_ size: Int) -> LayerSet { LayerSet(0..<size) }

    public func contains(_ layer: Int) -> Bool { mask & (1 << UInt16(layer)) != 0 }

    public func layers(size: Int) -> [Int] { (0..<size).filter(contains) }
}

/// One physical turn of the cube: some layers along an axis rotated by a
/// number of quarter turns. Positive quarters are counter-clockwise when
/// looking from the positive end of the axis, so `R` is `-1` on layer
/// `size - 1` of the x axis and `L` is `+1` on layer 0.
public struct Turn: Hashable, Sendable, Codable {
    public var axis: Axis
    public var layers: LayerSet
    /// One of -2, -1, 1 or 2. A half turn keeps its sign only to choose the
    /// direction it is animated in.
    public var quarters: Int

    public init(axis: Axis, layers: LayerSet, quarters: Int) {
        self.axis = axis
        self.layers = layers
        self.quarters = Turn.normalise(quarters)
    }

    public var inverse: Turn { Turn(axis: axis, layers: layers, quarters: -quarters) }

    public var isHalfTurn: Bool { abs(quarters) == 2 }

    /// Two turns do the same thing when they move the same layers by the same
    /// amount (a clockwise and an anticlockwise half turn are equal).
    public func isEquivalent(to other: Turn) -> Bool {
        axis == other.axis && layers == other.layers
            && (quarters == other.quarters || (isHalfTurn && other.isHalfTurn))
    }

    public func isWholeCube(size: Int) -> Bool { layers == .all(size) }

    static func normalise(_ q: Int) -> Int {
        switch ((q % 4) + 4) % 4 {
        case 1: 1
        case 2: q < 0 ? -2 : 2
        case 3: -1
        default: 0
        }
    }

    // MARK: Named turns

    /// The outer layer of `face`, clockwise as seen from that face, `amount`
    /// times (1, 2, or -1 for prime).
    public static func face(_ face: Face, _ amount: Int = 1, size: Int = 3) -> Turn {
        let layer = face.isPositive ? size - 1 : 0
        let sign = face.isPositive ? -1 : 1
        return Turn(axis: face.axis, layers: .single(layer), quarters: sign * amount)
    }

    /// Whole-cube rotation `x`, `y` or `z`, `amount` times.
    public static func rotation(_ axis: Axis, _ amount: Int = 1, size: Int = 3) -> Turn {
        Turn(axis: axis, layers: .all(size), quarters: -amount)
    }
}
