import CubeCore
import SwiftUI

/// Guided practice: the app sets up the case, the player turns, and every
/// move gets feedback.
struct PracticePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: LessonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Paragraph(title: app.t("practice.goal"), text: app.t("practice.goal.\(model.lesson.rawValue)"), systemImage: "target")
            feedbackBanner
            HStack(spacing: 10) {
                HelpButton(title: app.t("assist.hint"), systemImage: "lightbulb.fill", isEnabled: !model.goalReached) {
                    model.showHint()
                }
                HelpButton(title: app.t("common.undo"), systemImage: "arrow.uturn.backward",
                           isEnabled: model.session.canUndo && !model.goalReached) {
                    model.undoLast()
                }
                HelpButton(title: app.t("practice.newCase"), systemImage: "arrow.clockwise", prominent: model.goalReached) {
                    model.startPractice()
                }
            }
            if let next = model.expected.first, !model.goalReached {
                HStack(spacing: 8) {
                    Text(app.t("practice.suggested")).font(.rounded(13, .semibold)).foregroundStyle(palette.textDim)
                    ForEach(Array(model.expected.prefix(6).enumerated()), id: \.offset) { index, turn in
                        Chip(text: Notation.format(turn), highlighted: index == 0)
                    }
                    if model.expected.count > 6 { Text("…").foregroundStyle(palette.textDim) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(app.t("assist.next") + " " + NotationSpeech.describe(Notation.format(next), model: app)))
            }
            MoveHistoryStrip(turns: model.session.history, size: 3, emptyText: app.t("practice.start"))
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        switch model.feedback {
        case .none:
            EmptyView()
        case .correct:
            banner(app.t("practice.correct"), systemImage: "checkmark.circle.fill", color: palette.success)
        case .wrong(let turn):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(palette.amber)
                Text(app.t("practice.wrong", Notation.format(turn)))
                    .font(.rounded(14, .semibold)).foregroundStyle(palette.text)
                Spacer(minLength: 0)
                Button(app.t("common.undo")) { model.undoLast() }
                    .font(.rounded(14, .bold))
                    .foregroundStyle(palette.primary)
            }
            .padding(12)
            .background(palette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        case .goal:
            banner(app.t("practice.done"), systemImage: "star.fill", color: palette.primary)
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.rounded(14, .bold))
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.4)))
            .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

/// Every notation letter; tap one to see it on the cube.
struct NotationGrid: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: LessonModel

    private let tokens = ["R", "L", "U", "D", "F", "B", "R'", "L'", "U'", "D'", "F'", "B'",
                          "R2", "U2", "M", "E", "S", "x", "y", "z"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(tokens, id: \.self) { token in
                    Button { model.demonstrate(token) } label: {
                        Text(token)
                            .font(.mono(17, .heavy))
                            .foregroundStyle(model.demoToken == token ? Color(hex: 0x0A0A0F) : palette.text)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background {
                                if model.demoToken == token {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.brandGradient)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surfaceRaised)
                                }
                            }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text(NotationSpeech.describe(token, model: app)))
                }
            }
            if let token = model.demoToken {
                Text(NotationSpeech.describe(token, model: app))
                    .font(.rounded(14, .semibold)).foregroundStyle(palette.textDim)
            }
        }
    }
}

