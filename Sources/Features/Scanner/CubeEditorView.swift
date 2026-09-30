import CubeCore
import SwiftUI

/// Colour-in net of the cube: tap a colour, then tap stickers. Used for
/// manual entry and to fix whatever the scanner misread.
struct CubeEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onDone: (CubeState) -> Void

    @State private var stickers: [CubeColor?]
    @State private var brush: CubeColor = .white
    @State private var errorKey: String?
    @State private var shake = 0

    init(start: CubeState, onDone: @escaping (CubeState) -> Void) {
        let usable = start.size == 3 ? start : CubeState()
        _stickers = State(initialValue: usable.stickers.map { Optional($0) })
        self.onDone = onDone
    }

    init(prefilled: [CubeColor?], onDone: @escaping (CubeState) -> Void) {
        var colors = prefilled.count == 54 ? prefilled : Array(repeating: nil, count: 54)
        for face in Face.allCases { colors[face.rawValue * 9 + 4] = CubeColor.standard(for: face) }
        _stickers = State(initialValue: colors)
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(spacing: 18) {
                    Text(app.t("editor.help"))
                        .font(.rounded(14, .medium))
                        .foregroundStyle(palette.textDim)
                        .multilineTextAlignment(.center)
                    net
                        .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    palettePicker
                    if let errorKey {
                        Label(app.t(errorKey), systemImage: "exclamationmark.triangle.fill")
                            .font(.rounded(14, .semibold))
                            .foregroundStyle(palette.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .transition(.opacity)
                    }
                    HStack(spacing: 10) {
                        SecondaryButton(title: app.t("editor.clear"), systemImage: "eraser.fill") {
                            withAnimation { clear() }
                        }
                        SecondaryButton(title: app.t("editor.solved"), systemImage: "cube.fill") {
                            withAnimation { stickers = CubeState().stickers.map { Optional($0) } }
                        }
                    }
                    PrimaryButton(title: app.t("editor.solve"), systemImage: "wand.and.stars") { finish() }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(app.t("editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(app.t("common.cancel")) { dismiss() }
            }
        }
        .animation(.spring(response: 0.35), value: errorKey)
    }

    // MARK: Net

    /// Face positions in the unfolded cross: (column, row) in face units.
    private static let layout: [(Face, Int, Int)] = [(.U, 1, 0), (.L, 0, 1), (.F, 1, 1), (.R, 2, 1), (.B, 3, 1), (.D, 1, 2)]

    private var net: some View {
        GeometryReader { geometry in
            let cell = min(geometry.size.width / 12.6, 44)
            let faceSide = cell * 3 + 4
            ZStack(alignment: .topLeading) {
                ForEach(Self.layout, id: \.0) { face, column, row in
                    faceGrid(face, cell: cell)
                        .offset(x: CGFloat(column) * (faceSide + 3), y: CGFloat(row) * (faceSide + 3))
                }
            }
            .frame(width: 4 * faceSide + 9, height: 3 * faceSide + 6, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(4.2 / 3.1, contentMode: .fit)
    }

    private func faceGrid(_ face: Face, cell: CGFloat) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { col in
                        sticker(face.rawValue * 9 + row * 3 + col, face: face, cell: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sticker(_ index: Int, face: Face, cell: CGFloat) -> some View {
        let isCenter = index % 9 == 4
        Button {
            guard !isCenter else { return }
            stickers[index] = brush
            errorKey = nil
            app.feel(.tap)
        } label: {
            Group {
                if let color = stickers[index] {
                    StickerSwatch(color: color, scheme: app.settings.cubeScheme, size: cell)
                } else {
                    RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                        .strokeBorder(palette.textFaint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: cell, height: cell)
                }
            }
            .overlay {
                if isCenter {
                    Text(face.letter).font(.rounded(cell * 0.35, .heavy)).foregroundStyle(.black.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(app.t("face.\(face.letter)")) \(index % 9 + 1)"))
        .accessibilityValue(Text(stickers[index].map { app.t("color.\($0)") } ?? app.t("editor.empty")))
    }

    private var palettePicker: some View {
        HStack(spacing: 10) {
            ForEach(CubeColor.allCases, id: \.self) { color in
                let count = stickers.filter { $0 == color }.count
                Button {
                    brush = color
                    app.feel(.tap)
                } label: {
                    VStack(spacing: 4) {
                        StickerSwatch(color: color, scheme: app.settings.cubeScheme, size: 40)
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(brush == color ? palette.primary : .clear, lineWidth: 3)
                                .padding(-4))
                            .scaleEffect(brush == color ? 1.1 : 1)
                        Text("\(count)/9")
                            .font(.mono(11, .bold))
                            .foregroundStyle(count == 9 ? palette.success : (count > 9 ? palette.danger : palette.textDim))
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(app.t("color.\(color)")))
                .accessibilityValue(Text("\(count)/9"))
                .accessibilityAddTraits(brush == color ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.3), value: brush)
    }

    // MARK: Actions

    private func clear() {
        for index in stickers.indices where index % 9 != 4 { stickers[index] = nil }
        errorKey = nil
    }

    private func finish() {
        guard stickers.allSatisfy({ $0 != nil }) else {
            errorKey = "editor.incomplete"
            fail()
            return
        }
        guard let state = CubeState(size: 3, stickers: stickers.compactMap { $0 }) else { return }
        do {
            _ = try CubieCube(state: state)
            app.play(.correct)
            onDone(state)
        } catch {
            errorKey = error.messageKey
            fail()
        }
    }

    private func fail() {
        app.play(.wrong)
        app.feel(.warning)
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
    }
}

/// Horizontal shake for invalid input.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}
