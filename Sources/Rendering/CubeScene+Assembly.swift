import CubeCore
import RealityKit
import simd

/// Pieces flying in from all around and clicking into place (splash screen).
struct AssemblyState {
    struct Piece {
        var start: SIMD3<Float>
        var spin: simd_quatf
        var delay: Float
    }
    var elapsed: Float = 0
    var pieces: [Vec3: Piece]
    var duration: Float
    var onFinished: (() -> Void)?
}

extension CubeScene {

    /// Explodes the cubies and animates them back together over `duration` seconds.
    func playAssembly(duration: Float = 1.6, onFinished: (() -> Void)? = nil) {
        var generator = SeededGenerator(seed: 42)
        var pieces: [Vec3: AssemblyState.Piece] = [:]
        for coordinate in cubies.keys {
            let home = homePosition(coordinate)
            let direction = simd_length(home) > 0.001 ? simd_normalize(home) : SIMD3<Float>(0, 1, 0)
            let scatter = SIMD3<Float>(Float.random(in: -0.6...0.6, using: &generator),
                                       Float.random(in: -0.6...0.6, using: &generator),
                                       Float.random(in: -0.6...0.6, using: &generator))
            let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1, using: &generator),
                                                   Float.random(in: -1...1, using: &generator), 0.3))
            pieces[coordinate] = AssemblyState.Piece(
                start: direction * Float.random(in: 2.2...3.2, using: &generator) + scatter,
                spin: simd_quatf(angle: Float.random(in: 2...5, using: &generator), axis: axis),
                delay: Float.random(in: 0...0.35, using: &generator)
            )
        }
        assembly = AssemblyState(pieces: pieces, duration: duration, onFinished: onFinished)
        advanceAssembly(0)
    }

    func advanceAssembly(_ dt: Float) {
        guard var state = assembly else { return }
        state.elapsed += dt
        let travel = state.duration * 0.72
        for (coordinate, entity) in cubies {
            guard let piece = state.pieces[coordinate] else { continue }
            let raw = (state.elapsed - piece.delay) / travel
            let t = min(1, max(0, raw))
            // Ease out with a tiny overshoot, like a piece snapping in.
            let eased = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2)
            let home = homePosition(coordinate)
            entity.position = piece.start + (home - piece.start) * eased
            entity.orientation = simd_slerp(piece.spin, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), min(1, t * 1.15))
            entity.scale = SIMD3(repeating: 0.2 + 0.8 * min(1, t * 1.6))
        }
        if state.elapsed >= state.duration {
            assembly = nil
            resetLayerTransforms()
            for entity in cubies.values { entity.scale = .one }
            state.onFinished?()
        } else {
            assembly = state
        }
    }
}