/// Five questions: watch the move, pick its name.
struct NotationQuizView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: LessonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let quiz = model.quiz {
                if quiz.isOver {
                    VStack(spacing: 10) {
                        Image(systemName: quiz.score >= 4 ? "star.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(palette.brandGradient)
                        Text(app.t("quiz.score", quiz.score, LessonModel.Quiz.rounds))
                            .font(.rounded(22, .heavy)).foregroundStyle(palette.text)
                        Text(quiz.score >= 4 ? app.t("quiz.passed") : app.t("quiz.tryAgain"))
                            .font(.rounded(15, .medium)).foregroundStyle(palette.textDim)
                            .multilineTextAlignment(.center)
                        PrimaryButton(title: app.t("quiz.again"), systemImage: "arrow.clockwise") { model.startQuiz() }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Text(app.t("quiz.question")).font(.rounded(17, .bold)).foregroundStyle(palette.text)
                        Spacer()
                        Text("\(quiz.round + 1)/\(LessonModel.Quiz.rounds)").font(.mono(14, .bold)).foregroundStyle(palette.primary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(quiz.options, id: \.self) { option in
                            Button { model.answer(option) } label: {
                                Text(option)
                                    .font(.mono(22, .heavy))
                                    .foregroundStyle(palette.text)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(optionColor(option, quiz: quiz), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.stroke))
                            }
                            .buttonStyle(.pressable)
                            .disabled(quiz.picked != nil)
                            .accessibilityLabel(Text(NotationSpeech.describe(option, model: app)))
                        }
                    }
                    SecondaryButton(title: app.t("quiz.replay"), systemImage: "arrow.counterclockwise") { model.replayQuestion() }
                }
            } else {
                Paragraph(title: app.t("lesson.tab.quiz"), text: app.t("quiz.intro"), systemImage: "questionmark.bubble.fill")
                PrimaryButton(title: app.t("quiz.start"), systemImage: "play.fill") { model.startQuiz() }
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.35), value: model.quiz?.round)
    }

    private func optionColor(_ option: String, quiz: LessonModel.Quiz) -> Color {
        guard let picked = quiz.picked else { return palette.surfaceRaised }
        if option == quiz.answer { return palette.success.opacity(0.35) }
        if option == picked { return palette.danger.opacity(0.3) }
        return palette.surfaceRaised
    }
}

/// Sits on the cube while an algorithm is demonstrated: every move as a
/// chip, the current one highlighted and explained, with step controls.
struct AlgorithmPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: LessonModel
    let demo: AlgorithmDemo

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(app.t("algorithm.\(demo.algorithm.id)")).font(.rounded(14, .bold)).foregroundStyle(palette.text)
                Spacer()
                Text("\(demo.index)/\(demo.turns.count)").font(.mono(13, .bold)).foregroundStyle(palette.textDim)
                Button { model.closeDemo() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(palette.textDim)
                }
                .accessibilityLabel(Text(app.t("common.close")))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(demo.tokens.enumerated()), id: \.offset) { index, token in
                            Chip(text: token, highlighted: index == demo.index - 1)
                                .opacity(index < demo.index ? 1 : 0.5)
                                .scaleEffect(index == demo.index - 1 ? 1.12 : 1)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.3), value: demo.index)
                }
                .onChange(of: demo.index) { _, index in
                    withAnimation { proxy.scrollTo(max(0, index - 1), anchor: .center) }
                }
            }
            Text(caption)
                .font(.rounded(13, .semibold))
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .contentTransition(.opacity)
            HStack(spacing: 14) {
                CircleIconButton(systemImage: "backward.end.fill", label: app.t("assist.stepBack"),
                                 isEnabled: demo.index > 0) { model.stepDemo(forward: false) }
                CircleIconButton(systemImage: demo.isFinished ? "arrow.counterclockwise" : (demo.isPlaying ? "pause.fill" : "play.fill"),
                                 label: demo.isFinished ? app.t("lesson.replay") : (demo.isPlaying ? app.t("play.pause") : app.t("assist.play")),
                                 prominent: true) { model.toggleDemo() }
                CircleIconButton(systemImage: "forward.end.fill", label: app.t("assist.stepForward"),
                                 isEnabled: !demo.isFinished) { model.stepDemo(forward: true) }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.primary.opacity(0.35)))
    }

    private var caption: String {
        if demo.isFinished { return app.t("lesson.demoDone") }
        guard let token = demo.currentToken else { return app.t("lesson.demoStart") }
        return "\(token): " + NotationSpeech.describe(token, model: app)
    }
}
