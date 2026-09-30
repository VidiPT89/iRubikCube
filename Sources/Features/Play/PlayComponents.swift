import CubeCore
import SwiftUI

/// Big speedcubing clock with hundredths, plus the move counter.
struct TimerDisplay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let model: PlayModel

    var body: some View {
        VStack(spacing: 2) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.phase != .solving)) { timeline in
                let time = model.elapsed(at: timeline.date)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(time.cubeTime)
                        .font(.mono(44, .bold))
                        .monospacedDigit()
                        .foregroundStyle(model.phase == .solved ? AnyShapeStyle(palette.textGradient) : AnyShapeStyle(palette.text))
                        .contentTransition(.numericText())
                        .accessibilityLabel(Text(app.t("common.time")))
                        .accessibilityValue(Text(time.cubeTime))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(model.moves)")
                            .font(.mono(20, .bold))
                            .foregroundStyle(palette.primary)
                            .contentTransition(.numericText())
                        Text(app.t("common.moves").uppercased())
                            .font(.rounded(9, .heavy))
                            .kerning(1)
                            .foregroundStyle(palette.textDim)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(caption)
                .font(.rounded(12, .semibold))
                .foregroundStyle(palette.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .animation(.easeInOut, value: model.phase)
        }
    }

    private var caption: String {
        switch model.phase {
        case .idle: app.t("play.caption.idle")
        case .scrambling: app.t("play.caption.scrambling")
        case .waiting: app.t("play.caption.waiting")
        case .solving: app.t("play.caption.solving")
        case .paused: app.t("play.paused")
        case .solved: app.t("play.caption.solved")
        }
    }
}

/// The scramble in notation, in a frosted card.
struct ScrambleCard: View {
    @Environment(\.palette) private var palette
    let scramble: [Turn]
    let size: Int
    let placeholder: String

    var body: some View {
        GlassCard(padding: 12, cornerRadius: 16) {
            HStack(spacing: 10) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.primary)
                Text(scramble.isEmpty ? placeholder : Notation.format(scramble, size: size))
                    .font(scramble.isEmpty ? .rounded(13, .medium) : .mono(13, .semibold))
                    .foregroundStyle(scramble.isEmpty ? palette.textDim : palette.text)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .animation(.easeInOut, value: scramble)
    }
}

/// 15-second inspection countdown.
struct InspectionBadge: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let remaining = max(0, Int(ceil(end.timeIntervalSince(timeline.date))))
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                Text(app.t("play.inspection"))
                Text("\(remaining)").font(.mono(18, .heavy)).contentTransition(.numericText(countsDown: true))
            }
            .font(.rounded(14, .bold))
            .foregroundStyle(remaining <= 3 ? palette.danger : palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.primary.opacity(0.4)))
            .animation(.spring, value: remaining)
        }
    }
}

/// Shown when the cube is solved: time, moves and comparison with the record.
struct ResultSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let result: PlayModel.Result
    let onAgain: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Backdrop(glow: 1.4)
            VStack(spacing: 18) {
                Image(systemName: result.isNewBest ? "trophy.fill" : "checkmark.seal.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(palette.brandGradient)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -30))
                Text(result.isNewBest ? app.t("result.newBest") : app.t("result.solved"))
                    .font(.rounded(24, .heavy))
                    .foregroundStyle(palette.text)
                Text(result.time.cubeTime)
                    .font(.mono(52, .bold))
                    .foregroundStyle(palette.textGradient)
                HStack(spacing: 12) {
                    StatTile(value: "\(result.moves)", caption: app.t("common.moves"), systemImage: "arrow.triangle.2.circlepath")
                    StatTile(value: result.previousBest?.cubeTime ?? app.t("common.none"),
                             caption: app.t("result.previousBest"), systemImage: "trophy")
                    StatTile(value: comparison, caption: app.t("result.difference"), systemImage: "plusminus")
                }
                .padding(14)
                .background(palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                HStack(spacing: 12) {
                    SecondaryButton(title: app.t("common.close")) { dismiss() }
                    PrimaryButton(title: app.t("play.newScramble"), systemImage: "shuffle") { onAgain() }
                }
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.1)) { appeared = true }
        }
    }

    private var comparison: String {
        guard let best = result.previousBest else { return app.t("common.none") }
        let delta = result.time - best
        return (delta < 0 ? "−" : "+") + abs(delta).cubeTime
    }
}

/// Spoken description of the cube for VoiceOver: the colours on each face.
enum CubeDescriber {
    @MainActor
    static func describe(_ state: CubeState, app: AppModel) -> String {
        if state.isSolved { return app.t("a11y.cubeSolved") }
        let faces: [Face] = [.U, .F, .R, .B, .L, .D]
        return faces.map { face in
            var counts: [CubeColor: Int] = [:]
            for color in state.stickers(of: face) { counts[color, default: 0] += 1 }
            let parts = CubeColor.allCases.compactMap { color -> String? in
                guard let count = counts[color] else { return nil }
                return "\(count) \(app.t("color.\(color)"))"
            }
            return "\(app.t("face.\(face.letter)")): " + parts.joined(separator: ", ")
        }
        .joined(separator: ". ")
    }
}
