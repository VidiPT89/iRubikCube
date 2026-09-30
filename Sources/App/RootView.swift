import CubeCore
import SwiftUI

struct RootView: View {
    @State private var scene = CubeScene(size: 3, state: CubeState().applying(Notation.turns("R U F")))

    var body: some View {
        ZStack {
            Backdrop()
            CubeView(scene: scene)
        }
    }
}
