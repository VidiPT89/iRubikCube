import CubeCore
import RealityKit
import SwiftUI
import simd

/// Where a ray met the cube, in the cube's own frame.
struct CubeHit {
    var point: SIMD3<Float>
    var normal: SIMD3<Float>
}

enum DragState {
    case idle
    case pending(hit: CubeHit)
    case orbit(last: CGPoint)
    case layer(LayerDrag)
    case ignored

    var isActive: Bool {
        switch self {
        case .idle: false
        default: true
        }
    }
}

struct LayerDrag {
    var axis: CubeAxis
    var layer: Int
    /// Screen direction that turns the layer by a positive drag.
    var direction: CGVector
    var pixelsPerQuarter: CGFloat
    /// +1 or -1: how a positive drag maps onto the axis' rotation sense.
    var sign: Float
    var angle: Float = 0
    var detent = 0
}

struct SnapState {
    var axis: CubeAxis
    var layer: Int
    var angle: Float
    var velocity: Float = 0
    var quarters: Int
    var target: Float { Float(quarters) * .pi / 2 }
}

extension CubeScene {

    // MARK: Gestures

    func dragChanged(start: CGPoint, location: CGPoint) {
        guard interaction != .none else { return }
        idleSpinPause = 3
        switch drag {
        case .idle:
            if isAnimating { finishAnimations() }
            if snap != nil { completeSnapImmediately() }
            viewReset = nil
            if interaction == .full, let hit = hitTest(start) {
                drag = .pending(hit: hit)
            } else {
                drag = .orbit(last: start)
            }
            dragChanged(start: start, location: location)

        case .pending(let hit):
            let delta = CGVector(dx: location.x - start.x, dy: location.y - start.y)
            guard hypot(delta.dx, delta.dy) > 10 else { return }
            if let layer = beginLayerDrag(hit: hit, delta: delta) {
                drag = .layer(layer)
                dragChanged(start: start, location: location)
            } else {
                drag = .orbit(last: start)
            }

        case .orbit(let last):
            yaw += Float(location.x - last.x) * 0.0095
            pitch = min(1.35, max(-1.35, pitch + Float(location.y - last.y) * 0.0095))
            drag = .orbit(last: location)
            applyOrbit()

        case .layer(var layer):
            layer.angle = angle(for: layer, translation: CGVector(dx: location.x - start.x, dy: location.y - start.y))
            let detent = Int((layer.angle / (.pi / 2)).rounded())
            if detent != layer.detent {
                layer.detent = detent
                onDragDetent?()
            }
            drag = .layer(layer)
            setLayerAngle(turn: Turn(axis: layer.axis, layers: .single(layer.layer), quarters: 1), angle: layer.angle)

        case .ignored:
            break
        }
    }

    func dragEnded(start: CGPoint, location: CGPoint, predicted: CGPoint) {
        defer { drag = .idle }
        guard case .layer(let layer) = drag else { return }
        let now = angle(for: layer, translation: CGVector(dx: location.x - start.x, dy: location.y - start.y))
        let flung = angle(for: layer, translation: CGVector(dx: predicted.x - start.x, dy: predicted.y - start.y))
        let projected = now + (flung - now) * 0.3
        let quarters = max(-2, min(2, Int((projected / (.pi / 2)).rounded())))
        snap = SnapState(axis: layer.axis, layer: layer.layer, angle: now, quarters: quarters)
    }

    func pinchChanged(_ scale: CGFloat, base: Float) {
        guard interaction != .none else { return }
        zoom = min(1.6, max(0.65, base * Float(scale)))
        idleSpinPause = 3
        updateCamera()
    }

    /// Cancels a pending finger turn (used when a pinch takes over).
    func cancelDrag() {
        if case .layer = drag { resetLayerTransforms() }
        drag = .ignored
    }

    func finishDragImmediately() {
        if snap != nil { completeSnapImmediately() }
        if case .layer = drag {
            resetLayerTransforms()
            drag = .ignored
        }
    }

    // MARK: Snapping

    func advanceSnap(_ dt: TimeInterval) {
        guard var state = snap else { return }
        let stiffness: Float = 210
        let damping: Float = 2 * sqrt(stiffness) * 0.72
        let steps = 4
        let h = Float(dt) / Float(steps)
        for _ in 0..<steps {
            let force = -stiffness * (state.angle - state.target) - damping * state.velocity
            state.velocity += force * h
            state.angle += state.velocity * h
        }
        setLayerAngle(turn: Turn(axis: state.axis, layers: .single(state.layer), quarters: 1), angle: state.angle)
        if abs(state.angle - state.target) < 0.002 && abs(state.velocity) < 0.05 {
            snap = state
            completeSnapImmediately()
        } else {
            snap = state
        }
    }

