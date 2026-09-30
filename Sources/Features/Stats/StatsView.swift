import Charts
import CubeCore
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Query(sort: \SolveRecord.date, order: .reverse) private var records: [SolveRecord]
    @State private var size = 3
    @State private var expanded: SolveRecord.ID?

    private var filtered: [SolveRecord] { records.filter { $0.size == size } }
    /// Oldest first, as averages are computed over the latest solves.
    private var times: [TimeInterval] { filtered.reversed().map(\.duration) }

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SizePicker(size: $size).frame(maxWidth: .infinity)
                    tiles
                    chart
                    history
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(app.t("stats.title"))
        .navigationBarTitleDisplayMode(.large)
    }

    private var tiles: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StatTile(value: Statistics.best(in: times)?.cubeTime ?? app.t("common.none"),
                             caption: app.t("stats.best"), systemImage: "trophy.fill")
                    StatTile(value: Statistics.average(of: 5, in: times)?.cubeTime ?? app.t("common.none"),
                             caption: "Ao5", systemImage: "chart.line.uptrend.xyaxis")
                    StatTile(value: Statistics.average(of: 12, in: times)?.cubeTime ?? app.t("common.none"),
                             caption: "Ao12", systemImage: "chart.bar.fill")
                }
                HStack(spacing: 12) {
                    StatTile(value: "\(filtered.count)", caption: app.t("stats.solves"), systemImage: "cube.fill")
                    StatTile(value: Statistics.mean(of: times)?.cubeTime ?? app.t("common.none"),
                             caption: app.t("stats.mean"), systemImage: "equal.circle.fill")
                    StatTile(value: filtered.isEmpty ? app.t("common.none")
                             : "\(filtered.map(\.moveCount).reduce(0, +) / filtered.count)",
                             caption: app.t("stats.avgMoves"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let recent = Array(filtered.prefix(40).reversed())
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: app.t("stats.history"))
            if recent.count < 2 {
                empty(app.t("stats.chartEmpty"))
            } else {
                Chart {
                    ForEach(Array(recent.enumerated()), id: \.offset) { index, record in
                        AreaMark(x: .value("#", index + 1), y: .value(app.t("common.time"), record.duration))
                            .foregroundStyle(LinearGradient(colors: [palette.primary.opacity(0.35), .clear],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("#", index + 1), y: .value(app.t("common.time"), record.duration))
                            .foregroundStyle(palette.brandGradient)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("#", index + 1), y: .value(app.t("common.time"), record.duration))
                            .foregroundStyle(palette.amber)
                            .symbolSize(24)
                    }
                    if let best = Statistics.best(in: recent.map(\.duration)) {
                        RuleMark(y: .value(app.t("stats.best"), best))
                            .foregroundStyle(palette.success.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(palette.stroke)
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text(seconds.cubeTime).font(.mono(10, .medium)) }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 200)
                .padding(14)
                .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel(Text(app.t("stats.chartLabel")))
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: app.t("stats.solutions"))
            if filtered.isEmpty {
                empty(app.t("stats.empty"))
            }
            ForEach(filtered) { record in
                SolveRow(record: record, expanded: expanded == record.id) {
                    withAnimation(.spring(response: 0.35)) { expanded = expanded == record.id ? nil : record.id }
                } onDelete: {
                    withAnimation {
                        context.delete(record)
                        try? context.save()
                    }
                }
            }
        }
    }

    private func empty(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "timer").foregroundStyle(palette.primary)
            Text(text).font(.rounded(14, .medium)).foregroundStyle(palette.textDim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SolveRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    let record: SolveRecord
    let expanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(record.duration.cubeTime).font(.mono(18, .bold)).foregroundStyle(palette.text)
                    if record.isDaily {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.primary)
                    }
                    Spacer()
                    Text(app.t("common.movesCount", record.moveCount)).font(.rounded(13, .medium)).foregroundStyle(palette.textDim)
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.rounded(12, .regular)).foregroundStyle(palette.textFaint)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textFaint).rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.t("stats.scramble")).font(.rounded(11, .heavy)).foregroundStyle(palette.textDim)
                    Text(record.scramble).font(.mono(12, .medium)).foregroundStyle(palette.text).textSelection(.enabled)
                    Text(app.t("stats.solution")).font(.rounded(11, .heavy)).foregroundStyle(palette.textDim)
                    Text(record.solution.isEmpty ? app.t("common.none") : record.solution)
                        .font(.mono(12, .medium)).foregroundStyle(palette.text).textSelection(.enabled)
                    Button(role: .destructive, action: onDelete) {
                        Label(app.t("common.delete"), systemImage: "trash").font(.rounded(13, .semibold))
                    }
                    .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.stroke))
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label(app.t("common.delete"), systemImage: "trash") }
        }
    }
}
