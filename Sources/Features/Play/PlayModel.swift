import CubeCore
import Foundation
import Observation

/// Speedcubing session: scramble, optional inspection, timer and result.
@Observable
@MainActor
final class PlayModel {

    enum Phase: Equatable {
        /// Solved cube, nothing scrambled yet.
        case idle
        case scrambling
        /// Scrambled; the timer starts on the first turn (or when inspection ends).
        case waiting
        case solving
        case paused
        case solved
    }

    struct Result: Identifiable {
        let id = UUID()
        var time: TimeInterval
        var moves: Int
        var previousBest: TimeInterval?
        var size: Int
        var isDaily: Bool
        var isNewBest: Bool { previousBest.map { time < $0 } ?? true }
    }

    let session: CubeSession
    let isDaily: Bool
    private(set) var phase: Phase = .idle
    private(set) var scramble: [Turn] = []
    private(set) var moves = 0
    private(set) var inspectionEnd: Date?
    private(set) var timerStart: Date?
    private(set) var accumulated: TimeInterval = 0
    var result: Result?
    private(set) var confetti = 0

    /// Asked for the best time of a size when a solve ends.
    @ObservationIgnored var bestTime: ((Int) -> TimeInterval?)?
    /// Called once per finished solve, to store it.
    @ObservationIgnored var onSolved: ((Result, [Turn], [Turn]) -> Void)?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var solveTurns: [Turn] = []

    init(model: AppModel, size: Int = 3, isDaily: Bool = false) {
        self.model = model
        self.isDaily = isDaily
        session = CubeSession(size: isDaily ? 3 : size, model: model)
        session.onMove = { [weak self] turn, source in self?.moved(turn, source: source) }
    }

    var size: Int { session.size }

    func elapsed(at date: Date) -> TimeInterval {
        guard let timerStart else { return accumulated }
        return accumulated + date.timeIntervalSince(timerStart)
    }

    var inspectionEnabled: Bool { model?.settings.inspection ?? false }

    // MARK: Actions

    func changeSize(_ newSize: Int) {
        guard newSize != size, !isDaily else { return }
        stopClock()
        phase = .idle
        scramble = []
        session.load(CubeState(size: newSize))
        session.scene.resetView()
    }

    func newScramble() {
        stopClock()
        let turns = isDaily ? Scrambler.daily(for: .now) : Scrambler.scramble(size: size)
        scramble = turns
        moves = 0
        solveTurns = []
        result = nil
        session.load(CubeState(size: size))
        phase = .scrambling
        model?.play(.whoosh)
        session.animateSetup(turns)
        session.scene.whenIdle { [weak self] in self?.scrambleFinished() }
    }

    private func scrambleFinished() {
        guard phase == .scrambling else { return }
        phase = .waiting
        guard inspectionEnabled else { return }
        let end = Date.now.addingTimeInterval(15)
        inspectionEnd = end
        inspectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.phase == .waiting else { return }
            self.startClock()
        }
    }

    /// Starts the same scramble again from the beginning.
    func restart() {
        guard !scramble.isEmpty else { return }
        stopClock()
        moves = 0
        solveTurns = []
        result = nil
        session.load(CubeState(size: size).applying(scramble))
        phase = .scrambling
        scrambleFinished()
    }

    func togglePause() {
        switch phase {
        case .solving:
            accumulated = elapsed(at: .now)
            timerStart = nil
            phase = .paused
            session.scene.interaction = .none
        case .paused:
            timerStart = .now
            phase = .solving
            session.scene.interaction = .full
        default:
            break
        }
    }

    func undo() {
        guard phase == .solving || phase == .waiting else { return }
        session.undo()
    }

    func redo() {
        guard phase == .solving || phase == .waiting else { return }
        session.redo()
    }

    // MARK: Moves and clock

    private func moved(_ turn: Turn, source: CubeSession.Source) {
        let isRotation = turn.isWholeCube(size: size)
        switch phase {
        case .waiting where !isRotation && source != .program:
            startClock()
            count(turn, source: source)
        case .solving:
            count(turn, source: source)
            if session.state.isSolved { finish() }
        default:
            break
        }
    }

    private func count(_ turn: Turn, source: CubeSession.Source) {
        guard !turn.isWholeCube(size: size) else { return }
        if source == .undo {
            moves = max(0, moves - 1)
            _ = solveTurns.popLast()
        } else {
            moves += 1
            solveTurns.append(turn)
        }
    }

    private func startClock() {
        inspectionTask?.cancel()
        inspectionEnd = nil
        timerStart = .now
        accumulated = 0
        phase = .solving
    }

    private func stopClock() {
        inspectionTask?.cancel()
        inspectionEnd = nil
        timerStart = nil
        accumulated = 0
        session.scene.interaction = .full
    }

    private func finish() {
        let time = elapsed(at: .now)
        timerStart = nil
        accumulated = time
        phase = .solved
        let outcome = Result(time: time, moves: moves, previousBest: bestTime?(size), size: size, isDaily: isDaily)
        onSolved?(outcome, scramble, solveTurns)
        session.scene.whenIdle { [weak self] in
            guard let self else { return }
            self.session.scene.celebrate()
            self.confetti += 1
            self.model?.play(.solved)
            self.model?.feel(.solved)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.4))
                self?.result = outcome
            }
        }
    }
}
