import SwiftData
import SwiftUI

@main
struct iRubikCubeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    private let container = SolveStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .themed()
                .environment(model)
                .modelContainer(container)
                .onAppear { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.becameActive()
            case .background: model.resignedActive()
            default: break
            }
        }
    }
}

/// Resolves the palette from the chosen appearance and applies it with the
/// colour scheme, locale and toast layer. Used at the root and on every
/// sheet, which do not always inherit custom environment values.
struct ThemedModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let scheme = model.settings.appearance.colorScheme
        let palette = Palette.resolve(scheme ?? systemScheme)
        content
            .environment(\.palette, palette)
            .environment(\.locale, model.language.locale)
            .preferredColorScheme(scheme)
            .tint(palette.primary)
            // Beyond this the cube screens have no room left for the cube itself.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .modifier(ToastHost())
    }
}

/// Shows the current toast on whichever layer is on top.
private struct ToastHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var level = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = model.toast, level == model.presentationDepth {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                model.presentationDepth += 1
                level = model.presentationDepth
            }
            .onDisappear { model.presentationDepth -= 1 }
    }
}

struct ToastView: View {
    @Environment(\.palette) private var palette
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x0A0A0F))
                .frame(width: 38, height: 38)
                .background(palette.brandGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.rounded(12, .heavy)).foregroundStyle(palette.primary)
                Text(toast.message).font(.rounded(15, .semibold)).foregroundStyle(palette.text)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.primary.opacity(0.35)))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func themed() -> some View { modifier(ThemedModifier()) }
}
