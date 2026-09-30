import CubeCore
import Observation
import RealityKit
import SwiftUI
import simd

/// Owns the 3D cube: entities, the queue of animated turns, the camera
/// orbit and the finger-driven layer turns.
///
/// The logical cube lives in the screen's view model; the scene keeps its
/// own `displayed` copy that catches up as animations finish, so a burst of
/// moves never makes the picture jump.
@Observable
@MainActor
final class CubeScene {

    enum Interaction: Equatable {
        /// Layer turns, orbit, zoom.
        case full
        /// Orbit and zoom only (home screen, demonstrations).
        case orbitOnly
        case none
    }

    // MARK: Public state

    var size: Int
    var displayed: CubeState
    var interaction: Interaction = .full
    var scheme: CubeScheme = .standard { didSet { if scheme != oldValue { rebuildMaterials() } } }
    /// Seconds per quarter turn.
    var turnDuration: Double = 0.26
    var autoRotate = false
    /// Stickers to keep bright; everything else is dimmed. `nil` shows all.
    var highlighted: Set<Int>? { didSet { if highlighted != oldValue { recolor() } } }
    var isAnimating = false

    /// A finger turn has been committed (after the snap animation).
    @ObservationIgnored var onUserTurn: ((Turn) -> Void)?
    /// A turn starts animating (sound, haptics).
    @ObservationIgnored var onTurnStarted: ((Turn) -> Void)?
    /// A layer passed a 90° step while dragging.
    @ObservationIgnored var onDragDetent: (() -> Void)?
    @ObservationIgnored private var idleActions: [() -> Void] = []

    // MARK: Entities

    @ObservationIgnored let root = Entity()
    @ObservationIgnored let spinner = Entity()
    @ObservationIgnored let stageEntity = Entity()
    @ObservationIgnored let camera = PerspectiveCamera()
    @ObservationIgnored var cubies: [Vec3: ModelEntity] = [:]
    @ObservationIgnored var stickerEntities: [ModelEntity] = []
    @ObservationIgnored var glyphEntities: [ModelEntity] = []
    @ObservationIgnored var hintEntity: Entity?
    @ObservationIgnored var materials = MaterialSet()
    @ObservationIgnored private var subscription: EventSubscription?

    // MARK: Camera

    var viewSize: CGSize = CGSize(width: 390, height: 500) { didSet { updateCamera() } }
    static let defaultYaw: Float = -0.62
    static let defaultPitch: Float = 0.5
    @ObservationIgnored var yaw: Float = CubeScene.defaultYaw
    @ObservationIgnored var pitch: Float = CubeScene.defaultPitch
    @ObservationIgnored var zoom: Float = 1
    @ObservationIgnored var framing: Float = 1
    static let verticalFOV: Float = 30 * .pi / 180
    var cameraDistance: Float {
        let tanV = tan(Self.verticalFOV / 2)
        let aspect = Float(max(viewSize.width, 1) / max(viewSize.height, 1))
        let tanH = tanV * aspect
        let radius: Float = 1.0 * framing
        return radius / min(tanV, tanH) / zoom
    }

    // MARK: Animation state

    @ObservationIgnored var queue: [Turn] = []
    @ObservationIgnored var current: (turn: Turn, progress: Double, duration: Double)?
    @ObservationIgnored var drag = DragState.idle
    @ObservationIgnored var snap: SnapState?
    @ObservationIgnored var viewReset: (from: (Float, Float, Float), progress: Float)?
    @ObservationIgnored var celebration: Float?
    @ObservationIgnored var hintPhase: Float = 0
    @ObservationIgnored var idleSpinPause: Double = 0
    @ObservationIgnored var assembly: AssemblyState?

    init(size: Int = 3, state: CubeState? = nil) {
        self.size = size
        displayed = state ?? CubeState(size: size)
        root.addChild(spinner)
        buildCube()
        buildStage()
        applyOrbit()
    }

