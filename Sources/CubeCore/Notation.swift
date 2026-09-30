import Foundation

/// Reads and writes standard cube notation:
/// `R L U D F B` (outer layers), `M E S` (middle slices), `x y z` (whole
/// cube), `Rw`/`r` (wide), `2R` (second layer on big cubes), with `'` for
/// anticlockwise and `2` for a half turn.
public enum Notation {

    public enum ParseError: Error, Equatable, Sendable {
        case unknownToken(String)
        case unsupportedForSize(String, Int)
    }

    public static func parse(_ text: String, size: Int = 3) throws -> [Turn] {
        try text
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "(" || $0 == ")" })
            .map { try parseToken(String($0), size: size) }
    }

    /// Parses notation that is known to be valid (algorithms baked into the app).
    public static func turns(_ text: String, size: Int = 3) -> [Turn] {
        do {
            return try parse(text, size: size)
        } catch {
            preconditionFailure("Invalid built-in notation: \(text)")
        }
    }

    public static func parseToken(_ raw: String, size: Int) throws -> Turn {
        var token = Substring(raw.replacingOccurrences(of: "’", with: "'"))
        guard !token.isEmpty else { throw ParseError.unknownToken(raw) }

        var amount = 1
        if token.hasSuffix("2'") || token.hasSuffix("'2") {
            amount = 2
            token = token.dropLast(2)
        } else if token.hasSuffix("'") {
            amount = -1
            token = token.dropLast()
        } else if token.hasSuffix("2") && token.count > 1 {
            amount = 2
            token = token.dropLast()
        }

        var depth = 1
        var explicitDepth = false
        if let first = token.first, let digit = first.wholeNumberValue, token.count > 1 {
            depth = digit
            explicitDepth = true
            token = token.dropFirst()
        }

        var wide = false
        if token.hasSuffix("w") && token.count == 2 {
            wide = true
            token = token.dropLast()
            if !explicitDepth { depth = 2 }
        }

        guard token.count == 1, let letter = token.first else { throw ParseError.unknownToken(raw) }

        if let face = Face(letter: letter) {
            return try faceTurn(face, depth: depth, wide: wide, amount: amount, size: size, raw: raw)
        }
        if let face = Face(letter: Character(letter.uppercased())), letter.isLowercase {
            guard depth == 1 else { throw ParseError.unknownToken(raw) }
            return try faceTurn(face, depth: 2, wide: true, amount: amount, size: size, raw: raw)
        }
        guard depth == 1, !wide else { throw ParseError.unknownToken(raw) }

        switch letter {
        case "x": return .rotation(.x, amount, size: size)
        case "y": return .rotation(.y, amount, size: size)
        case "z": return .rotation(.z, amount, size: size)
        case "M", "E", "S":
            guard size >= 3 else { throw ParseError.unsupportedForSize(raw, size) }
            let middle = LayerSet(1..<(size - 1))
            switch letter {
            case "M": return Turn(axis: .x, layers: middle, quarters: amount)
            case "E": return Turn(axis: .y, layers: middle, quarters: amount)
            default: return Turn(axis: .z, layers: middle, quarters: -amount)
            }
        default:
            throw ParseError.unknownToken(raw)
        }
    }

    private static func faceTurn(_ face: Face, depth: Int, wide: Bool, amount: Int,
                                 size: Int, raw: String) throws -> Turn {
        guard depth >= 1, depth <= size else { throw ParseError.unsupportedForSize(raw, size) }
        if !wide && depth > 1 && depth >= size { throw ParseError.unsupportedForSize(raw, size) }
        let fromOuter: [Int] = wide ? Array(0..<depth) : [depth - 1]
        let layers = fromOuter.map { face.isPositive ? size - 1 - $0 : $0 }
        let sign = face.isPositive ? -1 : 1
        return Turn(axis: face.axis, layers: LayerSet(layers), quarters: sign * amount)
    }

    // MARK: Formatting

    public static func format(_ turns: [Turn], size: Int = 3) -> String {
        turns.map { format($0, size: size) }.joined(separator: " ")
    }

    public static func format(_ turn: Turn, size: Int = 3) -> String {
        let layers = turn.layers.layers(size: size)
        let axisFaces: (positive: Face, negative: Face) = switch turn.axis {
        case .x: (.R, .L)
        case .y: (.U, .D)
        case .z: (.F, .B)
        }

        func suffix(clockwiseQuarters q: Int) -> String {
            switch Turn.normalise(q) {
            case 1: ""
            case -1: "'"
            default: "2"
            }
        }

        if layers.count == size {
            let name = switch turn.axis { case .x: "x"; case .y: "y"; case .z: "z" }
            return name + suffix(clockwiseQuarters: -turn.quarters)
        }

        if size >= 3, layers == Array(1..<(size - 1)) {
            switch turn.axis {
            case .x: return "M" + suffix(clockwiseQuarters: turn.quarters)
            case .y: return "E" + suffix(clockwiseQuarters: turn.quarters)
            case .z: return "S" + suffix(clockwiseQuarters: -turn.quarters)
            }
        }

        // Contiguous block touching the positive or negative outer layer.
        if let last = layers.last, last == size - 1, layers == Array((size - layers.count)..<size) {
            let face = axisFaces.positive
            let name = layers.count == 1 ? face.letter : (layers.count == 2 ? "\(face.letter)w" : "\(layers.count)\(face.letter)w")
            return name + suffix(clockwiseQuarters: -turn.quarters)
        }
        if let first = layers.first, first == 0, layers == Array(0..<layers.count) {
            let face = axisFaces.negative
            let name = layers.count == 1 ? face.letter : (layers.count == 2 ? "\(face.letter)w" : "\(layers.count)\(face.letter)w")
            return name + suffix(clockwiseQuarters: turn.quarters)
        }

        // A single inner layer, named from the closer face.
        if layers.count == 1, let layer = layers.first {
            if layer >= size / 2 {
                return "\(size - layer)\(axisFaces.positive.letter)" + suffix(clockwiseQuarters: -turn.quarters)
            }
            return "\(layer + 1)\(axisFaces.negative.letter)" + suffix(clockwiseQuarters: turn.quarters)
        }

        let list = layers.map { String($0 + 1) }.joined(separator: "-")
        return "\(list)\(axisFaces.positive.letter)" + suffix(clockwiseQuarters: -turn.quarters)
    }
}
