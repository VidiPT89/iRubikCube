import Combine
import CubeCore
import RealityKit
import SwiftUI
import UIKit

/// SwiftUI host for a `CubeScene`: a slot for the shared 3D view plus the
/// touch gestures.
struct CubeView: View {
    let scene: CubeScene
    var accessibilityLabel: String = "Cube"
    var accessibilityValue: String = ""

    @State private var pinchBase: Float?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CubeSlot(scene: scene).allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
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

/// The one 3D view of the app, lent to the oldest cube slot on screen.
///
/// Each `RealityView` brings its own Metal layer, and the simulator runs out
/// of drawables when a new one is built while the old one is still sliding
/// away (or before it has a size): the new view stays blank for good. A
/// single view that moves between screens never allocates a second layer.
@MainActor
final class CubeStage {
    static let shared = CubeStage()

    private var slots: [CubeSlotView] = []
    private var shown: CubeScene?
    private var subscription: (any Cancellable)?

    private lazy var view: ARView = {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(event.deltaTime)
        }
        return view
    }()

    fileprivate func add(_ slot: CubeSlotView) {
        if !slots.contains(where: { $0 === slot }) { slots.append(slot) }
        refresh()
    }

    fileprivate func remove(_ slot: CubeSlotView) {
        slots.removeAll { $0 === slot }
        refresh()
    }

    /// Moves the view into the oldest slot that is in a window and has a size.
    /// The oldest, so a screen keeps its cube while it slides away and the
    /// splash keeps it over the home screen being built underneath.
    fileprivate func refresh() {
        let target = slots.first { $0.window != nil && $0.bounds.width >= 1 && $0.bounds.height >= 1 }
        guard let target, let scene = target.scene else {
            view.removeFromSuperview()
            show(nil)
            return
        }
        if view.superview !== target { target.addSubview(view) }
        if view.frame != target.bounds { view.frame = target.bounds }
        show(scene)
    }

    private func show(_ scene: CubeScene?) {
        guard scene !== shown else { return }
        shown?.anchor.removeFromParent()
        if let scene {
            view.scene.addAnchor(scene.anchor)
            scene.updateCamera()
        }
        shown = scene
    }

    /// Every scene with a slot keeps animating, shown or not, so queued
    /// turns and their callbacks finish even while another screen has the view.
    private func tick(_ dt: TimeInterval) {
        var seen = Set<ObjectIdentifier>()
        for scene in slots.compactMap(\.scene) where seen.insert(ObjectIdentifier(scene)).inserted {
            scene.tick(dt)
        }
    }
}

/// A place on screen where the shared 3D view can show `scene`.
final class CubeSlotView: UIView {
    var scene: CubeScene? {
        didSet { if scene !== oldValue { CubeStage.shared.add(self) } }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        CubeStage.shared.refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CubeStage.shared.refresh()
    }
}

private struct CubeSlot: UIViewRepresentable {
    let scene: CubeScene

    func makeUIView(context: Context) -> CubeSlotView {
        let slot = CubeSlotView()
        slot.backgroundColor = .clear
        slot.scene = scene
        return slot
    }

    func updateUIView(_ slot: CubeSlotView, context: Context) {
        slot.scene = scene
    }

    static func dismantleUIView(_ slot: CubeSlotView, coordinator: ()) {
        CubeStage.shared.remove(slot)
    }
}
