import CubeCore
import Foundation
import Observation

/// One lesson: demonstration, algorithms, guided practice and (for
/// notation) a quiz.
@Observable
@MainActor
final class LessonModel {

    enum Tab: String, CaseIterable, Identifiable {
        case why, how, practice
        var id: String { rawValue }
    }

    enum Feedback: Equatable {
        case none, correct, wrong(Turn), goal
    }

    enum Anatomy: String, CaseIterable, Identifiable {
        case centers, edges, corners
        var id: String { rawValue }
    }

    struct Quiz {
        var round = 0
        var score = 0
        var answer = ""
        var options: [String] = []
        var picked: String?
        static let rounds = 5
        var isOver: Bool { round >= Self.rounds }
    }

    let lesson: LessonID
    let session: CubeSession
    var tab: Tab = .why { didSet { if tab != oldValue { tabChanged() } } }
    private(set) var feedback: Feedback = .none
    private(set) var practising = false
    private(set) var expected: [Turn] = []
    private(set) var goalReached = false
    private(set) var confetti = 0
    /// Bumped on every right move, to flash the cube green.
    private(set) var correctMoves = 0
    private(set) var anatomy: Anatomy = .centers
    private(set) var demoToken: String?
    private(set) var playingAlgorithm: String?
    var quiz: Quiz?

    @ObservationIgnored private weak var app: AppModel?

    init(lesson: LessonID, app: AppModel) {
        self.lesson = lesson
        self.app = app
        session = CubeSession(size: 3, state: Self.demoState(for: lesson), model: app)
        session.onMove = { [weak self] turn, source in self?.moved(turn, source: source) }
        showDemo()
    }

    var isCompleted: Bool { app?.progress.completedLessons.contains(lesson) ?? false }

    /// Notation is shown in the usual white-up orientation; every other
    /// lesson holds white at the bottom, as the method is taught.
    static func demoState(for lesson: LessonID) -> CubeState {
        lesson.section == .basics ? CubeState() : CubeState().applying(.rotation(.x, 2))
    }

    // MARK: Demonstration

    private func tabChanged() {
        feedback = .none
        switch tab {
        case .why, .how:
            practising = false
            showDemo()
        case .practice:
            startPractice()
        }
    }

    func showDemo() {
        session.load(Self.demoState(for: lesson))
        session.scene.interaction = .orbitOnly
        session.scene.highlighted = highlight(for: lesson)
        playingAlgorithm = nil
    }

    func selectAnatomy(_ part: Anatomy) {
        anatomy = part
        session.scene.highlighted = Self.stickers(of: Self.pieces(for: part))
        app?.play(.tap)
    }

    /// Plays a notation letter on a solved cube.
    func demonstrate(_ token: String) {
        guard let turn = try? Notation.parseToken(token, size: 3) else { return }
        demoToken = token
        session.load(CubeState())
        session.scene.highlighted = nil
        session.scene.turnDuration = 0.55
        session.perform(turn, source: .program)
        session.scene.whenIdle { [weak self] in self?.session.applySettings() }
    }

