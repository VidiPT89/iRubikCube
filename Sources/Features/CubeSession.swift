import CubeCore
import Observation
import SwiftUI

/// The logical cube behind a screen, its undo/redo history and the 3D scene
/// that shows it. Play, Assist and Learn each own one.
@Observable
@MainActor
final class CubeSession {

    enum Source { case user, program, undo, redo }

    let scene: CubeScene
    private(set) var state: CubeState
    private(set) var history: [Turn] = []
    private(set) var future: [Turn] = []

    /// Every change of the logical cube, after it happened.
    @ObservationIgnored var onMove: ((Turn, Source) -> Void)?
    @ObservationIgnored private weak var model: AppModel?

    init(size: Int = 3, state: CubeState? = nil, model: AppModel?) {
        let start = state ?? CubeState(size: size)
        self.state = start
        self.model = model
        scene = CubeScene(size: start.size, state: start)
        scene.onUserTurn = { [weak self] turn in self?.gestureTurned(turn) }
        scene.onTurnStarted = { [weak self] _ in
            self?.model?.play(.turn)
            self?.model?.feel(.detent)
        }
        scene.onDragDetent = { [weak self] in
            self?.model?.feel(.detent)
            self?.model?.play(.tick)
        }
        applySettings()
    }

    var size: Int { state.size }
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var moveCount: Int { history.count }

    func applySettings() {
        guard let model else { return }
        scene.turnDuration = model.settings.animationSpeed.quarterTurn
        scene.scheme = model.settings.cubeScheme
    }

    // MARK: Moves

    /// A move asked for by the player (buttons) or by the app (hints, playback).
    func perform(_ turn: Turn, source: Source = .user) {
        state.apply(turn)
        scene.enqueue(turn)
        record(turn, source: source)
    }

    func perform(_ turns: [Turn], source: Source = .program) {
        for turn in turns { perform(turn, source: source) }
    }

    private func gestureTurned(_ turn: Turn) {
        state.apply(turn)
        model?.play(.snap)
        model?.feel(.snap)
        record(turn, source: .user)
    }

    private func record(_ turn: Turn, source: Source) {
        switch source {
        case .user, .program:
            history.append(turn)
            future.removeAll()
        case .undo:
            break
        case .redo:
            history.append(turn)
        }
        onMove?(turn, source)
    }

    func undo() {
        guard let last = history.popLast() else { return }
        future.append(last)
        perform(last.inverse, source: .undo)
    }

    func redo() {
        guard let next = future.popLast() else { return }
        perform(next, source: .redo)
    }

    // MARK: Whole state

    /// Replaces the cube without animation and clears the history.
    func load(_ newState: CubeState) {
        state = newState
        history.removeAll()
        future.removeAll()
        scene.show(newState)
    }

    /// Animates a sequence quickly (scrambles, lesson set-ups) and clears history.
    func animateSetup(_ turns: [Turn], fast: Bool = true) {
        let previous = scene.turnDuration
        if fast { scene.turnDuration = min(previous, 0.12) }
        state.apply(turns)
        scene.enqueue(turns)
        history.removeAll()
        future.removeAll()
        scene.whenIdle { [weak self] in self?.scene.turnDuration = previous }
    }

    /// Readable move history in notation.
    var historyText: String { Notation.format(history, size: size) }
}
