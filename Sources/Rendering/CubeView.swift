import CubeCore
import RealityKit
import SwiftUI

/// SwiftUI host for a `CubeScene`: RealityView plus the touch gestures.
struct CubeView: View {
    let scene: CubeScene
    var accessibilityLabel: String = "Cube"
    var accessibilityValue: String = ""

    @State private var pinchBase: Float?

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                scene.install(into: &content)
            }
            .onAppear { scene.viewSize = geometry.size }
            .onChange(of: geometry.size) { _, size in scene.viewSize = size }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        guard pinchBase == nil else { return }
                        scene.dragChanged(start: value.startLocation, location: value.location)
                    }
                    .onEnded { value in
                        scene.dragEnded(start: value.startLocation, location: value.location,
                                        predicted: value.predictedEndLocation)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchBase == nil {
                            pinchBase = scene.zoom
                            scene.cancelDrag()
                        }
                        scene.pinchChanged(value.magnification, base: pinchBase ?? 1)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
            .onTapGesture(count: 2) { scene.resetView() }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }
}
