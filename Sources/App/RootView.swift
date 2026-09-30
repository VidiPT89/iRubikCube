import CubeCore
import SwiftUI

/// Every screen reachable from the home screen.
enum Route: Hashable {
    case play
    case daily
    case assist(CubeState?)
    case learn
    case lesson(LessonID)
    case scanner
    case stats
}

/// Splash first, then the navigation stack with the home screen.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var showSplash = true
    @State private var path: [Route] = []

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: Route.self) { route in
                        destination(route)
                    }
            }
            .opacity(showSplash ? 0 : 1)
            .scaleEffect(showSplash ? 1.04 : 1)

            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.6)) { showSplash = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.08)))
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .play: PlayView(app: app)
        case .daily: PlayView(app: app, isDaily: true)
        case .assist(let state): AssistView(app: app, state: state)
        case .learn: LearnView()
        case .lesson(let lesson): LessonView(lesson: lesson, app: app)
        case .stats: StatsView()
        case .scanner:
            ScannerView { state in
                path.removeLast()
                path.append(.assist(state))
            }
        }
    }
}
