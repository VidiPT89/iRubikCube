import CubeCore
import SwiftUI

extension CubeValidationError {
    /// Localisation key of the message shown to the player.
    var messageKey: String {
        switch self {
        case .wrongColorCount: "validation.colorCount"
        case .duplicateCenters: "validation.centers"
        case .invalidCorner, .duplicateCorner: "validation.corner"
        case .invalidEdge, .duplicateEdge: "validation.edge"
        case .twistedCorner: "validation.twist"
        case .flippedEdge: "validation.flip"
        case .parity: "validation.parity"
        }
    }
}

/// Seven dots, one per beginner stage, filled up to the current one.
struct StageDots: View {
    @Environment(\.palette) private var palette
    let stage: BeginnerStage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BeginnerStage.teaching, id: \.self) { item in
                Circle()
                    .fill(item < stage ? AnyShapeStyle(palette.brandGradient)
                          : item == stage ? AnyShapeStyle(palette.primary.opacity(0.45)) : AnyShapeStyle(palette.stroke))
                    .frame(width: 7, height: 7)
                    .scaleEffect(item == stage ? 1.35 : 1)
            }
        }
        .animation(.spring(response: 0.4), value: stage)
        .accessibilityHidden(true)
    }
}

/// "Where am I": every beginner stage, done, current or still to do.
struct WhereAmISheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let stage: BeginnerStage

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(app.t("assist.whereAmI")).font(.rounded(26, .heavy)).foregroundStyle(palette.text)
                    Text(stage == .solved ? app.t("assist.whereSolved")
                         : app.t("assist.whereSummary", BeginnerStage.teaching.filter { $0 >= stage }.count))
                        .font(.rounded(15, .medium)).foregroundStyle(palette.textDim)
                    ForEach(Array(BeginnerStage.teaching.enumerated()), id: \.element) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(item < stage ? AnyShapeStyle(palette.brandGradient) : AnyShapeStyle(palette.surfaceRaised))
                                if item < stage {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(hex: 0x0A0A0F))
                                } else {
                                    Text("\(index + 1)").font(.rounded(13, .heavy))
                                        .foregroundStyle(item == stage ? palette.primary : palette.textDim)
                                }
                            }
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(item == stage ? palette.primary : .clear, lineWidth: 2))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.t("stage.\(item.rawValue).title"))
                                    .font(.rounded(16, .bold))
                                    .foregroundStyle(item > stage ? palette.textDim : palette.text)
                                if item == stage {
                                    Text(app.t("stage.\(item.rawValue).goal"))
                                        .font(.rounded(14, .regular)).foregroundStyle(palette.textDim)
                                }
                            }
                            Spacer()
                            if item == stage {
                                Text(app.t("assist.now")).font(.rounded(11, .heavy)).foregroundStyle(Color(hex: 0x0A0A0F))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(palette.brandGradient, in: Capsule())
                            }
                        }
                        .padding(12)
                        .background(item == stage ? palette.primary.opacity(0.1) : palette.surface.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
            }
        }
    }
}

/// Explains the beginner step the next move belongs to.
struct StepExplanation: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let step: SolveStep

    var body: some View {
        GlassCard(padding: 12, cornerRadius: 16) {
            HStack(spacing: 12) {
                if !step.piece.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(step.piece.enumerated()), id: \.offset) { _, color in
                            StickerSwatch(color: color, scheme: app.settings.cubeScheme, size: 18)
                        }
                    }
                } else {
                    Image(systemName: "sparkles").foregroundStyle(palette.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.t("stage.\(step.stage.rawValue).title"))
                        .font(.rounded(14, .bold)).foregroundStyle(palette.text)
                    Text(detail).font(.rounded(12, .medium)).foregroundStyle(palette.textDim).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let algorithm = step.algorithm {
            return app.t("assist.usingAlgorithm", app.t("algorithm.\(algorithm)"))
        }
        if step.piece.count >= 2 {
            let names = step.piece.map { app.t("color.\($0)") }.joined(separator: "–")
            return app.t("assist.placePiece", names)
        }
        return app.t("stage.\(step.stage.rawValue).goal")
    }
}

/// Step-by-step playback of the full solution.
struct PlaybackBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: AssistModel
    let playback: AssistModel.Playback

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(playback.turns.enumerated()), id: \.offset) { index, turn in
                            Chip(text: Notation.format(turn), highlighted: index == playback.index - 1)
                                .opacity(index < playback.index ? 0.55 : 1)
                                .id(index)
                        }
                    }
                }
                .onChange(of: playback.index) { _, index in
                    withAnimation { proxy.scrollTo(max(0, index - 1), anchor: .center) }
                }
            }
            .frame(height: 32)
            HStack(spacing: 12) {
                Text("\(playback.index)/\(playback.turns.count)")
                    .font(.mono(14, .bold)).foregroundStyle(palette.textDim)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                CircleIconButton(systemImage: "backward.end.fill", label: app.t("assist.stepBack"),
                                 isEnabled: playback.index > 0) { model.stepBackward() }
                CircleIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                                 label: playback.isPlaying ? app.t("play.pause") : app.t("assist.play"),
                                 isEnabled: !playback.isFinished, prominent: true) { model.togglePlay() }
                CircleIconButton(systemImage: "forward.end.fill", label: app.t("assist.stepForward"),
                                 isEnabled: !playback.isFinished) { model.stepForward() }
                Spacer()
                Menu {
                    ForEach(AssistModel.Speed.allCases) { speed in
                        Button {
                            model.speed = speed
                        } label: {
                            if model.speed == speed {
                                Label(app.t("assist.speed.\(speed)"), systemImage: "checkmark")
                            } else {
                                Text(app.t("assist.speed.\(speed)"))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.1f×", model.speed.rawValue))
                        .font(.mono(14, .bold)).foregroundStyle(palette.primary)
                        .frame(width: 60, height: 34)
                        .background(palette.primary.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel(Text(app.t("assist.speed")))
            }
            Button { model.stopPlayback() } label: {
                Text(app.t("assist.stopPlayback")).font(.rounded(13, .semibold)).foregroundStyle(palette.textDim)
            }
        }
        .padding(12)
        .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.stroke))
    }
}
