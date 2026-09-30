import CubeCore
import RealityKit
import UIKit

/// Pre-built materials, so recolouring after every turn only swaps references.
struct MaterialSet {
    var stickers: [RealityKit.Material] = []
    var dimmed: [RealityKit.Material] = []
    var body: RealityKit.Material = SimpleMaterial()
    var glyph: RealityKit.Material = SimpleMaterial()
}

extension CubeScene {

    // MARK: Cube

    func buildCube() {
        for child in Array(spinner.children) { child.removeFromParent() }
        cubies.removeAll()
        stickerEntities.removeAll()
        glyphEntities.removeAll()
        rebuildMaterialsOnly()

        let s = cubieSize
        let bodyMesh = MeshResource.generateBox(size: s * 0.965, cornerRadius: s * 0.11)
        let stickerMesh = MeshResource.generatePlane(width: s * 0.8, depth: s * 0.8, cornerRadius: s * 0.13)
        let geometry = StickerGeometry.of(size)

        let reach = size - 1
        for x in stride(from: -reach, through: reach, by: 2) {
            for y in stride(from: -reach, through: reach, by: 2) {
                for z in stride(from: -reach, through: reach, by: 2) {
                    guard abs(x) == reach || abs(y) == reach || abs(z) == reach else { continue }
                    let coordinate = Vec3(x, y, z)
                    let cubie = ModelEntity(mesh: bodyMesh, materials: [materials.body])
                    cubie.position = homePosition(coordinate)
                    spinner.addChild(cubie)
                    cubies[coordinate] = cubie
                }
            }
        }

        for index in geometry.positions.indices {
            let face = geometry.faces[index]
            guard let cubie = cubies[geometry.cubie(of: index)] else { continue }
            let sticker = ModelEntity(mesh: stickerMesh, materials: [materials.stickers[0]])
            let normal = Self.vector(face.normal)
            sticker.position = normal * (s * 0.965 / 2 + s * 0.012)
            sticker.orientation = Self.rotation(fromUpTo: face.normal)
            cubie.addChild(sticker)
            stickerEntities.append(sticker)

            let glyph = ModelEntity()
            glyph.position = [0, s * 0.006, 0]
            glyph.isEnabled = false
            sticker.addChild(glyph)
            glyphEntities.append(glyph)
        }
        recolor()
    }

    /// Soft contact shadow and lights; they stay put while the cube orbits.
    func buildStage() {
        let shadow = Entity()
        shadow.position = [0, -0.92, 0]
        // Many faint discs stacked from wide to narrow read as a soft blur.
        let rings = 18
        for ring in 0..<rings {
            let radius = 0.85 - Float(ring) * 0.042
            var material = UnlitMaterial(color: .black)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.032))
            let disc = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: radius), materials: [material])
            disc.position.y = Float(ring) * 0.0004
            disc.scale = [1, 1, 0.55]
            shadow.addChild(disc)
        }
        shadow.name = "shadow"
        let stage = stageEntity
        stage.addChild(shadow)

        let key = DirectionalLight()
        key.light.intensity = 2600
        key.light.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.look(at: .zero, from: [-1.5, 3, 2.5], relativeTo: nil)
        stage.addChild(key)

        let rim = DirectionalLight()
        rim.light.intensity = 900
        rim.light.color = UIColor(red: 1, green: 0.78, blue: 0.45, alpha: 1)
        rim.look(at: .zero, from: [2.5, 1, -2], relativeTo: nil)
        stage.addChild(rim)
    }

    // MARK: Materials

    func rebuildMaterials() {
        rebuildMaterialsOnly()
        recolor()
    }

    func rebuildMaterialsOnly() {
        var set = MaterialSet()
        for color in CubeColor.allCases {
            set.stickers.append(Self.plastic(scheme.uiColor(color), dim: false))
            set.dimmed.append(Self.plastic(scheme.uiColor(color), dim: true))
        }
        var body = PhysicallyBasedMaterial()
        body.baseColor = .init(tint: UIColor(red: 0.07, green: 0.07, blue: 0.085, alpha: 1))
        body.roughness = .init(floatLiteral: 0.42)
        body.metallic = .init(floatLiteral: 0)
        body.clearcoat = .init(floatLiteral: 0.3)
        set.body = body
        var glyph = UnlitMaterial(color: UIColor(white: 0, alpha: 1))
        glyph.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        set.glyph = glyph
        materials = set
    }

    static func plastic(_ color: UIColor, dim: Bool) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        if dim {
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            material.baseColor = .init(tint: UIColor(hue: hue, saturation: saturation * 0.35,
                                                     brightness: brightness * 0.28, alpha: 1))
        } else {
            material.baseColor = .init(tint: color)
        }
        material.roughness = .init(floatLiteral: 0.3)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.6)
        material.clearcoat = .init(floatLiteral: dim ? 0.1 : 0.85)
        material.clearcoatRoughness = .init(floatLiteral: 0.1)
        return material
    }

    /// Paints every sticker from `displayed`.
    func recolor() {
        guard stickerEntities.count == displayed.stickers.count else { return }
        let showGlyphs = scheme == .highContrast
        for (index, sticker) in stickerEntities.enumerated() {
            let color = displayed.stickers[index]
            let dim = highlighted.map { !$0.contains(index) } ?? false
            let material = dim ? materials.dimmed[color.rawValue] : materials.stickers[color.rawValue]
            sticker.model?.materials = [material]

            let glyph = glyphEntities[index]
            if showGlyphs, !dim, let mesh = glyphMesh(for: CubeScheme.glyph(for: color)) {
                glyph.model = ModelComponent(mesh: mesh.mesh, materials: [materials.glyph])
                glyph.orientation = mesh.rotation
                glyph.isEnabled = true
            } else {
                glyph.isEnabled = false
            }
        }
    }

    private func glyphMesh(for glyph: CubeScheme.Glyph) -> (mesh: MeshResource, rotation: simd_quatf)? {
        let s = cubieSize
        let flat = s * 0.004
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        switch glyph {
        case .none:
            return nil
        case .circle:
            return (.generateCylinder(height: flat, radius: s * 0.14), identity)
        case .square:
            return (.generateBox(width: s * 0.26, height: flat, depth: s * 0.26), identity)
        case .diamond:
            return (.generateBox(width: s * 0.24, height: flat, depth: s * 0.24),
                    simd_quatf(angle: .pi / 4, axis: [0, 1, 0]))
        case .bar:
            return (.generateBox(width: s * 0.4, height: flat, depth: s * 0.1), identity)
        case .plus:
            return (.generateBox(width: s * 0.36, height: flat, depth: s * 0.09), identity)
        }
    }

    // MARK: Helpers

    static func vector(_ v: Vec3) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    /// Rotation that turns +Y (a plane's normal) into `normal`.
    static func rotation(fromUpTo normal: Vec3) -> simd_quatf {
        switch (normal.x, normal.y, normal.z) {
        case (0, 1, 0): simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        case (0, -1, 0): simd_quatf(angle: .pi, axis: [1, 0, 0])
        case (1, 0, 0): simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        case (-1, 0, 0): simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        case (0, 0, 1): simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        default: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        }
    }
}
