import CubeCore
import Foundation
import Observation

/// The player solves; the app helps on request.
@Observable
@MainActor
final class AssistModel {

    enum Method: String, CaseIterable, Identifiable {
        case optimal, beginner
        var id: String { rawValue }
    }

    struct Playback {
        var turns: [Turn]
        var index = 0
        var isPlaying = true
        var isFinished: Bool { index >= turns.count }
    }

    enum Speed: Double, CaseIterable, Identifiable {
        case slow = 0.6, normal = 1, fast = 1.8
        var id: Double { rawValue }
    }

    let session: CubeSession
    var method: Method = .optimal {
        didSet {
            guard method != oldValue else { return }
            stopPlayback()
            invalidate()
        }
    }
    private(set) var isComputing = false
    private(set) var solution: [Turn]?
    private(set) var steps: [SolveStep]?
    private(set) var error: CubeValidationError?
    private(set) var hintTurn: Turn?
    private(set) var playback: Playback?
    var speed: Speed = .normal
    private(set) var confetti = 0

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var computeTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var solutionState: CubeState?
    @ObservationIgnored private var revision = UUID()

    init(app: AppModel, state: CubeState? = nil) {
        self.app = app
        session = CubeSession(size: 3, state: state, model: app)
        session.onMove = { [weak self] turn, source in self?.moved(turn, source: source) }
    }

    var stage: BeginnerStage { BeginnerSolver.stage(of: session.state) }
    var isSolved: Bool { session.state.isSolved }

    /// Beginner step that contains the next move of the solution.
    var currentStep: SolveStep? {
        guard method == .beginner, let steps else { return nil }
        var index = playback?.index ?? 0
        for step in steps {
            if index < step.turns.count { return step }
            index -= step.turns.count
        }
        return nil
    }

    // MARK: Cube set-up

    func scramble() {
        stopPlayback()
        invalidate()
        session.load(CubeState())
        session.animateSetup(Scrambler.scramble(size: 3))
        app?.play(.whoosh)
    }

    func load(_ state: CubeState) {
        stopPlayback()
        invalidate()
        session.load(state)
    }

    func reset() {
        stopPlayback()
        invalidate()
        session.load(CubeState())
    }

    // MARK: Help

    func showHint() {
        withSolution { [weak self] turns in
            guard let self, let next = turns.first else { return }
            self.hintTurn = next
            self.session.scene.showHint(next)
            self.app?.play(.tap)
        }
    }

    func doNextMove() {
        withSolution { [weak self] turns in
            guard let self, let next = turns.first else { return }
            self.clearHint()
            self.session.perform(next, source: .program)
        }
    }

    func solveAll() {
        withSolution { [weak self] turns in
            guard let self, !turns.isEmpty else { return }
            self.clearHint()
            self.playback = Playback(turns: turns)
            self.runPlayback()
        }
    }

    func togglePlay() {
        guard var current = playback else { return }
        if current.isFinished { return }
        current.isPlaying.toggle()
        playback = current
        if current.isPlaying { runPlayback() } else { playTask?.cancel() }
    }

    func stepForward() {
        guard var current = playback, !current.isFinished else { return }
        playTask?.cancel()
        current.isPlaying = false
        let turn = current.turns[current.index]
        current.index += 1
        playback = current
        session.perform(turn, source: .program)
    }

    func stepBackward() {
        guard var current = playback, current.index > 0 else { return }
        playTask?.cancel()
        current.isPlaying = false
        current.index -= 1
        playback = current
        session.perform(current.turns[current.index].inverse, source: .program)
    }

    func stopPlayback() {
        playTask?.cancel()
        if playback != nil {
            solution = nil
            solutionState = nil
            steps = nil
        }
        playback = nil
    }

    func deactivate() {
        stopPlayback()
        invalidate()
        // Release any playback continuation waiting for the disappearing view.
        session.scene.finishAnimations()
    }

    private func runPlayback() {
        playTask?.cancel()
        playTask = Task { @MainActor [weak self] in
            while let self, var current = self.playback, current.isPlaying, !current.isFinished {
                await self.waitUntilIdle()
                try? await Task.sleep(for: .seconds(0.25 / self.speed.rawValue))
                guard !Task.isCancelled, let latest = self.playback, latest.isPlaying, !latest.isFinished else { return }
                current = latest
                let turn = current.turns[current.index]
                current.index += 1
                if current.isFinished { current.isPlaying = false }
                self.playback = current
                let previous = self.session.scene.turnDuration
                self.session.scene.turnDuration = (self.app?.settings.animationSpeed.quarterTurn ?? 0.26) / self.speed.rawValue
                self.session.perform(turn, source: .program)
                self.session.scene.whenIdle { [weak self] in self?.session.scene.turnDuration = previous }
            }
        }
    }

    private func waitUntilIdle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.scene.whenIdle { continuation.resume() }
        }
    }

    private func clearHint() {
        hintTurn = nil
        session.scene.hideHint()
    }

    // MARK: Moves

    private func moved(_ turn: Turn, source: CubeSession.Source) {
        clearHint()
        if source == .program, playback != nil {
            // Playback owns the complete plan; cached hints no longer match.
            solution = nil
            solutionState = nil
        } else if source == .program, let solution, let first = solution.first, first.isEquivalent(to: turn) {
            self.solution = Array(solution.dropFirst())
            solutionState = session.state
            trimSteps()
        } else {
            stopPlayback()
            invalidate()
        }
        if isSolved {
            let id = revision
            session.scene.whenIdle { [weak self] in
                guard let self, self.revision == id, self.isSolved else { return }
                self.session.scene.celebrate()
                self.confetti += 1
                self.app?.play(.solved)
                self.app?.feel(.solved)
            }
        }
    }

    private func trimSteps() {
        guard var list = steps, !list.isEmpty else { return }
        while let first = list.first, first.turns.isEmpty { list.removeFirst() }
        guard !list.isEmpty else { steps = []; return }
        list[0].turns.removeFirst()
        if list[0].turns.isEmpty { list.removeFirst() }
        steps = list
    }

    private func invalidate() {
        revision = UUID()
        computeTask?.cancel()
        solution = nil
        steps = nil
        solutionState = nil
        error = nil
        isComputing = false
        clearHint()
    }

    /// Runs `action` with a solution for the current cube, computing it off
    /// the main thread when needed.
    private func withSolution(_ action: @escaping ([Turn]) -> Void) {
        session.scene.finishDragImmediately()
        let state = session.state
        if let solution, solutionState == state {
            action(solution)
            return
        }
        computeTask?.cancel()
        isComputing = true
        let method = self.method
        computeTask = Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<([Turn], [SolveStep]?), CubeValidationError> in
                do {
                    switch method {
                    case .optimal:
                        return .success((try TwoPhaseSolver.solve(state), nil))
                    case .beginner:
                        let steps = try BeginnerSolver.solve(state)
                        return .success((steps.flatMap(\.turns), steps))
                    }
                } catch let error as CubeValidationError {
                    return .failure(error)
                } catch {
                    return .failure(.invalidCorner)
                }
            }.value
            guard let self, !Task.isCancelled, self.session.state == state else { return }
            self.isComputing = false
            switch outcome {
            case .success(let (turns, steps)):
                self.solution = turns
                self.steps = steps
                self.solutionState = state
                action(turns)
            case .failure(let error):
                self.error = error
                self.app?.play(.wrong)
            }
        }
    }
}
