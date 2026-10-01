import SwiftUI

/// Springy press feedback for every tappable surface.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// A frosted panel used over the 3D scene and for grouped content.
struct GlassCard<Content: View>: View {
    @Environment(\.palette) private var palette
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(palette.surface.opacity(palette.isDark ? 0.45 : 0.55))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
    }
}

/// Main call to action, filled with the brand gradient.
struct PrimaryButton: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.rounded(16, .bold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Color(hex: 0x0A0A0F))
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(palette.brandGradient, in: Capsule())
            .shadow(color: palette.primary.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 6)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.pressable)
    }
}

/// Secondary action: tinted capsule.
struct SecondaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var systemImage: String?
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.rounded(15, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(palette.primary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(palette.primary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Round icon button used in toolbars over the cube.
struct CircleIconButton: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let label: String
    var isEnabled = true
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(prominent ? Color(hex: 0x0A0A0F) : palette.text)
                .frame(width: 46, height: 46)
                .background {
                    if prominent {
                        Circle().fill(palette.brandGradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().fill(palette.surface.opacity(0.4)))
                    }
                }
                .overlay(Circle().strokeBorder(palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
    }
}

/// Small rounded label, e.g. for moves and tags.
struct Chip: View {
    @Environment(\.palette) private var palette
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.mono(14, .bold))
            .foregroundStyle(highlighted ? Color(hex: 0x0A0A0F) : palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if highlighted {
                    Capsule().fill(palette.brandGradient)
                } else {
                    Capsule().fill(palette.surfaceRaised)
                }
            }
    }
}

/// Section title with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.rounded(12, .heavy))
                .kerning(1.4)
                .foregroundStyle(palette.textDim)
            Spacer()
            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String) {
        self.title = title
        accessory = EmptyView()
    }
}

/// Stat tile: big number with a caption.
struct StatTile: View {
    @Environment(\.palette) private var palette
    let value: String
    let caption: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.primary)
                }
                Text(caption.uppercased())
                    .font(.rounded(10, .heavy))
                    .kerning(0.8)
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(value)
                .font(.mono(20, .bold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The app wordmark: a white "i" and a gradient "RubikCube".
struct Wordmark: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            Text("i").foregroundStyle(palette.text)
            Text("RubikCube").foregroundStyle(palette.textGradient)
        }
        .font(.rounded(size, .heavy))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityLabel(Text("iRubikCube"))
    }
}

extension TimeInterval {
    /// Speedcubing format: `12.34` or `1:02.34`.
    var cubeTime: String {
        let hundredths = Int((self * 100).rounded())
        let minutes = hundredths / 6000
        let seconds = (hundredths / 100) % 60
        let fraction = hundredths % 100
        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
        }
        return String(format: "%d.%02d", seconds, fraction)
    }
}
