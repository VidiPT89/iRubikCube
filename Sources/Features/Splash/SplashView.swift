import CubeCore
import SwiftUI

/// Opening title card: the pieces fly in and click together, the cube spins
/// once and glows, the name appears and the credits fade in. It leaves on
/// its own, or on a tap.
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var scene: CubeScene = {
        let scene = CubeScene(size: 3)
        scene.interaction = .none
        scene.framing = 1.25
        return scene
    }()
    @State private var showCube = false
    @State private var glow = false
    @State private var showWordmark = false
    @State private var showTagline = false
    @State private var showCredit = false
    @State private var showLinks = false
    @State private var finished = false

    private let palette = Palette.dark

    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0F).ignoresSafeArea()
            RadialGradient(colors: [palette.primary.opacity(glow ? 0.45 : 0.12), .clear],
                           center: .init(x: 0.5, y: 0.36), startRadius: 0, endRadius: glow ? 460 : 240)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 1.1), value: glow)

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                CubeView(scene: scene, accessibilityLabel: "iRubikCube")
                    .frame(width: 300, height: 300)
                    .opacity(showCube ? 1 : 0)
                    .scaleEffect(glow ? 1 : 0.94)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: glow)
                    .accessibilityHidden(true)

                Wordmark(size: 46)
                    .shadow(color: palette.primary.opacity(0.55), radius: 22)
                    .scaleEffect(showWordmark ? 1 : 0.7)
                    .opacity(showWordmark ? 1 : 0)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)

                Text(app.t("splash.tagline"))
                    .font(.rounded(15, .medium))
                    .kerning(1.1)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline || reduceMotion ? 0 : 8)
                    .padding(.top, 8)

                Spacer()
                credits.padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .environment(\.palette, palette)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(app.t("a11y.skipSplash"))) { finish() }
        .onAppear(perform: run)
    }

    private var credits: some View {
        VStack(spacing: 14) {
            Text(app.t("about.developedBy"))
                .font(.rounded(15, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(showCredit ? 1 : 0)
                .offset(y: showCredit || reduceMotion ? 0 : 12)

            VStack(spacing: 8) {
                link("ividi.dev", symbol: "globe", url: Links.website, label: app.t("a11y.openWebsite"))
                link("github.com/VidiPT89", symbol: "chevron.left.forwardslash.chevron.right",
                     url: Links.github, label: app.t("a11y.openGitHub"))
            }
            .opacity(showLinks ? 1 : 0)
            .offset(y: showLinks || reduceMotion ? 0 : 12)
        }
    }

    private func link(_ title: String, symbol: String, url: URL, label: String) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(title).font(.rounded(14, .semibold))
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(palette.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }

    // MARK: Choreography

    private func run() {
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.6)) {
                showCube = true
                glow = true
                showWordmark = true
                showTagline = true
                showCredit = true
                showLinks = true
            }
            after(2.6) { finish() }
            return
        }
        scene.yaw = -0.62 - 2.2
        scene.playAssembly(duration: 1.5) {
            app.play(.snap)
            app.feel(.snap)
            scene.resetView()
            scene.celebrate()
            glow = true
        }
        showCube = true
        app.play(.whoosh)
        after(1.55) { withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { showWordmark = true } }
        after(1.85) { withAnimation(.easeOut(duration: 0.5)) { showTagline = true } }
        after(2.2) { withAnimation(.easeOut(duration: 0.5)) { showCredit = true } }
        after(2.45) { withAnimation(.easeOut(duration: 0.5)) { showLinks = true } }
        after(4.3) { finish() }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            work()
        }
    }

    /// Guarded, because the timer and a tap can both arrive.
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