    /// Adds the scene to a `RealityView` and starts the frame loop.
    ///
    /// SwiftUI may build a second RealityView before tearing the first one
    /// down, and a torn-down view removes whatever it added. Each install
    /// therefore adds a fresh holder and moves the cube into it, so the old
    /// view only takes its own empty holder with it.
    func install(into content: inout RealityViewCameraContent) {
        let holder = Entity()
        holder.addChild(root)
        holder.addChild(stageEntity)
        holder.addChild(camera)
        content.add(holder)
        content.environment = .default
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(event.deltaTime)
        }
        updateCamera()
    }

    // MARK: Commands

    /// Shows `state` immediately, cancelling any animation.
    func show(_ state: CubeState) {
        queue.removeAll()
        current = nil
        snap = nil
        drag = .idle
        resetLayerTransforms()
        if state.size != size {
            size = state.size
            displayed = state
            buildCube()
        } else {
            displayed = state
        }
        hideHint()
        recolor()
        isAnimating = false
        runIdleActions()
    }

    /// Runs `action` once every queued turn has been animated.
    func whenIdle(_ action: @escaping () -> Void) {
        if current == nil && queue.isEmpty {
            action()
        } else {
            idleActions.append(action)
        }
    }

    private func runIdleActions() {
        let actions = idleActions
        idleActions.removeAll()
        actions.forEach { $0() }
    }

    /// Animates `turns` one after another.
    func enqueue(_ turns: [Turn]) {
        guard !turns.isEmpty else { return }
        finishDragImmediately()
        queue.append(contentsOf: turns)
        isAnimating = true
    }

    func enqueue(_ turn: Turn) { enqueue([turn]) }

    /// Jumps to the end of every queued animation.
    func finishAnimations() {
        if let active = current {
            displayed.apply(active.turn)
            current = nil
        }
        displayed.apply(queue)
        queue.removeAll()
        resetLayerTransforms()
        recolor()
        isAnimating = false
        runIdleActions()
    }

    func resetView(animated: Bool = true) {
        if animated {
            viewReset = ((yaw, pitch, zoom), 0)
        } else {
            yaw = Self.defaultYaw
            pitch = Self.defaultPitch
            zoom = 1
            applyOrbit()
            updateCamera()
        }
    }

    /// A full spin of the whole cube, for the solved celebration.
    func celebrate() {
        celebration = 0
    }

    // MARK: Frame loop

    func tick(_ dt: TimeInterval) {
        let dt = min(dt, 1.0 / 20)
        advanceTurns(dt)
        advanceSnap(dt)
        advanceView(Float(dt))
        advanceHint(Float(dt))
        advanceAssembly(Float(dt))
    }

    private func advanceTurns(_ dt: TimeInterval) {
        guard snap == nil, !drag.isActive else { return }
        if current == nil, !queue.isEmpty {
            let turn = queue.removeFirst()
            let base = turnDuration * (turn.isHalfTurn ? 1.45 : 1)
            // Catch up when many moves are waiting (scrambles, undo bursts).
            let duration = queue.count > 2 ? base * 0.55 : base
            current = (turn, 0, duration)
            onTurnStarted?(turn)
        }
        guard var active = current else { return }
        active.progress = min(1, active.progress + dt / max(active.duration, 0.01))
        current = active
        let eased = Self.easeInOut(active.progress)
        setLayerAngle(turn: active.turn, angle: Float(eased) * Float(active.turn.quarters) * .pi / 2)
        if active.progress >= 1 {
            current = nil
            displayed.apply(active.turn)
            resetLayerTransforms()
            recolor()
            if queue.isEmpty {
                isAnimating = false
                runIdleActions()
            }
        }
    }

    private func advanceView(_ dt: Float) {
        if var reset = viewReset {
            reset.progress = min(1, reset.progress + dt / 0.55)
            let k = Float(Self.easeInOut(Double(reset.progress)))
            yaw = reset.from.0 + (Self.defaultYaw - reset.from.0) * k
            pitch = reset.from.1 + (Self.defaultPitch - reset.from.1) * k
            zoom = reset.from.2 + (1 - reset.from.2) * k
            viewReset = reset.progress >= 1 ? nil : reset
            updateCamera()
        } else if autoRotate, !drag.isActive {
            idleSpinPause = max(0, idleSpinPause - Double(dt))
            if idleSpinPause == 0 { yaw += dt * 0.35 }
        }
        if var spin = celebration {
            spin = min(1, spin + dt / 1.3)
            let k = Float(Self.easeInOut(Double(spin)))
            spinner.orientation = simd_quatf(angle: k * 2 * .pi, axis: [0, 1, 0])
                * simd_quatf(angle: sin(k * .pi) * 0.35, axis: [1, 0, 0])
            spinner.scale = SIMD3(repeating: 1 + sin(k * .pi) * 0.08)
            celebration = spin >= 1 ? nil : spin
        }
        applyOrbit()
    }

    func applyOrbit() {
        root.orientation = orbitRotation
    }

    var orbitRotation: simd_quatf {
        simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    func updateCamera() {
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = Self.verticalFOV * 180 / .pi
        component.fieldOfViewOrientation = .vertical
        component.near = 0.05
        component.far = 50
        camera.components.set(component)
        camera.position = [0, 0, cameraDistance]
        camera.look(at: .zero, from: [0, 0, cameraDistance], relativeTo: nil)
    }

    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // MARK: Layer transforms

    /// Rotates the cubies of `turn`'s layers by `angle` around its axis.
    func setLayerAngle(turn: Turn, angle: Float) {
        let axisVector = Self.axisVector(turn.axis)
        let rotation = simd_quatf(angle: angle, axis: axisVector)
        for (coordinate, entity) in cubies {
            let layer = (coordinate[turn.axis] + size - 1) / 2
            guard turn.layers.contains(layer) else { continue }
            let home = homePosition(coordinate)
            entity.position = rotation.act(home)
            entity.orientation = rotation
        }
    }

    func resetLayerTransforms() {
        for (coordinate, entity) in cubies {
            entity.position = homePosition(coordinate)
            entity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
    }

    var cubieSize: Float { 1 / Float(size) }

    func homePosition(_ coordinate: Vec3) -> SIMD3<Float> {
        SIMD3(Float(coordinate.x), Float(coordinate.y), Float(coordinate.z)) * (cubieSize / 2)
    }

    static func axisVector(_ axis: CubeAxis) -> SIMD3<Float> {
        switch axis {
        case .x: [1, 0, 0]
        case .y: [0, 1, 0]
        case .z: [0, 0, 1]
        }
    }
}