    /// Shows the case an algorithm solves, then solves it slowly.
    func watch(_ algorithm: Algorithm) {
        let start = Self.demoState(for: lesson).applying(LessonCoach.inverse(of: algorithm.turns))
        session.load(start)
        session.scene.highlighted = nil
        playingAlgorithm = algorithm.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard let self, self.playingAlgorithm == algorithm.id else { return }
            self.session.scene.turnDuration = 0.6
            self.session.perform(algorithm.turns, source: .program)
            self.session.scene.whenIdle { [weak self] in
                self?.session.applySettings()
                self?.playingAlgorithm = nil
            }
        }
    }

    private func highlight(for lesson: LessonID) -> Set<Int>? {
        let solver = BeginnerSolver.self
        let pieces: [[Face]]
        switch lesson {
        case .anatomy: return Self.stickers(of: Self.pieces(for: anatomy))
        case .notation: return nil
        case .whiteCross: pieces = solver.crossEdges
        case .whiteCorners: pieces = solver.bottomCorners
        case .middleEdges: pieces = solver.middleEdges
        case .yellowCross, .yellowEdges: pieces = solver.topEdges
        case .yellowFace, .oll, .pll: pieces = solver.topEdges + solver.topCorners + [[.U]]
        case .yellowCorners: pieces = solver.topCorners
        case .f2l: pieces = solver.bottomCorners + solver.middleEdges
        }
        return Self.stickers(of: pieces)
    }

    static func pieces(for part: Anatomy) -> [[Face]] {
        let sides: [Face] = [.F, .R, .B, .L]
        switch part {
        case .centers: return Face.allCases.map { [$0] }
        case .edges:
            var list: [[Face]] = []
            for i in 0..<4 {
                let side = sides[i]
                let next = sides[(i + 1) % 4]
                list.append([.U, side])
                list.append([.D, side])
                list.append([side, next])
            }
            return list
        case .corners:
            var list: [[Face]] = []
            for i in 0..<4 {
                let side = sides[i]
                let next = sides[(i + 1) % 4]
                list.append([.U, side, next])
                list.append([.D, side, next])
            }
            return list
        }
    }

    static func stickers(of pieces: [[Face]]) -> Set<Int> {
        let cube = CubeState()
        return Set(pieces.flatMap { piece in piece.map { cube.stickerIndex(of: piece, on: $0) } })
    }

    // MARK: Practice

    func startPractice() {
        guard let start = LessonCoach.practiceCase(for: lesson) else { return }
        session.load(start)
        session.scene.highlighted = nil
        session.scene.interaction = .full
        practising = true
        goalReached = false
        feedback = .none
        refreshExpected()
    }

    func showHint() {
        guard let next = expected.first else { return }
        session.scene.showHint(next)
        app?.play(.tap)
    }

    func undoLast() {
        session.undo()
        feedback = .none
    }

    private func moved(_ turn: Turn, source: CubeSession.Source) {
        guard practising else { return }
        session.scene.hideHint()
        if source == .undo {
            refreshExpected()
            return
        }
        let wasExpected = expected.first.map { matches(turn, $0) } ?? false
        refreshExpected()
        if LessonCoach.isGoalReached(lesson, in: session.state) {
            reachGoal()
        } else if wasExpected {
            feedback = .correct
            correctMoves += 1
            app?.play(.correct)
        } else {
            feedback = .wrong(turn)
            app?.play(.wrong)
            app?.feel(.warning)
        }
    }

    /// A quarter of a suggested half turn also counts as progress.
    private func matches(_ turn: Turn, _ expected: Turn) -> Bool {
        turn.isEquivalent(to: expected)
            || (expected.isHalfTurn && turn.axis == expected.axis && turn.layers == expected.layers)
    }

    private func refreshExpected() {
        expected = LessonCoach.suggestion(for: lesson, from: session.state)
    }

    private func reachGoal() {
        goalReached = true
        feedback = .goal
        session.scene.whenIdle { [weak self] in
            guard let self else { return }
            self.session.scene.celebrate()
            self.confetti += 1
            self.app?.play(.solved)
            self.app?.feel(.solved)
            self.complete()
        }
    }

    func complete() {
        guard let app, !isCompleted else { return }
        app.announce(app.progress.completeLesson(lesson))
    }

    // MARK: Notation quiz

    static let quizTokens = ["R", "R'", "L", "L'", "U", "U'", "D", "D'", "F", "F'", "B", "B'", "R2", "U2", "F2", "M", "x", "y"]

    func startQuiz() {
        quiz = Quiz()
        nextQuestion()
    }

    private func nextQuestion() {
        guard var current = quiz, !current.isOver else { return }
        let answer = Self.quizTokens.randomElement() ?? "R"
        var options: Set<String> = [answer]
        // A distractor on the same face makes it about direction, not just letters.
        let base = String(answer.prefix(1))
        if let sameFace = Self.quizTokens.filter({ $0.hasPrefix(base) && $0 != answer }).randomElement() {
            options.insert(sameFace)
        }
        while options.count < 4, let other = Self.quizTokens.randomElement() { options.insert(other) }
        current.answer = answer
        current.options = options.shuffled()
        current.picked = nil
        quiz = current
        replayQuestion()
    }

    func replayQuestion() {
        guard let answer = quiz?.answer, let turn = try? Notation.parseToken(answer, size: 3) else { return }
        session.load(CubeState())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard let self else { return }
            self.session.scene.turnDuration = 0.7
            self.session.perform(turn, source: .program)
            self.session.scene.whenIdle { [weak self] in self?.session.applySettings() }
        }
    }

    func answer(_ option: String) {
        guard var current = quiz, current.picked == nil else { return }
        current.picked = option
        if option == current.answer {
            current.score += 1
            app?.play(.correct)
        } else {
            app?.play(.wrong)
        }
        quiz = current
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, var latest = self.quiz else { return }
            latest.round += 1
            self.quiz = latest
            if latest.isOver {
                if latest.score >= 4 { self.complete() }
            } else {
                self.nextQuestion()
            }
        }
    }
}
