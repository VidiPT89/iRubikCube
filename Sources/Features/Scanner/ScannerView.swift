import CubeCore
import SwiftUI

/// Reads a real cube face by face, then opens the editor to fix anything.
struct ScannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Show a Cancel button (when presented modally rather than pushed).
    var showsCancel = false
    let onDone: (CubeState) -> Void

    @State private var camera = CameraController()
    @State private var captured: [Face: [RGB]] = [:]
    @State private var step = 0
    @State private var flash = false
    @State private var reviewColors: [CubeColor?]?

    private var current: (face: Face, up: Face)? {
        step < ColorClassifier.scanOrder.count ? ColorClassifier.scanOrder[step] : nil
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 16) {
                progressRow
                switch camera.status {
                case .running: cameraArea
                case .unknown: ProgressView().tint(palette.primary).frame(maxHeight: .infinity)
                case .unavailable: unavailable(app.t("scanner.unavailable"), systemImage: "camera.metering.unknown")
                case .denied: unavailable(app.t("scanner.denied"), systemImage: "lock.fill", showSettings: true)
                }
                bottom
            }
            .padding(16)
        }
        .navigationTitle(app.t("scanner.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.t("common.cancel")) { dismiss() }
                }
            }
        }
        .navigationDestination(item: $reviewColors) { colors in
            CubeEditorView(prefilled: colors) { state in
                app.announce(app.progress.recordScan())
                onDone(state)
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(ColorClassifier.scanOrder.enumerated()), id: \.offset) { index, item in
                let done = captured[item.face] != nil
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(done ? app.settings.cubeScheme.color(CubeColor.standard(for: item.face)) : palette.surfaceRaised)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black.opacity(0.6))
                    }
                }
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(index == step ? palette.primary : palette.stroke, lineWidth: index == step ? 2 : 1))
                .scaleEffect(index == step ? 1.12 : 1)
            }
        }
        .animation(.spring(response: 0.35), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text(app.t("scanner.progress", captured.count)))
    }

    private var cameraArea: some View {
        GeometryReader { geometry in
            let side = geometry.size.width * 0.7
            ZStack {
                CameraPreview(session: camera.session)
                Rectangle().fill(.black.opacity(0.35))
                    .mask {
                        Rectangle().overlay(RoundedRectangle(cornerRadius: 20).frame(width: side, height: side).blendMode(.destinationOut))
                            .compositingGroup()
                    }
                guide(side: side)
                if flash { Color.white.opacity(0.8).transition(.opacity) }
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.stroke))
        .frame(maxHeight: .infinity)
    }

    private func guide(side: CGFloat) -> some View {
        let cell = side / 3
        return ZStack {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(camera.locked ? palette.primary : .white.opacity(0.8), lineWidth: camera.locked ? 4 : 2)
            ForEach(0..<9, id: \.self) { index in
                let row = index / 3, col = index % 3
                Circle()
                    .fill(camera.samples.count == 9
                          ? app.settings.cubeScheme.color(ColorClassifier.guess(camera.samples[index])) : .clear)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: cell * 0.28, height: cell * 0.28)
                    .offset(x: (CGFloat(col) - 1) * cell, y: (CGFloat(row) - 1) * cell)
            }
            Path { path in
                for i in 1..<3 {
                    let offset = CGFloat(i) * cell
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset, y: side))
                    path.move(to: CGPoint(x: 0, y: offset))
                    path.addLine(to: CGPoint(x: side, y: offset))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .frame(width: side, height: side)
        .animation(.easeInOut(duration: 0.2), value: camera.locked)
        .accessibilityHidden(true)
    }

    private var bottom: some View {
        VStack(spacing: 12) {
            if let current {
                HStack(spacing: 10) {
                    StickerSwatch(color: CubeColor.standard(for: current.face), scheme: app.settings.cubeScheme, size: 26)
                    Text(app.t("scanner.instruction",
                               app.t("color.\(CubeColor.standard(for: current.face))"),
                               app.t("color.\(CubeColor.standard(for: current.up))")))
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 10) {
                SecondaryButton(title: app.t("scanner.manual"), systemImage: "square.grid.3x3.fill") {
                    reviewColors = Array(repeating: nil, count: 54)
                }
                Spacer()
                if step > 0 {
                    CircleIconButton(systemImage: "arrow.uturn.backward", label: app.t("scanner.retake")) {
                        step -= 1
                        captured[ColorClassifier.scanOrder[step].face] = nil
                    }
                }
                PrimaryButton(title: app.t("scanner.capture"), systemImage: "camera.fill") { capture() }
                    .disabled(camera.status != .running || camera.samples.count != 9)
            }
        }
    }

    private func unavailable(_ message: String, systemImage: String, showSettings: Bool = false) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(palette.primary)
            Text(message).font(.rounded(16, .medium)).foregroundStyle(palette.textDim).multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                SecondaryButton(title: app.t("scanner.openSettings"), systemImage: "gear") { openURL(url) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func capture() {
        guard let current, camera.samples.count == 9 else { return }
        captured[current.face] = camera.samples
        app.play(.snap)
        app.feel(.snap)
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        withAnimation(.easeIn(duration: 0.3).delay(0.08)) { flash = false }
        step += 1
        if step == ColorClassifier.scanOrder.count {
            let colors = ColorClassifier.classify(faces: captured)
            var stickers = [CubeColor?](repeating: nil, count: 54)
            for (face, list) in colors {
                for (index, color) in list.enumerated() { stickers[face.rawValue * 9 + index] = color }
            }
            reviewColors = stickers
        }
    }
}
