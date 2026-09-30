import CubeCore
import SwiftUI

struct LessonView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: LessonModel

    init(lesson: LessonID, app: AppModel) {
        _model = State(initialValue: LessonModel(lesson: lesson, app: app))
    }

    private var tabs: [LessonModel.Tab] {
        model.lesson == .anatomy ? [.why, .how] : LessonModel.Tab.allCases
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 700
            ZStack {
                Backdrop()
                if wide {
                    HStack(spacing: 20) {
                        cube
                        VStack(spacing: 12) { tabPicker; content }
                            .frame(width: min(440, geometry.size.width * 0.44))
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        cube.frame(height: geometry.size.height * 0.42)
                        tabPicker
                        content
                    }
                    .padding(.horizontal, 16)
                }
                ConfettiView(trigger: model.confetti).ignoresSafeArea()
            }
        }
        .navigationTitle(app.t("lesson.\(model.lesson.rawValue).title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isCompleted {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(palette.primary)
                        .accessibilityLabel(Text(app.t("learn.completed")))
                }
            }
        }
        .onAppear { model.session.applySettings() }
    }

    private var cube: some View {
        ZStack(alignment: .bottom) {
            CubeView(scene: model.session.scene,
                     accessibilityLabel: app.t("a11y.cube"),
                     accessibilityValue: CubeDescriber.describe(model.session.state, app: app))
            if let token = model.demoToken, model.tab == .how, model.lesson == .notation, model.quiz == nil {
                Text(token).font(.mono(28, .heavy)).foregroundStyle(palette.textGradient)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .id(token)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: model.demoToken)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.tab = tab }
                } label: {
                    Text(tabTitle(tab))
                        .font(.rounded(14, .bold))
                        .foregroundStyle(model.tab == tab ? Color(hex: 0x0A0A0F) : palette.textDim)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if model.tab == tab { Capsule().fill(palette.brandGradient) } }
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surface.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(palette.stroke))
    }

    private func tabTitle(_ tab: LessonModel.Tab) -> String {
        if tab == .practice && model.lesson == .notation { return app.t("lesson.tab.quiz") }
        return app.t("lesson.tab.\(tab.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.tab {
                case .why: whyContent
                case .how: howContent
                case .practice:
                    if model.lesson == .notation {
                        NotationQuizView(model: model)
                    } else {
                        PracticePanel(model: model)
                    }
                }
                if !model.isCompleted && model.tab != .practice {
                    SecondaryButton(title: app.t("lesson.markDone"), systemImage: "checkmark.circle") { model.complete() }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .id(model.tab)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var whyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Paragraph(title: app.t("lesson.why"), text: app.t("lesson.\(model.lesson.rawValue).why"), systemImage: "questionmark.circle.fill")
            if model.lesson == .anatomy {
                HStack(spacing: 8) {
                    ForEach(LessonModel.Anatomy.allCases) { part in
                        SecondaryButton(title: app.t("anatomy.\(part.rawValue)")) { model.selectAnatomy(part) }
                    }
                }
                Text(app.t("anatomy.\(model.anatomy.rawValue).detail"))
                    .font(.rounded(15, .regular)).foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.anatomy)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.anatomy)
    }

    private var howContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Paragraph(title: app.t("lesson.how"), text: app.t("lesson.\(model.lesson.rawValue).how"), systemImage: "hand.point.up.left.fill")
            if model.lesson == .notation {
                NotationGrid(model: model)
            }
            ForEach(model.lesson.algorithms) { algorithm in
                AlgorithmCard(algorithm: algorithm, isPlaying: model.playingAlgorithm == algorithm.id) {
                    model.watch(algorithm)
                }
            }
            if let tip = tipText {
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.rounded(14, .medium)).foregroundStyle(palette.textDim)
                    .padding(12)
                    .background(palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var tipText: String? {
        let key = "lesson.\(model.lesson.rawValue).tip"
        let text = app.t(key)
        return text == key ? nil : text
    }
}

struct Paragraph: View {
    @Environment(\.palette) private var palette
    let title: String
    let text: String
    let systemImage: String

    var body: some View {
        GlassCard(padding: 14, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.rounded(13, .heavy)).foregroundStyle(palette.primary)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// An algorithm with its name, notation and a slow-motion demo button.
struct AlgorithmCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let algorithm: Algorithm
    let isPlaying: Bool
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.t("algorithm.\(algorithm.id)")).font(.rounded(14, .bold)).foregroundStyle(palette.text)
                Text(algorithm.notation)
                    .font(.mono(15, .bold))
                    .foregroundStyle(palette.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onWatch) {
                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0A0A0F))
                    .frame(width: 42, height: 42)
                    .background(palette.brandGradient, in: Circle())
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(app.t("lesson.watchSlowly")))
        }
        .padding(14)
        .background(palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isPlaying ? palette.primary : palette.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(app.t("lesson.watchSlowly")), onWatch)
    }
}
