import CubeCore
import Foundation
import Testing
@testable import iRubikCube

@MainActor
@Suite("App logic", .serialized)
struct AppLogicTests {

    private func freshDefaults() -> UserDefaults {
        let name = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Gestures

    /// Drags across the cube as a finger would and returns the committed turn.
    private func drag(on scene: CubeScene, from start: SIMD3<Float>, to end: SIMD3<Float>) -> Turn? {
        var committed: Turn?
        scene.onUserTurn = { committed = $0 }
        guard let a = scene.project(start), let b = scene.project(end) else { return nil }
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        scene.dragChanged(start: a, location: middle)
        scene.dragChanged(start: a, location: b)
        scene.dragEnded(start: a, location: b, predicted: b)
        for _ in 0..<240 where committed == nil { scene.tick(1.0 / 60) }
        return committed
    }

    @Test("Dragging the top row of the front face to the right turns U′")
    func dragTopRowRight() {
        let scene = CubeScene(size: 3)
        scene.viewSize = CGSize(width: 390, height: 500)
        let turn = drag(on: scene, from: [-0.2, 1.0 / 3, 0.5], to: [0.35, 1.0 / 3, 0.5])
        #expect(turn == .face(.U, -1))
        #expect(scene.displayed == CubeState().applying(.face(.U, -1)))
    }

    @Test("Dragging the right column of the front face upwards turns R")
    func dragRightColumnUp() {
        let scene = CubeScene(size: 3)
        scene.viewSize = CGSize(width: 390, height: 500)
        let turn = drag(on: scene, from: [1.0 / 3, -0.25, 0.5], to: [1.0 / 3, 0.35, 0.5])
        #expect(turn == .face(.R))
    }

    @Test("Dragging the middle layer of a 4×4 turns an inner slice")
    func dragInnerLayer() {
        let scene = CubeScene(size: 4)
        scene.viewSize = CGSize(width: 390, height: 500)
        let turn = drag(on: scene, from: [0.125, -0.25, 0.5], to: [0.125, 0.35, 0.5])
        #expect(turn == Turn(axis: .x, layers: .single(2), quarters: -1))
    }

    @Test("A drag that starts off the cube only orbits the view")
    func orbitOffCube() {
        let scene = CubeScene(size: 3)
        scene.viewSize = CGSize(width: 390, height: 500)
        let yaw = scene.yaw
        scene.dragChanged(start: CGPoint(x: 10, y: 20), location: CGPoint(x: 80, y: 20))
        scene.dragEnded(start: CGPoint(x: 10, y: 20), location: CGPoint(x: 80, y: 20), predicted: CGPoint(x: 80, y: 20))
        #expect(scene.yaw != yaw)
        #expect(scene.displayed.isSolved)
    }

    @Test("Queued turns catch up with the logical cube")
    func animationQueue() {
        let scene = CubeScene(size: 3)
        let turns = Scrambler.scramble(size: 3)
        scene.enqueue(turns)
        #expect(scene.isAnimating)
        for _ in 0..<2000 where scene.isAnimating { scene.tick(1.0 / 30) }
        #expect(!scene.isAnimating)
        #expect(scene.displayed == CubeState().applying(turns))
    }

    // MARK: Play

    @Test("A full solve: scramble, first move starts the clock, solving stops it")
    func playFlow() {
        let app = AppModel(defaults: freshDefaults())
        let model = PlayModel(model: app)
        var solved: PlayModel.Result?
        model.onSolved = { result, _, _ in solved = result }
        model.newScramble()
        #expect(model.phase == .scrambling)
        model.session.scene.finishAnimations()
        #expect(model.phase == .waiting)
        let solution = model.scramble.reversed().map(\.inverse)
        model.session.perform(solution[0])
        #expect(model.phase == .solving)
        model.session.perform(Array(solution.dropFirst()), source: .user)
        #expect(model.phase == .solved)
        #expect(solved?.moves == model.scramble.count)
        #expect(solved?.isNewBest == true)
    }

    @Test("Undo during a solve takes a move off the counter")
    func undoCounts() {
        let app = AppModel(defaults: freshDefaults())
        let model = PlayModel(model: app)
        model.newScramble()
        model.session.scene.finishAnimations()
        model.session.perform(.face(.R))
        model.session.perform(.face(.U))
        #expect(model.moves == 2)
        model.undo()
        #expect(model.moves == 1)
    }

    @Test("Restart puts the same scramble back and resets the clock")
    func restart() {
        let app = AppModel(defaults: freshDefaults())
        let model = PlayModel(model: app)
        model.newScramble()
        model.session.scene.finishAnimations()
        let scrambled = model.session.state
        model.session.perform(.face(.R))
        #expect(model.phase == .solving)
        model.restart()
        #expect(model.session.state == scrambled)
        #expect(model.phase == .waiting)
        #expect(model.moves == 0)
        #expect(model.elapsed(at: .now) == 0)
    }

    // MARK: Progress

    @Test("Achievements unlock once and a week of play makes a streak")
    func progress() {
        let store = ProgressStore(defaults: freshDefaults())
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        let first = store.recordSolve(time: 55, size: 3, isDaily: false, on: start)
        #expect(Set(first) == [.firstSolve, .underTwoMinutes, .underOneMinute])
        #expect(store.recordSolve(time: 50, size: 3, isDaily: false, on: start).isEmpty)
        var unlocked: [Achievement] = []
        for day in 1...6 {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            unlocked += store.completeLesson(.anatomy, on: date)
        }
        #expect(unlocked.contains(.weekStreak))
        #expect(store.streak(asOf: calendar.date(byAdding: .day, value: 6, to: start)!) == 7)
    }

    @Test("Progress from another device is merged, never lost")
    func merge() throws {
        let local = ProgressStore(defaults: freshDefaults())
        local.completeLesson(.notation)
        let remote = ProgressStore(defaults: freshDefaults())
        remote.completeLesson(.whiteCross)
        local.merge(try JSONEncoder().encode(remote.snapshot))
        #expect(local.completedLessons == [.notation, .whiteCross])
        #expect(local.achievements[.firstCross] != nil)
    }

    @Test("Settings survive a relaunch")
    func settingsPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.language = .pt
        settings.appearance = .dark
        settings.highContrast = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.language == .pt)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.cubeScheme == .highContrast)
    }

    // MARK: Scanner

    @Test("Scanned colours are calibrated against the six centres")
    func colourCalibration() {
        // A warm light: every colour is shifted towards orange.
        let tint: [CubeColor: RGB] = [
            .white: RGB(r: 0.95, g: 0.88, b: 0.75), .yellow: RGB(r: 0.95, g: 0.85, b: 0.2),
            .red: RGB(r: 0.8, g: 0.15, b: 0.1), .orange: RGB(r: 0.98, g: 0.5, b: 0.1),
            .blue: RGB(r: 0.1, g: 0.3, b: 0.7), .green: RGB(r: 0.15, g: 0.65, b: 0.3),
        ]
        let cube = CubeState().applying(Scrambler.scramble(size: 3))
        var faces: [Face: [RGB]] = [:]
        for face in Face.allCases {
            faces[face] = cube.stickers(of: face).map { tint[$0]! }
        }
        let result = ColorClassifier.classify(faces: faces)
        for face in Face.allCases {
            #expect(result[face] == Array(cube.stickers(of: face)), "\(face)")
        }
    }
}
