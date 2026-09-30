import Foundation

/// Every piece of text in the app, in Portuguese (PT-PT) and English.
///
/// The language is chosen inside the app, independently of the system, so
/// the strings live in code and switch instantly. Split into small tables
/// by screen to keep type-checking quick.
enum Strings {

    typealias Pair = (pt: String, en: String)

    static let all: [String: Pair] = {
        var table: [String: Pair] = [:]
        let groups: [[String: Pair]] = [
            common, splash, home, settings, play, assist, stages, scanner, stats, learn,
            lessons, lessonSteps, achievements, notation, a11y,
        ]
        for group in groups {
            table.merge(group) { _, new in new }
        }
        return table
    }()

    static func t(_ key: String, _ language: AppLanguage) -> String {
        guard let pair = all[key] else { return key }
        return language == .pt ? pair.pt : pair.en
    }

    static let common: [String: Pair] = [
        "common.ok": ("OK", "OK"),
        "common.close": ("Fechar", "Close"),
        "common.cancel": ("Cancelar", "Cancel"),
        "common.done": ("Concluído", "Done"),
        "common.continue": ("Continuar", "Continue"),
        "common.back": ("Voltar", "Back"),
        "common.next": ("Seguinte", "Next"),
        "common.reset": ("Repor", "Reset"),
        "common.undo": ("Desfazer", "Undo"),
        "common.redo": ("Refazer", "Redo"),
        "common.delete": ("Apagar", "Delete"),
        "common.moves": ("Movimentos", "Moves"),
        "common.movesCount": ("%d movimentos", "%d moves"),
        "common.time": ("Tempo", "Time"),
        "common.none": ("–", "–"),
        "common.size": ("%d×%d", "%d×%d"),
    ]

    static let splash: [String: Pair] = [
        "splash.tagline": ("O cubo mágico, reinventado", "The classic cube, reimagined"),
        "about.developedBy": ("Developed by David Arsénio Martins", "Developed by David Arsénio Martins"),
        "about.body": ("O Cubo de Rubik clássico em 3D para iPhone e iPad: joga contra o relógio, pede ajuda quando precisares e aprende a resolvê-lo passo a passo.",
                       "The classic Rubik's Cube in 3D for iPhone and iPad: race the clock, ask for help whenever you need it and learn to solve it step by step."),
        "about.version": ("Versão %@", "Version %@"),
        "about.website": ("Website", "Website"),
        "about.github": ("GitHub", "GitHub"),
    ]
}
