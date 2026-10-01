import SwiftUI

/// The ividi.dev identity: amber orange, burnt yellow and near-black.
/// Every colour in the app comes from here, never from a view.
struct Palette: Sendable {
    let background: Color
    let backgroundDeep: Color
    let surface: Color
    let surfaceRaised: Color
    let stroke: Color
    let primary: Color
    /// Middle stop of the brand gradient (fills, never small text).
    let brandMid: Color
    let amber: Color
    let deep: Color
    let hot: Color
    let text: Color
    let textDim: Color
    let textFaint: Color
    let success: Color
    let danger: Color
    let isDark: Bool

    static let dark = Palette(
        background: Color(hex: 0x0A0A0F),
        backgroundDeep: Color(hex: 0x050508),
        surface: Color(hex: 0x14141A),
        surfaceRaised: Color(hex: 0x1D1D25),
        stroke: Color.white.opacity(0.08),
        primary: Color(hex: 0xF99C00),
        brandMid: Color(hex: 0xF99C00),
        amber: Color(hex: 0xFCBB00),
        deep: Color(hex: 0xDD7400),
        hot: Color(hex: 0xFE6E00),
        text: Color(hex: 0xF5F1EA),
        textDim: Color(hex: 0xA9A39B),
        textFaint: Color(hex: 0x66615B),
        success: Color(hex: 0x3DD68C),
        danger: Color(hex: 0xFF5A4E),
        isDark: true
    )

    static let light = Palette(
        background: Color(hex: 0xFBF6EE),
        backgroundDeep: Color(hex: 0xF3EADC),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xF5EDE1),
        stroke: Color.black.opacity(0.07),
        // Darker than the brand amber so text in it passes WCAG AA on the warm white.
        primary: Color(hex: 0xAD5600),
        brandMid: Color(hex: 0xF28A00),
        amber: Color(hex: 0xF5A800),
        deep: Color(hex: 0x8F4500),
        hot: Color(hex: 0xE25F00),
        text: Color(hex: 0x17140F),
        textDim: Color(hex: 0x645B51),
        textFaint: Color(hex: 0x8A8073),
        success: Color(hex: 0x1C8F55),
        danger: Color(hex: 0xC8372A),
        isDark: false
    )

    static func resolve(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    /// The signature gradient: burnt yellow into amber into deep orange.
    var brandGradient: LinearGradient {
        LinearGradient(colors: [amber, brandMid, hot], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var textGradient: LinearGradient {
        LinearGradient(colors: [amber, primary, deep], startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: Typography

extension Font {
    /// SF Pro Rounded, for titles and numbers that should feel friendly.
    /// Sizes map onto the nearest text style, so everything follows Dynamic Type.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        scaled(size, weight: weight, design: .rounded)
    }

    /// SF Mono, for times and notation.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        scaled(size, weight: weight, design: .monospaced)
    }

    /// Text style whose default size is closest to `size`. Very large display
    /// sizes (the timer) stay fixed so they never push the cube off screen.
    static func scaled(_ size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        let style: Font.TextStyle
        switch size {
        case ..<11.5: style = .caption2
        case ..<12.5: style = .caption
        case ..<13.5: style = .footnote
        case ..<15.5: style = .subheadline
        case ..<16.5: style = .callout
        case ..<18.5: style = .body
        case ..<21: style = .title3
        case ..<25: style = .title2
        case ..<31: style = .title
        case ..<40: style = .largeTitle
        default: return .system(size: size, weight: weight, design: design)
        }
        return .system(style, design: design, weight: weight)
    }
}

/// Soft backdrop shared by every screen: near-black (or warm white) with an
/// amber glow from the top.
struct Backdrop: View {
    @Environment(\.palette) private var palette
    var glow: Double = 1

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.background, palette.backgroundDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [palette.primary.opacity((palette.isDark ? 0.22 : 0.16) * glow), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [palette.hot.opacity((palette.isDark ? 0.10 : 0.06) * glow), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
