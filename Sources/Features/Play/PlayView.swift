import CubeCore
import SwiftData
import SwiftUI

struct PlayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @State private var model: PlayModel
    @State private var showPad = false

    init(app: AppModel, isDaily: Bool = false) {
        _model = State(initialValue: PlayModel(model: app, isDaily: isDaily))
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 700
            ZStack {
                Backdrop(glow: model.phase == .solved ? 1.6 : 1)
                    .animation(.easeInOut(duration: 0.8), value: model.phase)
                if wide {
                    HStack(spacing: 20) {
                        cubeArea
                        ScrollView { panel.padding(.vertical, 16) }
                            .frame(width: min(420, geometry.size.width * 0.4))
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        header.frame(maxWidth: 680)
                        cubeArea
                        bottomPanel.frame(maxWidth: 680)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                ConfettiView(trigger: model.confetti).ignoresSafeArea()
            }
        }
        .navigationTitle(model.isDaily ? app.t("home.daily") : app.t("mode.play"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.result) { result in
            ResultSheet(result: result) {
                model.result = nil
                model.newScramble()
            }
            .themed()
            .environment(app)
            .presentationDetents([.medium])
        }
        .onAppear {
            model.session.applySettings()
            showPad = app.settings.showNotationPanel
            model.bestTime = { size in bestTime(for: size) }
            model.onSolved = { result, scramble, solution in save(result, scramble: scramble, solution: solution) }
        }
    }

    // MARK: Layout pieces

    private var header: some View {
        VStack(spacing: 10) {
            if !model.isDaily {
                SizePicker(size: Binding(get: { model.size }, set: { model.changeSize($0) }))
                    .disabled(model.phase == .solving || model.phase == .scrambling)
            }
            HStack(spacing: 12) {
                CircleIconButton(systemImage: "arrow.counterclockwise", label: app.t("play.restart"),
                                 isEnabled: !model.scramble.isEmpty && model.phase != .scrambling) {
                    model.restart()
                }
                TimerDisplay(model: model).frame(maxWidth: .infinity)
                CircleIconButton(systemImage: model.phase == .paused ? "play.fill" : "pause.fill",
                                 label: model.phase == .paused ? app.t("play.resume") : app.t("play.pause"),
                                 isEnabled: model.phase == .solving || model.phase == .paused) {
                    model.togglePause()
                }
            }
            ScrambleCard(scramble: model.scramble, size: model.size, placeholder: app.t("play.noScramble"))
        }
    }

    private var cubeArea: some View {
        ZStack {
            CubeView(scene: model.session.scene,
                     accessibilityLabel: app.t("a11y.cube"),
                     accessibilityValue: CubeDescriber.describe(model.session.state, app: app))
                .blur(radius: model.phase == .paused ? 18 : 0)
            if model.phase == .paused {
                VStack(spacing: 12) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 54)).foregroundStyle(palette.primary)
                    Text(app.t("play.paused")).font(.rounded(22, .bold)).foregroundStyle(palette.text)
                    PrimaryButton(title: app.t("play.resume"), systemImage: "play.fill") { model.togglePause() }
                }
                .transition(.scale.combined(with: .opacity))
            }
            if let end = model.inspectionEnd, model.phase == .waiting {
                InspectionBadge(end: end).frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.4), value: model.phase)
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            MoveHistoryStrip(turns: model.session.history, size: model.size, emptyText: app.t("play.historyEmpty"))
            if showPad {
                NotationPad(size: model.size, isEnabled: model.phase != .paused && model.phase != .scrambling) { turn in
                    model.session.perform(turn)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controlBar
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            MoveHistoryStrip(turns: model.session.history, size: model.size, emptyText: app.t("play.historyEmpty"))
            NotationPad(size: model.size, isEnabled: model.phase != .paused && model.phase != .scrambling) { turn in
                model.session.perform(turn)
            }
            controlBar
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            CircleIconButton(systemImage: "arrow.uturn.backward", label: app.t("common.undo"),
                             isEnabled: model.session.canUndo && (model.phase == .solving || model.phase == .waiting)) {
                model.undo()
            }
            CircleIconButton(systemImage: "arrow.uturn.forward", label: app.t("common.redo"),
                             isEnabled: model.session.canRedo && (model.phase == .solving || model.phase == .waiting)) {
                model.redo()
            }
            Spacer(minLength: 0)
            PrimaryButton(title: app.t("play.scramble"), systemImage: "shuffle") {
                model.newScramble()
            }
            .disabled(model.phase == .scrambling)
            Spacer(minLength: 0)
            Color.clear.frame(width: 46, height: 1)
            CircleIconButton(systemImage: showPad ? "keyboard.chevron.compact.down" : "keyboard",
                             label: app.t("play.togglePad"), prominent: showPad) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPad.toggle() }
            }
        }
    }

    // MARK: Records

    private func bestTime(for size: Int) -> TimeInterval? {
        let descriptor = FetchDescriptor<SolveRecord>(predicate: #Predicate { $0.size == size },
                                                      sortBy: [SortDescriptor(\.duration)])
        return (try? context.fetch(descriptor))?.first?.duration
    }

    private func save(_ result: PlayModel.Result, scramble: [Turn], solution: [Turn]) {
        let record = SolveRecord(duration: result.time, moveCount: result.moves, size: result.size,
                                 scramble: Notation.format(scramble, size: result.size),
                                 solution: Notation.format(solution, size: result.size),
                                 isDaily: result.isDaily)
        context.insert(record)
        try? context.save()
        let unlocked = app.progress.recordSolve(time: result.time, size: result.size, isDaily: result.isDaily)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            app.announce(unlocked)
        }
    }
}

/// 2×2 / 3×3 / 4×4 selector.
struct SizePicker: View {
    @Environment(\.palette) private var palette
    @Binding var size: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach([2, 3, 4], id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { size = option }
                } label: {
                    Text("\(option)×\(option)")
                        .font(.rounded(14, .bold))
                        .foregroundStyle(size == option ? Color(hex: 0x0A0A0F) : palette.textDim)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if size == option {
                                Capsule().fill(palette.brandGradient)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(size == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surface.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(palette.stroke))
        .frame(maxWidth: 300)
    }
}
