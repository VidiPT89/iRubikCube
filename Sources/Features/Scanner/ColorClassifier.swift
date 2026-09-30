import CubeCore
import Foundation

/// An averaged camera colour, 0…1 per channel.
struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    var hsv: (h: Double, s: Double, v: Double) {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }

    /// Rough perceptual coordinates (hue on a circle, saturation, value),
    /// good enough to compare stickers under the same light.
    var features: (Double, Double, Double) {
        let (h, s, v) = hsv
        let radians = h * .pi / 180
        return (cos(radians) * s, sin(radians) * s, v * 0.6)
    }
}

/// Turns camera colours into sticker colours.
enum ColorClassifier {

    /// Quick guess for the live preview, from hue and saturation alone.
    static func guess(_ rgb: RGB) -> CubeColor {
        let (h, s, v) = rgb.hsv
        if s < 0.25 && v > 0.45 { return .white }
        switch h {
        case ..<14, 330...: return .red
        case 14..<42: return .orange
        case 42..<75: return .yellow
        case 75..<170: return .green
        case 170..<265: return .blue
        default: return .red
        }
    }

    /// Calibrated pass: each sticker takes the colour of the nearest centre,
    /// since the six centres show every colour under the same lighting.
    static func classify(faces: [Face: [RGB]]) -> [Face: [CubeColor]] {
        var centers: [(CubeColor, (Double, Double, Double))] = []
        for face in Face.allCases {
            guard let samples = faces[face], samples.count == 9 else { continue }
            centers.append((CubeColor.standard(for: face), samples[4].features))
        }
        var result: [Face: [CubeColor]] = [:]
        for (face, samples) in faces {
            result[face] = samples.enumerated().map { index, sample in
                if index == 4 { return CubeColor.standard(for: face) }
                let f = sample.features
                let nearest = centers.min { a, b in distance(a.1, f) < distance(b.1, f) }
                return nearest?.0 ?? guess(sample)
            }
        }
        return result
    }

    private static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dx = a.0 - b.0, dy = a.1 - b.1, dz = a.2 - b.2
        return dx * dx + dy * dy + dz * dz
    }

    /// Order in which faces are scanned, with what should face up in each photo.
    static let scanOrder: [(face: Face, up: Face)] = [
        (.F, .U), (.R, .U), (.B, .U), (.L, .U), (.U, .B), (.D, .F),
    ]
}
