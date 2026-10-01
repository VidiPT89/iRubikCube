import CubeCore
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Binding var path: [Route]
    @Query(sort: \SolveRecord.date, order: .reverse) private var records: [SolveRecord]
    @State private var hero = HeroCube()
    @State private var showSettings = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 700
            ZStack {
                Backdrop(glow: 1.2)
                if wide {
                    HStack(spacing: 24) {
                        VStack(spacing: 8) {
                            title
                            heroCube
                            statsStrip
                        }
                        .frame(maxWidth: .infinity)
                        ScrollView { cards.padding(.vertical, 20) }
                            .frame(width: min(460, geometry.size.width * 0.45))
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            title
                            heroCube.frame(height: min(320, geometry.size.height * 0.38))
                            statsStrip
                            cards
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(Text(app.t("settings.title")))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) {
            SettingsView().themed().environment(app)
        }
        .onAppear {
            hero.start(app: app)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
        .onDisappear { hero.stop() }
        .onChange(of: app.settings.highContrast) { _, _ in hero.session?.scene.scheme = app.settings.cubeScheme }
    }

    // MARK: Pieces

    private var title: some View {
        VStack(spacing: 4) {
            Wordmark(size: 34)
            Text(app.t("splash.tagline"))
                .font(.rounded(14, .medium))
                .foregroundStyle(palette.textDim)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.9)
    }

    private var heroCube: some View {
        ZStack {
            RadialGradient(colors: [palette.primary.opacity(0.3), palette.primary.opacity(0.08), .clear],
                           center: .center, startRadius: 0, endRadius: 200)
                .scaleEffect(appeared ? 1 : 0.6)
                .allowsHitTesting(false)
            // Only one RealityView renders at a time, so the hero steps aside
            // while another screen with a cube is on top.
            if let session = hero.session, path.isEmpty {
                CubeView(scene: session.scene, accessibilityLabel: app.t("a11y.heroCube"))
            }
        }
    }

    private var statsStrip: some View {
        let threes = records.filter { $0.size == 3 }
        return HStack(spacing: 12) {
            StatTile(value: records.first?.duration.cubeTime ?? app.t("common.none"),
                     caption: app.t("home.lastTime"), systemImage: "clock.fill")
            StatTile(value: threes.map(\.duration).min()?.cubeTime ?? app.t("common.none"),
                     caption: app.t("home.bestTime"), systemImage: "trophy.fill")
            StatTile(value: "\(Int((app.progress.lessonProgress * 100).rounded()))%",
                     caption: app.t("home.lessons"), systemImage: "graduationcap.fill")
        }
        .padding(14)
        .background(palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.stroke))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private var cards: some View {
        VStack(spacing: 14) {
            ModeCard(title: app.t("mode.play"), subtitle: app.t("mode.play.subtitle"), systemImage: "timer",
                     index: 0, appeared: appeared) { path.append(.play) }
            ModeCard(title: app.t("mode.assist"), subtitle: app.t("mode.assist.subtitle"), systemImage: "lightbulb.fill",
                     index: 1, appeared: appeared) { path.append(.assist(nil)) }
            ModeCard(title: app.t("mode.learn"), subtitle: app.t("mode.learn.subtitle"), systemImage: "graduationcap.fill",
                     index: 2, appeared: appeared, progress: app.progress.lessonProgress) { path.append(.learn) }
            DailyCard(index: 3, appeared: appeared) { path.append(.daily) }
            HStack(spacing: 12) {
                ShortcutButton(title: app.t("home.scanner"), systemImage: "camera.viewfinder") { path.append(.scanner) }
                ShortcutButton(title: app.t("home.stats"), systemImage: "chart.xyaxis.line") { path.append(.stats) }
                ShortcutButton(title: app.t("settings.title"), systemImage: "gearshape.fill") { showSettings = true }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.35), value: appeared)
        }
    }
}

/// The slowly spinning cube on the home screen, which now and then turns a
/// layer on its own and turns it back.
@Observable
@MainActor
final class HeroCube {
    private(set) var session: CubeSession?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(app: AppModel) {
        if session == nil {
            let session = CubeSession(size: 3, model: nil)
            session.scene.interaction = .orbitOnly
            session.scene.autoRotate = !UIAccessibility.isReduceMotionEnabled
            session.scene.turnDuration = 0.45
            self.session = session
        }
        session?.scene.scheme = app.settings.cubeScheme
        task?.cancel()
        task = Task { @MainActor [weak self] in
            var pending: [Turn] = []
            while !Task.isCancelled, !UIAccessibility.isReduceMotionEnabled {
                try? await Task.sleep(for: .seconds(2.4))
                guard let session = self?.session, !Task.isCancelled else { return }
                if pending.count >= 3 || (!pending.isEmpty && Bool.random()) {
                    session.perform(pending.removeLast().inverse, source: .program)
                } else {
                    let turn = Turn.face(Face.allCases.randomElement() ?? .R, Bool.random() ? 1 : -1)
                    pending.append(turn)
                    session.perform(turn, source: .program)
                }
            }
        }
    }

    func stop() { task?.cancel() }
}
