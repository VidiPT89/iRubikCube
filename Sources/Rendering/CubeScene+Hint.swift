import CubeCore
import RealityKit
import UIKit
import simd

/// The animated 3D arrow that shows which layer to turn next.
extension CubeScene {

    func showHint(_ turn: Turn) {
        hideHint()
        let arrow = Entity()
        arrow.name = "hint"

        let axisIndex = turn.axis.rawValue
        let axis = Self.axisVector(turn.axis)
        let layers = turn.layers.layers(size: size)
        let wholeCube = layers.count == size
        // Middle of the moving block of layers, in cube units.
        let middle = layers.map { (Float($0) + 0.5) / Float(size) - 0.5 }.reduce(0, +) / Float(max(layers.count, 1))
        let center = axis * (wholeCube ? 0 : middle)
        let radius: Float = wholeCube ? 0.95 : 0.8

        // Sweep centred on the side of the ring facing the camera.
        let towardCamera = orbitRotation.inverse.act([0, 0, 1])
        let (u, v) = Self.planeBasis(for: axisIndex)
        let facing = atan2(simd_dot(towardCamera, v), simd_dot(towardCamera, u))
        let direction: Float = turn.quarters > 0 ? 1 : -1
        let sweep: Float = (turn.isHalfTurn ? 1.6 : 1.1) * direction
        let startAngle = facing - sweep / 2

        var material = UnlitMaterial(color: UIColor(red: 0.98, green: 0.61, blue: 0, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        let dotMesh = MeshResource.generateSphere(radius: 0.024)
        let dots = 16
        for i in 0..<dots {
            let t = Float(i) / Float(dots - 1)
            let angle = startAngle + sweep * t
            let dot = ModelEntity(mesh: dotMesh, materials: [material])
            dot.position = center + (u * cos(angle) + v * sin(angle)) * radius
            dot.name = "dot\(i)"
            arrow.addChild(dot)
        }

        let endAngle = startAngle + sweep
        let tip = center + (u * cos(endAngle) + v * sin(endAngle)) * radius
        let tangent = simd_normalize((u * -sin(endAngle) + v * cos(endAngle)) * direction)
        var headMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.74, blue: 0, alpha: 1))
        headMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        let head = ModelEntity(mesh: .generateCone(height: 0.13, radius: 0.06), materials: [headMaterial])
        head.position = tip + tangent * 0.03
        head.orientation = simd_quatf(from: [0, 1, 0], to: tangent)
        arrow.addChild(head)

        spinner.addChild(arrow)
        hintEntity = arrow
        hintPhase = 0
    }

    func hideHint() {
        hintEntity?.removeFromParent()
        hintEntity = nil
    }

    func advanceHint(_ dt: Float) {
        guard let arrow = hintEntity else { return }
        hintPhase += dt
        let count = Float(max(arrow.children.count - 1, 1))
        for (i, child) in arrow.children.enumerated() {
            guard child.name.hasPrefix("dot") else {
                let pulse = 1 + 0.12 * sin(hintPhase * 6)
                child.scale = SIMD3(repeating: pulse)
                continue
            }
            // A bright wave travels along the arc towards the arrow head.
            let wave = sin(hintPhase * 5 - Float(i) / count * 6)
            child.scale = SIMD3(repeating: 0.75 + 0.45 * max(0, wave))
        }
    }

    /// Two unit vectors spanning the plane perpendicular to an axis, ordered
    /// so that turning from the first to the second is a positive rotation.
    static func planeBasis(for axisIndex: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        switch axisIndex {
        case 0: ([0, 1, 0], [0, 0, 1])
        case 1: ([0, 0, 1], [1, 0, 0])
        default: ([1, 0, 0], [0, 1, 0])
        }
    }
}
