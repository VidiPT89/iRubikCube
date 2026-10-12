import GameKit
import UIKit

/// Signs the player in to Game Center, so the app shows up in Apple Games,
/// and on iOS 26 reports each solve as a game activity there.
@MainActor
final class GameCenter {

    /// The game activity set up in App Store Connect for a timed solve.
    static let solveActivityID = "solve"

    private var handlerSet = false
    /// A `GKGameActivity` on iOS 26; `Any` so the app still runs on iOS 18.
    private var activity: Any?
    /// Bumped on every start and end, so a definition that loads late does
    /// not start an activity for a round that is already over.
    private var round = 0

    var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    /// Asks Game Center for the player, once per launch. iOS shows its welcome
    /// banner or hands back a sign-in screen, presented over the app. GameKit
    /// calls the handler again by itself when the player signs in later in
    /// Settings, so a declined sign-in is not asked again on every round.
    func signIn() {
        guard !handlerSet else { return }
        handlerSet = true
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            MainActor.assumeIsolated {
                if let viewController { Self.present(viewController) }
            }
        }
    }

    /// A round has started: tell Apple Games, if the player is signed in.
    func gameStarted() {
        signIn()
        guard isSignedIn, #available(iOS 26.0, *) else { return }
        endActivity()
        let round = round
        GKGameActivityDefinition.loadGameActivityDefinitions(IDs: [Self.solveActivityID]) { [weak self] definitions, _ in
            guard let definition = definitions?.first else { return }
            Task { @MainActor in
                guard let self, self.round == round else { return }
                let activity = GKGameActivity(definition: definition)
                activity.start()
                self.activity = activity
            }
        }
    }

    /// The round was solved or abandoned.
    func gameEnded() {
        guard #available(iOS 26.0, *) else { return }
        endActivity()
    }

    @available(iOS 26.0, *)
    private func endActivity() {
        round += 1
        (activity as? GKGameActivity)?.end()
        activity = nil
    }

    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(viewController, animated: true)
    }
}
