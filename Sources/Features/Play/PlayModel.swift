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
        var dailyDate: Date?
        var isNewBest: Bool { previousBest.map { time < $0 } ?? true }
    }

    let session: CubeSession
    let isDaily: Bool
    private(set) var phase: Phase = .idle
    private(set) var scramble: [Turn] = []
    private(set) var moves = 0
    private(set) var inspectionEnd: ContinuousClock.Instant?
    private var timerStart: ContinuousClock.Instant?
    private(set) var accumulated: TimeInterval = 0
    var result: Result?
    private(set) var confetti = 0

    /// Asked for the best time of a size when a solve ends.
    @ObservationIgnored var bestTime: ((Int) -> TimeInterval?)?
    /// Called once per finished solve, to store it.
    @ObservationIgnored var onSolved: ((Result, [Turn], [Turn]) -> Void)?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var roundID = UUID()
    @ObservationIgnored private var scrambleDate: Date?
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var resultTask: Task<Void, Never>?

    init(model: AppModel, size: Int = 3, isDaily: Bool = false,
         now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
        self.model = model
        self.isDaily = isDaily
        session = CubeSession(size: isDaily ? 3 : size, model: model)
        session.onMove = { [weak self] turn, source in self?.moved(turn, source: source) }
    }

    var size: Int { session.size }

    func elapsed() -> TimeInterval {
        guard let timerStart else { return accumulated }
        let duration = timerStart.duration(to: now()).components
        return accumulated + Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    var inspectionEnabled: Bool { model?.settings.inspection ?? false }

    // MARK: Actions

    func changeSize(_ newSize: Int) {
        guard [2, 3, 4].contains(newSize), newSize != size, !isDaily else { return }
        stopClock()
        scramble = []
        scrambleDate = nil
        session.load(CubeState(size: newSize))
        session.scene.resetView()
    }

    func newScramble(on date: Date = .now) {
        stopClock()
        scrambleDate = date
        let turns = isDaily ? Scrambler.daily(for: date) : Scrambler.scramble(size: size)
        scramble = turns
        session.load(CubeState(size: size))
        phase = .scrambling
        session.scene.interaction = .orbitOnly
        model?.play(.whoosh)
        session.animateSetup(turns)
        session.scene.whenIdle { [weak self] in self?.scrambleFinished() }
    }

    private func scrambleFinished() {
        guard phase == .scrambling else { return }
        phase = .waiting
        session.scene.interaction = .full
        guard inspectionEnabled else { return }
        let end = now().advanced(by: .seconds(15))
        inspectionEnd = end
        inspectionTask = Task { @MainActor [weak self] in
            try? await ContinuousClock().sleep(until: end)
            guard !Task.isCancelled, let self, self.phase == .waiting else { return }
            self.refreshInspection()
        }
    }

    /// Starts the same scramble again from the beginning.
    func restart() {
        guard !scramble.isEmpty else { return }
        stopClock()
        session.load(CubeState(size: size).applying(scramble))
        phase = .scrambling
        scrambleFinished()
    }

    func togglePause() {
        switch phase {
        case .solving:
            session.scene.finishDragImmediately()
            guard phase == .solving else { return }
            accumulated = elapsed()
            timerStart = nil
            phase = .paused
            session.scene.interaction = .none
        case .paused:
            timerStart = now()
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
        refreshInspection()
        let isRotation = turn.isWholeCube(size: size)
        switch phase {
        case .waiting where !isRotation && source != .program:
            startClock()
            count()
            if session.state.isSolved { finish() }
        case .solving:
            count()
            if session.state.isSolved { finish() }
        default:
            break
        }
    }

    private func count() {
        moves = session.history.filter { !$0.isWholeCube(size: size) }.count
    }

    /// Catch up after suspension, using the original deadline rather than wake-up time.
    func refreshInspection() {
        guard phase == .waiting, let inspectionEnd, now() >= inspectionEnd else { return }
        startClock()
    }

    private func startClock() {
        let instant = now()
        timerStart = min(instant, inspectionEnd ?? instant)
        inspectionTask?.cancel()
        inspectionEnd = nil
        accumulated = 0
        phase = .solving
    }

    private func stopClock() {
        roundID = UUID()
        resultTask?.cancel()
        result = nil
        phase = .idle
        moves = 0
        inspectionTask?.cancel()
        inspectionEnd = nil
        timerStart = nil
        accumulated = 0
        session.scene.interaction = .full
    }

    private func finish() {
        let time = elapsed()
        timerStart = nil
        accumulated = time
        phase = .solved
        let outcome = Result(time: time, moves: moves, previousBest: bestTime?(size), size: size, isDaily: isDaily, dailyDate: isDaily ? scrambleDate : nil)
        onSolved?(outcome, scramble, session.history)
        let id = roundID
        session.scene.whenIdle { [weak self] in
            guard let self, self.roundID == id, self.phase == .solved else { return }
            self.session.scene.celebrate()
            self.confetti += 1
            self.model?.play(.solved)
            self.model?.feel(.solved)
            self.resultTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled, let self, self.roundID == id, self.phase == .solved else { return }
                self.result = outcome
            }
        }
    }
}
