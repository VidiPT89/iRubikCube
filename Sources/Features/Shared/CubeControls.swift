import CubeCore
import SwiftUI

/// Collapsible grid of notation buttons for players who prefer to tap.
struct NotationPad: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let size: Int
    var isEnabled = true
    let onTurn: (Turn) -> Void

    @State private var prime = false
    @State private var double = false

    private var tokens: [String] {
        var list = ["R", "L", "U", "D", "F", "B"]
        if size >= 3 { list += ["M", "E", "S"] }
        if size >= 4 { list += ["Rw", "Uw", "Fw"] }
        list += ["x", "y", "z"]
        return list
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                modifierToggle("′", isOn: $prime, other: $double, label: model.t("notation.primeToggle"))
                modifierToggle("2", isOn: $double, other: $prime, label: model.t("notation.doubleToggle"))
                Spacer()
                Text(model.t("notation.padHint"))
                    .font(.rounded(12, .medium))
                    .foregroundStyle(palette.textDim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(tokens, id: \.self) { token in
                    let full = token + (prime ? "'" : (double ? "2" : ""))
                    Button {
                        guard let turn = try? Notation.parseToken(full, size: size) else { return }
                        onTurn(turn)
                    } label: {
                        Text(full)
                            .font(.mono(16, .bold))
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.stroke))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text(NotationSpeech.describe(full, model: model)))
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func modifierToggle(_ title: String, isOn: Binding<Bool>, other: Binding<Bool>, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isOn.wrappedValue.toggle()
                if isOn.wrappedValue { other.wrappedValue = false }
            }
        } label: {
            Text(title)
                .font(.mono(16, .heavy))
                .foregroundStyle(isOn.wrappedValue ? Color(hex: 0x0A0A0F) : palette.primary)
                .frame(width: 44, height: 34)
                .background {
                    if isOn.wrappedValue {
                        Capsule().fill(palette.brandGradient)
                    } else {
                        Capsule().fill(palette.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// VoiceOver wording for a notation token, e.g. "R'" → "Right face anticlockwise".
enum NotationSpeech {
    @MainActor
    static func describe(_ token: String, model: AppModel) -> String {
        var base = token
        var suffix = model.t("notation.speak.clockwise")
        if base.hasSuffix("'") {
            base.removeLast()
            suffix = model.t("notation.speak.anticlockwise")
        } else if base.hasSuffix("2") {
            base.removeLast()
            suffix = model.t("notation.speak.double")
        }
        let name = model.t("notation.name.\(base)")
        return "\(name), \(suffix)"
    }
}

/// Horizontal strip with the moves made so far; the latest one glows.
struct MoveHistoryStrip: View {
    @Environment(\.palette) private var palette
    let turns: [Turn]
    let size: Int
    var emptyText: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if turns.isEmpty {
                        Text(emptyText)
                            .font(.rounded(13, .medium))
                            .foregroundStyle(palette.textFaint)
                    }
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        Chip(text: Notation.format(turn, size: size), highlighted: index == turns.count - 1)
                            .id(index)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: turns.count)
            }
            .onChange(of: turns.count) { _, count in
                withAnimation { proxy.scrollTo(count - 1, anchor: .trailing) }
            }
        }
        .frame(height: 32)
    }
}

/// Orange and amber confetti bursting from the top of the screen.
struct ConfettiView: View {
    /// Change the value to fire a new burst.
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        var x: Double
        var delay: Double
        var speed: Double
        var drift: Double
        var spin: Double
        var size: Double
        var color: Color
    }

    private static let colors: [Color] = [
        Color(hex: 0xF99C00), Color(hex: 0xFCBB00), Color(hex: 0xFE6E00), Color(hex: 0xDD7400), .white,
    ]

    private let pieces: [Piece] = (0..<90).map { i in
        var generator = SeededGenerator(seed: UInt64(i) &* 2_654_435_761)
        return Piece(x: Double.random(in: 0...1, using: &generator),
                     delay: Double.random(in: 0...0.5, using: &generator),
                     speed: Double.random(in: 0.35...0.7, using: &generator),
                     drift: Double.random(in: -0.12...0.12, using: &generator),
                     spin: Double.random(in: 2...9, using: &generator),
                     size: Double.random(in: 6...12, using: &generator),
                     color: colors[i % colors.count])
    }

    var body: some View {
        ZStack {
            if start != nil { particles }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            start = .now
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                start = nil
            }
        }
    }

    private var particles: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -0.05 + t * piece.speed
                    guard y < 1.1 else { continue }
                    let x = piece.x + sin(t * 3 + piece.spin) * 0.03 + piece.drift * t
                    var rect = context
                    rect.translateBy(x: x * size.width, y: y * size.height)
                    rect.rotate(by: .radians(t * piece.spin))
                    let width = piece.size
                    let height = piece.size * (0.45 + 0.35 * abs(sin(t * piece.spin)))
                    rect.fill(Path(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                   cornerRadius: 2),
                              with: .color(piece.color.opacity(max(0, min(1, (1.1 - y) * 3)))))
                }
            }
        }
    }
}
