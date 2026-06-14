import Charts
import SwiftData
import SwiftUI

struct SummariesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]

    /// 近 14 天，按时间正序，用于趋势图。
    private var trendSummaries: [DailySummary] {
        Array(summaries.prefix(14)).reversed()
    }

    var body: some View {
        NavigationStack {
            Group {
                if summaries.isEmpty {
                    ContentUnavailableView {
                        Label("还没有每日总结", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("在「今日」页同步并生成今日建议后，这里会留下每天的热量复盘和明日建议。")
                    }
                } else {
                    List {
                        if trendSummaries.count >= 2 {
                            Section("趋势") {
                                TrendChartsView(summaries: trendSummaries)
                                    .padding(.vertical, 4)
                            }
                        }
                        Section("每日记录") {
                            ForEach(summaries) { summary in
                                NavigationLink {
                                    SummaryDetailView(summary: summary)
                                } label: {
                                    SummaryRow(summary: summary)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(summary)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("总结")
        }
    }

    private func delete(_ summary: DailySummary) {
        modelContext.delete(summary)
        try? modelContext.save()
    }
}

/// 是否达到当日目标缺口。
private func deficitReached(_ summary: DailySummary) -> Bool {
    let target = summary.snapshot?.targetDailyDeficitKcal ?? 0
    return target > 0 && summary.calorieDeficit >= target
}

private let trendDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M/d"
    return formatter
}()

/// 多指标趋势图：缺口 / 摄入消耗 / 体重 / 营养素，用分段控件切换（基于 Swift Charts）。
private struct TrendChartsView: View {
    let summaries: [DailySummary]   // 时间正序

    @State private var metric: Metric = .deficit

    enum Metric: String, CaseIterable, Identifiable {
        case deficit = "缺口"
        case energy = "摄入/消耗"
        case weight = "体重"
        case macros = "营养素"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("指标", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            chart
                .frame(height: 200)
                .animation(.default, value: metric)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .deficit:
            Chart(summaries) { summary in
                BarMark(
                    x: .value("日期", summary.date, unit: .day),
                    y: .value("缺口", summary.calorieDeficit)
                )
                .foregroundStyle(deficitReached(summary) ? Color.deficitReached : Color.deficitShort)
            }
            .chartXAxis { dateAxis }

        case .energy:
            Chart {
                ForEach(summaries) { summary in
                    LineMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("kcal", summary.intakeCalories)
                    )
                    .foregroundStyle(by: .value("类型", "摄入"))
                    .symbol(by: .value("类型", "摄入"))
                }
                ForEach(summaries) { summary in
                    LineMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("kcal", summary.totalBurnCalories)
                    )
                    .foregroundStyle(by: .value("类型", "消耗"))
                    .symbol(by: .value("类型", "消耗"))
                }
            }
            .chartXAxis { dateAxis }

        case .weight:
            let points = summaries.filter { $0.weightKg > 0 }
            if points.count < 2 {
                ContentUnavailableView(
                    "体重数据不足",
                    systemImage: "scalemass",
                    description: Text("生成几天建议、且健康里有体重记录后，这里会显示体重趋势。")
                )
            } else {
                Chart(points) { summary in
                    LineMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("kg", summary.weightKg)
                    )
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("kg", summary.weightKg)
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { dateAxis }
            }

        case .macros:
            Chart {
                ForEach(summaries) { summary in
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.proteinGrams)
                    )
                    .foregroundStyle(by: .value("营养", "蛋白质"))
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.carbsGrams)
                    )
                    .foregroundStyle(by: .value("营养", "碳水"))
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.fatGrams)
                    )
                    .foregroundStyle(by: .value("营养", "脂肪"))
                }
            }
            .chartXAxis { dateAxis }
        }
    }

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: min(summaries.count, 7))) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(trendDayFormatter.string(from: date))
                }
            }
        }
    }
}

/// 总结列表行：日期 + 缺口（着色）+ 摄入/消耗 + 建议预览。
private struct SummaryRow: View {
    let summary: DailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DateFormatter.csvDate.string(from: summary.date))
                    .font(.headline)
                Spacer()
                Text(summary.calorieDeficit.signedKcalText)
                    .font(.headline)
                    .foregroundStyle(deficitReached(summary) ? Color.deficitReached : Color.deficitShort)
            }
            HStack(spacing: 14) {
                Label(summary.intakeCalories.kcalText, systemImage: "fork.knife")
                Label(summary.totalBurnCalories.kcalText, systemImage: "flame")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !summary.adviceText.isEmpty {
                Text(summary.adviceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 单日总结详情：完整热量明细 + 营养素/体重 + 当日饮食/运动清单 + AI 建议全文。
struct SummaryDetailView: View {
    let summary: DailySummary

    var body: some View {
        List {
            Section("热量") {
                LabeledContent("摄入", value: summary.intakeCalories.kcalText)
                LabeledContent("活动消耗", value: summary.activeCalories.kcalText)
                LabeledContent("基础代谢", value: summary.restingCalories.kcalText)
                LabeledContent("总消耗", value: summary.totalBurnCalories.kcalText)
                LabeledContent("热量差", value: summary.calorieDeficit.signedKcalText)
                if let target = summary.snapshot?.targetDailyDeficitKcal, target > 0 {
                    LabeledContent("目标缺口", value: "\(Int(target)) kcal")
                }
            }

            Section("营养素与体重") {
                LabeledContent("蛋白质", value: "\(Int(summary.proteinGrams)) g")
                LabeledContent("碳水", value: "\(Int(summary.carbsGrams)) g")
                LabeledContent("脂肪", value: "\(Int(summary.fatGrams)) g")
                LabeledContent("体重", value: summary.weightKg > 0 ? String(format: "%.1f kg", summary.weightKg) : "—")
            }

            if let meals = summary.snapshot?.meals, !meals.isEmpty {
                Section("当日饮食") {
                    ForEach(meals, id: \.self) { meal in
                        Text(meal)
                            .font(.subheadline)
                    }
                }
            }

            if let workouts = summary.snapshot?.workouts, !workouts.isEmpty {
                Section("当日运动") {
                    ForEach(workouts, id: \.self) { workout in
                        Text(workout)
                            .font(.subheadline)
                    }
                }
            }

            if !summary.adviceText.isEmpty {
                Section("总结与明日建议") {
                    Text(summary.adviceText)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(DateFormatter.csvDate.string(from: summary.date))
        .navigationBarTitleDisplayMode(.inline)
    }
}