    func completeSnapImmediately() {
        guard let state = snap else { return }
        snap = nil
        resetLayerTransforms()
        guard state.quarters != 0 else { return }
        let turn = Turn(axis: state.axis, layers: .single(state.layer), quarters: state.quarters)
        displayed.apply(turn)
        recolor()
        onUserTurn?(turn)
    }

    // MARK: Geometry

    private func beginLayerDrag(hit: CubeHit, delta: CGVector) -> LayerDrag? {
        let normal = hit.normal
        let candidates: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].filter { abs(simd_dot($0, normal)) < 0.5 }
        guard let origin = project(hit.point) else { return nil }
        var best: (axis: SIMD3<Float>, screen: CGVector, score: CGFloat)?
        for candidate in candidates {
            guard let tip = project(hit.point + candidate * 0.25) else { continue }
            let screen = CGVector(dx: tip.x - origin.x, dy: tip.y - origin.y)
            let length = hypot(screen.dx, screen.dy)
            guard length > 1 else { continue }
            let score = (delta.dx * screen.dx + delta.dy * screen.dy) / length
            if best == nil || abs(score) > abs(best?.score ?? 0) {
                best = (candidate, screen, score)
            }
        }
        guard let best else { return nil }
        let length = hypot(best.screen.dx, best.screen.dy)
        let direction = CGVector(dx: best.screen.dx / length, dy: best.screen.dy / length)
        // Rotation that carries the touched sticker along `candidate`.
        let spin = simd_cross(normal, best.axis)
        guard let axisIndex = (0..<3).max(by: { abs(spin[$0]) < abs(spin[$1]) }),
              let axis = CubeAxis(rawValue: axisIndex) else { return nil }
        let coordinate = hit.point[axisIndex]
        let layer = min(size - 1, max(0, Int(((coordinate + 0.5) * Float(size)).rounded(.down))))
        return LayerDrag(axis: axis, layer: layer, direction: direction,
                         pixelsPerQuarter: max(60, length / 0.25 * 0.5),
                         sign: spin[axisIndex] > 0 ? 1 : -1)
    }

    private func angle(for layer: LayerDrag, translation: CGVector) -> Float {
        let along = translation.dx * layer.direction.dx + translation.dy * layer.direction.dy
        return layer.sign * Float(along / layer.pixelsPerQuarter) * .pi / 2
    }

    /// Ray from the camera through a point of the view, in the cube's frame.
    func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)
        let tanV = tan(Self.verticalFOV / 2)
        let tanH = tanV * Float(width / height)
        let x = Float(2 * point.x / width - 1) * tanH
        let y = Float(1 - 2 * point.y / height) * tanV
        let inverse = orbitRotation.inverse
        return (inverse.act([0, 0, cameraDistance]), simd_normalize(inverse.act([x, y, -1])))
    }

    func hitTest(_ point: CGPoint) -> CubeHit? {
        let (origin, direction) = ray(through: point)
        let half: Float = 0.5
        var tNear = -Float.infinity
        var tFar = Float.infinity
        var nearAxis = 0
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-6 {
                if abs(origin[axis]) > half { return nil }
                continue
            }
            var t1 = (-half - origin[axis]) / direction[axis]
            var t2 = (half - origin[axis]) / direction[axis]
            if t1 > t2 { swap(&t1, &t2) }
            if t1 > tNear {
                tNear = t1
                nearAxis = axis
            }
            tFar = min(tFar, t2)
            if tNear > tFar { return nil }
        }
        guard tNear > 0 else { return nil }
        let point = origin + direction * tNear
        var normal = SIMD3<Float>(repeating: 0)
        normal[nearAxis] = point[nearAxis] > 0 ? 1 : -1
        return CubeHit(point: point, normal: normal)
    }

    /// Screen position of a point in the cube's frame.
    func project(_ local: SIMD3<Float>) -> CGPoint? {
        let world = orbitRotation.act(local)
        let depth = cameraDistance - world.z
        guard depth > 0.01 else { return nil }
        let tanV = tan(Self.verticalFOV / 2)
        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)
        let tanH = tanV * Float(width / height)
        let x = world.x / depth / tanH
        let y = world.y / depth / tanV
        return CGPoint(x: CGFloat(x + 1) / 2 * width, y: CGFloat(1 - y) / 2 * height)
    }
}
