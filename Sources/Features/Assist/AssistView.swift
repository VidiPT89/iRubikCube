import CubeCore
import SwiftUI

struct AssistView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: AssistModel
    @State private var showWhereAmI = false
    @State private var showEditor = false
    @State private var showScanner = false
    @State private var showPad = false

    init(app: AppModel, state: CubeState? = nil) {
        _model = State(initialValue: AssistModel(app: app, state: state))
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width > 700
            ZStack {
                Backdrop()
                if wide {
                    HStack(spacing: 20) {
                        cube
                        ScrollView { VStack(spacing: 14) { topBar; helpPanel } .padding(.vertical, 16) }
                            .frame(width: min(430, geometry.size.width * 0.42))
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        topBar.frame(maxWidth: 680)
                        cube
                        helpPanel.frame(maxWidth: 680)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                ConfettiView(trigger: model.confetti).ignoresSafeArea()
            }
        }
        .navigationTitle(app.t("mode.assist"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { model.scramble() } label: { Label(app.t("play.scramble"), systemImage: "shuffle") }
                    Button { showScanner = true } label: { Label(app.t("assist.scan"), systemImage: "camera.viewfinder") }
                    Button { showEditor = true } label: { Label(app.t("assist.manual"), systemImage: "square.grid.3x3.fill") }
                    Button(role: .destructive) { model.reset() } label: { Label(app.t("assist.resetCube"), systemImage: "arrow.counterclockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel(Text(app.t("assist.cubeMenu")))
            }
        }
        .sheet(isPresented: $showWhereAmI) {
            WhereAmISheet(stage: model.stage).themed().environment(app).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showEditor) {
            NavigationStack {
                CubeEditorView(start: model.session.state) { state in
                    model.load(state)
                    showEditor = false
                }
            }
            .themed()
            .environment(app)
        }
        .fullScreenCover(isPresented: $showScanner) {
            NavigationStack {
                ScannerView { state in
                    model.load(state)
                    showScanner = false
                }
            }
            .themed()
            .environment(app)
        }
        .alert(app.t("assist.invalidTitle"), isPresented: Binding(get: { model.error != nil }, set: { _ in })) {
            Button(app.t("common.ok")) { model.reset() }
        } message: {
            Text(app.t(model.error?.messageKey ?? "validation.invalidCorner"))
        }
        .onAppear { model.session.applySettings() }
    }

    // MARK: Pieces

    private var topBar: some View {
        VStack(spacing: 10) {
            MethodPicker(method: $model.method)
            Button { showWhereAmI = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isSolved ? "checkmark.seal.fill" : "location.fill")
                        .foregroundStyle(palette.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.t("assist.whereAmI").uppercased())
                            .font(.rounded(10, .heavy)).kerning(1).foregroundStyle(palette.textDim)
                        Text(app.t("stage.\(model.stage.rawValue).title"))
                            .font(.rounded(15, .bold)).foregroundStyle(palette.text)
                    }
                    Spacer()
                    StageDots(stage: model.stage)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textFaint)
                }
                .padding(12)
                .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.stroke))
            }
            .buttonStyle(.pressable)
        }
    }

    private var cube: some View {
        ZStack(alignment: .top) {
            CubeView(scene: model.session.scene,
                     accessibilityLabel: app.t("a11y.cube"),
                     accessibilityValue: CubeDescriber.describe(model.session.state, app: app))
            if let hint = model.hintTurn {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(palette.amber)
                    Text(app.t("assist.next")).font(.rounded(13, .semibold)).foregroundStyle(palette.textDim)
                    Chip(text: Notation.format(hint), highlighted: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(app.t("assist.next") + " " + NotationSpeech.describe(Notation.format(hint), model: app)))
            }
            if model.isComputing {
                ProgressView().tint(palette.primary).padding(.top, 50)
            }
        }
        .animation(.spring(response: 0.4), value: model.hintTurn)
    }

    private var helpPanel: some View {
        VStack(spacing: 12) {
            if let step = model.currentStep {
                StepExplanation(step: step)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let playback = model.playback {
                PlaybackBar(model: model, playback: playback)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                MoveHistoryStrip(turns: model.session.history, size: 3, emptyText: app.t("assist.historyEmpty"))
                if showPad {
                    NotationPad(size: 3) { turn in model.session.perform(turn) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            HStack(spacing: 10) {
                HelpButton(title: app.t("assist.hint"), systemImage: "lightbulb.fill", isEnabled: !model.isSolved) {
                    model.showHint()
                }
                HelpButton(title: app.t("assist.doIt"), systemImage: "hand.tap.fill", isEnabled: !model.isSolved) {
                    model.doNextMove()
                }
                HelpButton(title: app.t("assist.solveAll"), systemImage: "play.circle.fill",
                           isEnabled: !model.isSolved, prominent: true) {
                    model.solveAll()
                }
            }
            HStack(spacing: 10) {
                CircleIconButton(systemImage: "arrow.uturn.backward", label: app.t("common.undo"),
                                 isEnabled: model.session.canUndo && model.playback == nil) { model.session.undo() }
                CircleIconButton(systemImage: "arrow.uturn.forward", label: app.t("common.redo"),
                                 isEnabled: model.session.canRedo && model.playback == nil) { model.session.redo() }
                Spacer()
                SecondaryButton(title: app.t("play.scramble"), systemImage: "shuffle") { model.scramble() }
                CircleIconButton(systemImage: showPad ? "keyboard.chevron.compact.down" : "keyboard",
                                 label: app.t("play.togglePad"), prominent: showPad) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showPad.toggle() }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.playback != nil)
    }
}

/// Optimal / Beginner.
struct MethodPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Binding var method: AssistModel.Method

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AssistModel.Method.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { method = option }
                } label: {
                    Label(app.t("assist.method.\(option.rawValue)"),
                          systemImage: option == .optimal ? "bolt.fill" : "graduationcap.fill")
                        .font(.rounded(14, .bold))
                        .foregroundStyle(method == option ? Color(hex: 0x0A0A0F) : palette.textDim)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if method == option { Capsule().fill(palette.brandGradient) }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(method == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surface.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(palette.stroke))
    }
}

/// Tall help button with an icon above its title.
struct HelpButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    var isEnabled = true
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 20, weight: .bold))
                Text(title).font(.rounded(13, .bold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(prominent ? Color(hex: 0x0A0A0F) : palette.text)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.brandGradient)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.surface.opacity(0.8))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.stroke))
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
