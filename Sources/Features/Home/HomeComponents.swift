import CubeCore
import SwiftUI

/// Big animated card for one of the three modes.
struct ModeCard: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    let systemImage: String
    let index: Int
    let appeared: Bool
    var progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.brandGradient)
                        .shadow(color: palette.primary.opacity(0.45), radius: 12, y: 4)
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0A0A0F))
                        .symbolEffect(.bounce, value: appeared)
                }
                .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.rounded(21, .heavy)).foregroundStyle(palette.text)
                    Text(subtitle).font(.rounded(14, .regular)).foregroundStyle(palette.textDim)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let progress {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.stroke)
                                Capsule().fill(palette.brandGradient)
                                    .frame(width: max(6, geometry.size.width * (appeared ? progress : 0)))
                            }
                        }
                        .frame(height: 5)
                        .padding(.top, 4)
                        .animation(.spring(response: 1).delay(0.4), value: appeared)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.primary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(palette.surface.opacity(palette.isDark ? 0.55 : 0.6)))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(RadialGradient(colors: [palette.primary.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 90))
                            .frame(width: 180, height: 180)
                            .offset(x: 60, y: -70)
                            .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(palette.stroke))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
        .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.08 * Double(index)), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Today's scramble, the same for everyone.
struct DailyCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let index: Int
    let appeared: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(Date.now.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.rounded(10, .heavy)).foregroundStyle(Color(hex: 0x0A0A0F))
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(palette.brandGradient)
                    Text(Date.now.formatted(.dateTime.day()))
                        .font(.rounded(22, .heavy)).foregroundStyle(palette.text)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 52, height: 56)
                .background(palette.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.t("home.daily")).font(.rounded(17, .bold)).foregroundStyle(palette.text)
                    Text(app.progress.dailyTime().map { app.t("home.dailyBest", $0.cubeTime) } ?? app.t("home.dailyNew"))
                        .font(.rounded(13, .regular)).foregroundStyle(palette.textDim)
                }
                Spacer(minLength: 0)
                Image(systemName: app.progress.dailyTime() == nil ? "play.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(palette.primary)
                    .symbolEffect(.pulse, isActive: app.progress.dailyTime() == nil)
            }
            .padding(14)
            .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [palette.primary.opacity(0.6), palette.stroke], startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
        .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.08 * Double(index)), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct ShortcutButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.primary)
                Text(title).font(.rounded(13, .semibold)).foregroundStyle(palette.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.stroke))
        }
        .buttonStyle(.pressable)
    }
}
