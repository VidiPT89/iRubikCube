import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            ZStack {
                Backdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        group(app.t("settings.language"), systemImage: "globe") {
                            ChoiceRow(options: AppLanguage.allCases, selection: $settings.language) { language in
                                Text(language.nativeName)
                            }
                        }
                        group(app.t("settings.appearance"), systemImage: "circle.lefthalf.filled") {
                            ChoiceRow(options: Appearance.allCases, selection: $settings.appearance) { appearance in
                                Label(app.t("settings.appearance.\(appearance.rawValue)"), systemImage: appearance.systemImage)
                            }
                        }
                        group(app.t("settings.cube"), systemImage: "cube.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(app.t("settings.animationSpeed")).font(.rounded(14, .semibold)).foregroundStyle(palette.textDim)
                                ChoiceRow(options: AnimationSpeed.allCases, selection: $settings.animationSpeed) { speed in
                                    Text(app.t("settings.speed.\(speed.rawValue)"))
                                }
                            }
                            ToggleRow(title: app.t("settings.highContrast"), detail: app.t("settings.highContrast.detail"),
                                      systemImage: "eye.fill", isOn: $settings.highContrast)
                            ToggleRow(title: app.t("settings.notationPanel"), detail: app.t("settings.notationPanel.detail"),
                                      systemImage: "keyboard", isOn: $settings.showNotationPanel)
                        }
                        group(app.t("settings.play"), systemImage: "timer") {
                            ToggleRow(title: app.t("settings.inspection"), detail: app.t("settings.inspection.detail"),
                                      systemImage: "eye.circle.fill", isOn: $settings.inspection)
                        }
                        group(app.t("settings.feedback"), systemImage: "waveform") {
                            ToggleRow(title: app.t("settings.sound"), detail: nil, systemImage: "speaker.wave.2.fill", isOn: $settings.sound)
                            ToggleRow(title: app.t("settings.haptics"), detail: nil, systemImage: "iphone.radiowaves.left.and.right",
                                      isOn: $settings.haptics)
                        }
                        group(app.t("settings.data"), systemImage: "externaldrive.fill") {
                            Button(role: .destructive) { confirmReset = true } label: {
                                Label(app.t("settings.resetStats"), systemImage: "trash")
                                    .font(.rounded(15, .semibold))
                                    .foregroundStyle(palette.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(app.t("settings.sync")).font(.rounded(12, .regular)).foregroundStyle(palette.textDim)
                        }
                        about
                    }
                    .padding(20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(app.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.t("common.done")) { dismiss() }.fontWeight(.bold)
                }
            }
            .confirmationDialog(app.t("settings.resetStats.confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(app.t("settings.resetStats"), role: .destructive) { resetStatistics() }
                Button(app.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(app.t("settings.resetStats.message"))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.settings.appearance)
    }

    private var about: some View {
        group(app.t("settings.about"), systemImage: "info.circle.fill") {
            HStack(spacing: 14) {
                AppIconBadge(size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Wordmark(size: 24)
                    Text(app.t("about.version", AppInfo.version)).font(.rounded(13, .medium)).foregroundStyle(palette.textDim)
                }
            }
            Text(app.t("about.body")).font(.system(size: 14)).foregroundStyle(palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Text(app.t("about.developedBy")).font(.rounded(15, .bold)).foregroundStyle(palette.text)
            HStack(spacing: 10) {
                LinkPill(title: "ividi.dev", systemImage: "globe") { openURL(Links.website) }
                LinkPill(title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right") { openURL(Links.github) }
            }
        }
    }

    private func group<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.rounded(12, .heavy)).kerning(1.2).foregroundStyle(palette.textDim)
            GlassCard(padding: 14, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resetStatistics() {
        try? context.delete(model: SolveRecord.self)
        try? context.save()
        app.progress.resetStatistics()
        app.show(Toast(title: app.t("settings.title"), message: app.t("settings.resetStats.done"), systemImage: "trash.fill"))
    }
}

/// Segmented choice with the brand highlight.
struct ChoiceRow<Option: Hashable & Identifiable, Label: View>: View {
    @Environment(\.palette) private var palette
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option }
                } label: {
                    label(option)
                        .font(.rounded(14, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selection == option ? Color(hex: 0x0A0A0F) : palette.textDim)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background { if selection == option { Capsule().fill(palette.brandGradient) } }
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surfaceRaised.opacity(0.8), in: Capsule())
    }
}

struct ToggleRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let detail: String?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 30, height: 30)
                    .background(palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rounded(15, .semibold)).foregroundStyle(palette.text)
                    if let detail {
                        Text(detail).font(.rounded(12, .regular)).foregroundStyle(palette.textDim)
                    }
                }
            }
        }
        .tint(palette.primary)
    }
}

struct LinkPill: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
                Text(title).font(.rounded(14, .semibold))
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// The app icon drawn in SwiftUI (an isometric cube in brand colours).
struct AppIconBadge: View {
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1D1D25), Color(hex: 0x0A0A0F)], startPoint: .top, endPoint: .bottom))
            IsoCube(colors: [Color(hex: 0xFCBB00), Color(hex: 0xF99C00), Color(hex: 0xDD7400)])
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0xF99C00).opacity(0.3), radius: size * 0.15)
        .accessibilityHidden(true)
    }
}

/// A flat isometric 3×3 cube: top, left and right faces.
struct IsoCube: View {
    let colors: [Color]

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let r = min(w, h) / 2
            let top = CGPoint(x: center.x, y: center.y - r)
            let right = CGPoint(x: center.x + r * 0.866, y: center.y - r / 2)
            let left = CGPoint(x: center.x - r * 0.866, y: center.y - r / 2)
            let bottom = CGPoint(x: center.x, y: center.y + r)
            let rightLow = CGPoint(x: right.x, y: center.y + r / 2)
            let leftLow = CGPoint(x: left.x, y: center.y + r / 2)
            let faces: [([CGPoint], Color)] = [
                ([top, right, center, left], colors[0]),
                ([left, center, bottom, leftLow], colors[1]),
                ([center, right, rightLow, bottom], colors[2]),
            ]
            for (corners, color) in faces {
                let (a, b, _, d) = (corners[0], corners[1], corners[2], corners[3])
                let u = CGPoint(x: (b.x - a.x) / 3, y: (b.y - a.y) / 3)
                let v = CGPoint(x: (d.x - a.x) / 3, y: (d.y - a.y) / 3)
                for i in 0..<3 {
                    for j in 0..<3 {
                        let origin = CGPoint(x: a.x + u.x * CGFloat(i) + v.x * CGFloat(j), y: a.y + u.y * CGFloat(i) + v.y * CGFloat(j))
                        let inset: CGFloat = 0.1
                        func p(_ s: CGFloat, _ t: CGFloat) -> CGPoint {
                            CGPoint(x: origin.x + u.x * s + v.x * t, y: origin.y + u.y * s + v.y * t)
                        }
                        var path = Path()
                        path.move(to: p(inset, inset))
                        path.addLine(to: p(1 - inset, inset))
                        path.addLine(to: p(1 - inset, 1 - inset))
                        path.addLine(to: p(inset, 1 - inset))
                        path.closeSubpath()
                        context.fill(path, with: .color(color))
                    }
                }
            }
        }
    }
}
