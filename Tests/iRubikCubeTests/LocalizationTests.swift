import CubeCore
import Testing
@testable import iRubikCube

@Suite("Localization")
struct LocalizationTests {

    /// Keys that are allowed to be empty in both languages.
    private let intentionallyEmpty: Set<String> = ["practice.goal.anatomy", "practice.goal.notation"]

    @Test("Every string has both languages")
    func bothLanguages() {
        for (key, pair) in Strings.all where !intentionallyEmpty.contains(key) {
            #expect(!pair.pt.isEmpty, "Missing PT for \(key)")
            #expect(!pair.en.isEmpty, "Missing EN for \(key)")
        }
    }

    @Test("Format specifiers match between languages")
    func formatSpecifiers() throws {
        let regex = try Regex("%[0-9$]*[@dfs]")
        for (key, pair) in Strings.all {
            let pt = pair.pt.matches(of: regex).map { String(pair.pt[$0.range]) }.sorted()
            let en = pair.en.matches(of: regex).map { String(pair.en[$0.range]) }.sorted()
            #expect(pt == en, "Specifiers differ for \(key)")
        }
    }

    @Test("Portuguese copy avoids Brazilian forms")
    func europeanPortuguese() {
        let brazilian = [" você", "Você", " pra ", "tela", "arquivo", "usuário", "celular", "time "]
        for (key, pair) in Strings.all {
            for word in brazilian {
                #expect(!pair.pt.contains(word), "\(key) uses \(word)")
            }
        }
    }

    @Test("Keys built at runtime all exist")
    func dynamicKeys() {
        var keys: [String] = []
        keys += BeginnerStage.allCases.flatMap { ["stage.\($0.rawValue).title", "stage.\($0.rawValue).goal"] }
        keys += LessonID.allCases.flatMap { lesson in
            ["title", "subtitle", "why", "how"].map { "lesson.\(lesson.rawValue).\($0)" }
        }
        keys += LessonID.allCases.filter(\.hasPractice).map { "practice.goal.\($0.rawValue)" }
        keys += LessonID.Section.allCases.map { "learn.section.\($0.rawValue)" }
        keys += Achievement.allCases.flatMap { ["achievement.\($0.rawValue).title", "achievement.\($0.rawValue).detail"] }
        keys += (Algorithms.all + Algorithms.cornerTriggers + [Algorithms.ollLine]).map { "algorithm.\($0.id)" }
        keys += CubeColor.allCases.map { "color.\($0)" }
        keys += Face.allCases.map { "face.\($0.letter)" }
        keys += ["R", "L", "U", "D", "F", "B", "M", "E", "S", "x", "y", "z", "Rw", "Uw", "Fw"].map { "notation.name.\($0)" }
        keys += Appearance.allCases.map { "settings.appearance.\($0.rawValue)" }
        keys += AnimationSpeed.allCases.map { "settings.speed.\($0.rawValue)" }
        keys += AssistModel.Speed.allCases.map { "assist.speed.\($0)" }
        keys += AssistModel.Method.allCases.map { "assist.method.\($0.rawValue)" }
        keys += LessonModel.Tab.allCases.map { "lesson.tab.\($0.rawValue)" }
        keys += LessonModel.Anatomy.allCases.flatMap { ["anatomy.\($0.rawValue)", "anatomy.\($0.rawValue).detail"] }
        let errors: [CubeValidationError] = [.wrongColorCount(.white), .duplicateCenters, .invalidCorner, .invalidEdge,
                                             .duplicateCorner, .duplicateEdge, .twistedCorner, .flippedEdge, .parity]
        keys += errors.map(\.messageKey)
        for key in keys {
            #expect(Strings.all[key] != nil, "Missing key \(key)")
        }
    }

    @Test("Credits are exactly as requested")
    func credits() {
        #expect(Strings.t("about.developedBy", .pt) == "Developed by David Arsénio Martins")
        #expect(Strings.t("about.developedBy", .en) == "Developed by David Arsénio Martins")
        #expect(Links.website.absoluteString == "https://ividi.dev/")
        #expect(Links.github.absoluteString == "https://github.com/VidiPT89/")
    }

    @Test("Portuguese uses the Portugal locale")
    func locale() {
        #expect(AppLanguage.pt.locale.identifier == "pt_PT")
    }
}
