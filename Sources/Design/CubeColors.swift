import CubeCore
import SwiftUI
import UIKit

/// Sticker colours for the two cube schemes. The high-contrast scheme uses
/// the Okabe–Ito colour-blind-safe palette and adds a symbol to each colour.
enum CubeScheme: String, CaseIterable, Identifiable, Sendable {
    case standard, highContrast

    var id: String { rawValue }

    func uiColor(_ color: CubeColor) -> UIColor {
        UIColor(rgb: hex(color))
    }

    func color(_ color: CubeColor) -> Color {
        Color(hex: hex(color))
    }

    private func hex(_ color: CubeColor) -> UInt32 {
        switch self {
        case .standard:
            switch color {
            case .white: 0xF4F4EF
            case .yellow: 0xFFD320
            case .red: 0xD62631
            case .orange: 0xFF7B0A
            case .blue: 0x1460D8
            case .green: 0x17A55A
            }
        case .highContrast:
            switch color {
            case .white: 0xFFFFFF
            case .yellow: 0xF0E442
            case .red: 0xC7361B
            case .orange: 0xE69F00
            case .blue: 0x0072B2
            case .green: 0x009E73
            }
        }
    }

    /// Symbol drawn on high-contrast stickers, so colour is never the only cue.
    static func glyph(for color: CubeColor) -> Glyph {
        switch color {
        case .white: .none
        case .yellow: .circle
        case .red: .plus
        case .orange: .bar
        case .blue: .diamond
        case .green: .square
        }
    }

    enum Glyph: Sendable {
        case none, circle, plus, bar, diamond, square

        var systemImage: String? {
            switch self {
            case .none: nil
            case .circle: "circle.fill"
            case .plus: "plus"
            case .bar: "minus"
            case .diamond: "diamond.fill"
            case .square: "square.fill"
            }
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A single sticker drawn in 2D (nets, previews, lesson diagrams).
struct StickerSwatch: View {
    let color: CubeColor
    let scheme: CubeScheme
    var size: CGFloat = 28
    var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(scheme.color(color))
            .overlay {
                if scheme == .highContrast, let symbol = CubeScheme.glyph(for: color).systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.38, weight: .black))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.25 : 1)
    }
}
