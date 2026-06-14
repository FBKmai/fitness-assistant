import SwiftData
import SwiftUI

struct SummariesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]

    /// 近 7 天，按时间正序，用于趋势条。
    private var trendSummaries: [DailySummary] {
        Array(summaries.prefix(7)).reversed()
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
                                DeficitTrendView(summaries: trendSummaries)
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

/// 近 7 日热量缺口迷你条形（纯 SwiftUI，无额外依赖）。
private struct DeficitTrendView: View {
    let summaries: [DailySummary]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private var maxValue: Double {
        max(summaries.map { max($0.calorieDeficit, 0) }.max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(summaries) { summary in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(deficitReached(summary) ? Color.deficitReached : Color.deficitShort)
                        .frame(height: barHeight(summary.calorieDeficit))
                    Text(Self.dayFormatter.string(from: summary.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92, alignment: .bottom)
    }

    private func barHeight(_ value: Double) -> CGFloat {
        let usable: CGFloat = 70
        let height = CGFloat(max(value, 0) / maxValue) * usable
        return max(height, 3)
    }
}

/// 单日总结详情：完整热量明细 + 当日饮食/运动清单 + AI 建议全文。
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
