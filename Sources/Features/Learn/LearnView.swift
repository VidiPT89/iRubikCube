import CubeCore
import SwiftUI

/// The course: sections of lessons, overall progress and achievements.
struct LearnView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var appeared = false

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    progressHeader
                    ForEach(LessonID.Section.allCases, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: app.t("learn.section.\(section.rawValue)"))
                            let lessons = LessonID.allCases.filter { $0.section == section }
                            ForEach(Array(lessons.enumerated()), id: \.element) { index, lesson in
                                NavigationLink(value: Route.lesson(lesson)) {
                                    LessonRow(lesson: lesson, number: number(of: lesson))
                                }
                                .buttonStyle(.pressable)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04), value: appeared)
                            }
                        }
                    }
                    AchievementsGrid()
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(app.t("mode.learn"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { appeared = true }
    }

    private func number(of lesson: LessonID) -> Int {
        (LessonID.allCases.firstIndex(of: lesson) ?? 0) + 1
    }

    private var progressHeader: some View {
        let done = app.progress.completedLessons.count
        let total = LessonID.allCases.count
        return GlassCard {
            HStack(spacing: 18) {
                ProgressRing(progress: app.progress.lessonProgress, lineWidth: 9)
                    .frame(width: 74, height: 74)
                    .overlay(Text("\(Int((app.progress.lessonProgress * 100).rounded()))%").font(.rounded(17, .heavy)).foregroundStyle(palette.text))
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.t("learn.progress", done, total)).font(.rounded(17, .bold)).foregroundStyle(palette.text)
                    Text(app.t("learn.intro")).font(.rounded(14, .regular)).foregroundStyle(palette.textDim)
                    Label(app.t("learn.streak", app.progress.streak()), systemImage: "flame.fill")
                        .font(.rounded(13, .semibold)).foregroundStyle(palette.primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LessonRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let lesson: LessonID
    let number: Int

    var body: some View {
        let done = app.progress.completedLessons.contains(lesson)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(done ? AnyShapeStyle(palette.brandGradient) : AnyShapeStyle(palette.primary.opacity(0.12)))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(Color(hex: 0x0A0A0F))
                } else {
                    Image(systemName: LessonCatalog.icon(for: lesson)).font(.system(size: 18, weight: .bold)).foregroundStyle(palette.primary)
                }
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(app.t("lesson.\(lesson.rawValue).title"))")
                    .font(.rounded(16, .bold)).foregroundStyle(palette.text)
                Text(app.t("lesson.\(lesson.rawValue).subtitle"))
                    .font(.rounded(13, .regular)).foregroundStyle(palette.textDim).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textFaint)
        }
        .padding(14)
        .background(palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(done ? palette.primary.opacity(0.35) : palette.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(done ? app.t("learn.completed") : ""))
    }
}

enum LessonCatalog {
    static func icon(for lesson: LessonID) -> String {
        switch lesson {
        case .anatomy: "cube.transparent"
        case .notation: "character.textbox"
        case .whiteCross: "plus"
        case .whiteCorners: "square.bottomhalf.filled"
        case .middleEdges: "square.split.1x2"
        case .yellowCross: "plus.circle"
        case .yellowFace: "square.fill"
        case .yellowCorners: "arrow.triangle.swap"
        case .yellowEdges: "arrow.triangle.2.circlepath"
        case .f2l: "rectangle.stack.fill"
        case .oll: "sun.max.fill"
        case .pll: "shuffle"
        }
    }
}

/// Circular progress in the brand gradient.
struct ProgressRing: View {
    @Environment(\.palette) private var palette
    let progress: Double
    var lineWidth: CGFloat = 8
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(palette.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [palette.amber, palette.primary, palette.hot, palette.amber], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(response: 1, dampingFraction: 0.8).delay(0.15)) { shown = max(progress, 0.001) } }
        .onChange(of: progress) { _, value in withAnimation(.spring) { shown = max(value, 0.001) } }
    }
}

/// Badges, greyed out until earned.
struct AchievementsGrid: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: app.t("achievements.title")) {
                Text("\(app.progress.achievements.count)/\(Achievement.allCases.count)")
                    .font(.mono(12, .bold)).foregroundStyle(palette.primary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(Achievement.allCases) { achievement in
                    let earned = app.progress.achievements[achievement] != nil
                    VStack(spacing: 8) {
                        Image(systemName: achievement.systemImage)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(earned ? Color(hex: 0x0A0A0F) : palette.textFaint)
                            .frame(width: 48, height: 48)
                            .background {
                                if earned {
                                    Circle().fill(palette.brandGradient).shadow(color: palette.primary.opacity(0.5), radius: 8)
                                } else {
                                    Circle().fill(palette.surfaceRaised)
                                }
                            }
                        Text(app.t("achievement.\(achievement.rawValue).title"))
                            .font(.rounded(12, .bold)).foregroundStyle(earned ? palette.text : palette.textDim)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                        Text(app.t("achievement.\(achievement.rawValue).detail"))
                            .font(.rounded(10, .regular)).foregroundStyle(palette.textDim)
                            .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
                    .background(palette.surface.opacity(earned ? 0.85 : 0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(earned ? palette.primary.opacity(0.4) : palette.stroke))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(earned ? app.t("achievements.earned") : app.t("achievements.locked")))
                }
            }
        }
    }
}
