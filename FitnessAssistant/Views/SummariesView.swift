import Charts
import SwiftData
import SwiftUI

struct SummariesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingSession.date, order: .reverse) private var trainingSessions: [TrainingSession]
    @Query private var profiles: [UserProfile]

    /// 趋势使用所有有有效身体或汇总数据的日记录，不因缺少 AI 文案丢掉体重点。
    private var summaries: [DayLog] {
        dayLogs.filter {
            $0.weightKg > 0 || $0.hasSummary || $0.sleepHours != nil || $0.waterMl != nil
        }
    }

    /// 近 30 天，按时间正序，用于趋势图。
    private var trendSummaries: [DayLog] {
        Array(summaries.prefix(30)).reversed()
    }

    private var weightTrend: WeightTrendSummary {
        TrendSafetyAnalyzer.weightTrend(
            dayLogs: dayLogs,
            targetWeightKg: profiles.first?.targetWeightKg ?? 0,
            currentWeightKg: profiles.first?.currentWeightKg ?? 0
        )
    }

    var body: some View {
        Group {
            if summaries.isEmpty && trainingSessions.isEmpty {
                ContentUnavailableView {
                    Label("还没有趋势数据", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("记录体重、饮食与训练后，这里会显示体重曲线、缺口趋势和每日复盘归档。")
                }
            } else {
                List {
                        Section("本周概览") {
                            LabeledContent(
                                "7日平均体重",
                                value: weightTrend.sevenDayAverage.map { String(format: "%.2f kg", $0) } ?? "数据不足"
                            )
                            LabeledContent(
                                "14日速度",
                                value: weightTrend.fourteenDayRateKgPerWeek.map { String(format: "%+.2f kg/周", $0) } ?? "数据不足"
                            )
                            LabeledContent("平台期判断", value: weightTrend.isPlateau ? "符合条件" : "暂不符合")
                            LabeledContent("预测置信度", value: weightTrend.confidence)
                            if let range = weightTrend.predictedTargetDateRange {
                                LabeledContent(
                                    "目标日期范围",
                                    value: "\(DateFormatter.csvDate.string(from: range.lowerBound)) - \(DateFormatter.csvDate.string(from: range.upperBound))"
                                )
                            }
                            NavigationLink {
                                TrainingPerformanceView()
                            } label: {
                                Label("训练表现与动作组", systemImage: "dumbbell")
                            }
                        }
                        if trendSummaries.count >= 2 {
                            Section("趋势") {
                                TrendChartsView(summaries: trendSummaries)
                                    .padding(.vertical, 4)
                            }
                        }
                        if !summaries.isEmpty {
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
            }
            .navigationTitle("趋势")
    }

    private func delete(_ summary: DayLog) {
        // 仅清除当日「总结」部分，保留体重/身体打卡，避免删掉体重趋势点。
        summary.generatedAt = nil
        summary.adviceText = ""
        summary.snapshot = nil
        summary.intakeCalories = 0
        summary.activeCalories = 0
        summary.restingCalories = 0
        summary.totalBurnCalories = 0
        summary.calorieDeficit = 0
        summary.proteinGrams = 0
        summary.carbsGrams = 0
        summary.fatGrams = 0
        summary.updatedAt = .now
        try? modelContext.save()
    }

}

/// 是否达到当日目标缺口。
private func deficitReached(_ summary: DayLog) -> Bool {
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
    let summaries: [DayLog]   // 时间正序

    @State private var metric: Metric = .deficit
    @State private var selectedDate: Date?

    enum Metric: String, CaseIterable, Identifiable {
        case deficit = "缺口"
        case energy = "摄入/消耗"
        case weight = "体重"
        case macros = "营养素"
        case recovery = "恢复"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("指标", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: metric) { _, _ in selectedDate = nil }

            valuesHeader

            chart
                .frame(height: 210)
                .animation(.default, value: metric)
        }
    }

    /// 当前选中（点按图表）或默认最近一天，用于表头精确数值。
    private var activeSummary: DayLog? {
        if let selectedDate {
            return summaries.min {
                abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
            }
        }
        return summaries.last
    }

    /// 最近一次设置的目标缺口（>0），用于缺口图的目标线。
    private var targetDeficit: Double {
        summaries.reversed().compactMap { $0.snapshot?.targetDailyDeficitKcal }.first { $0 > 0 } ?? 0
    }

    @ViewBuilder
    private var valuesHeader: some View {
        if let summary = activeSummary {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(
                        selectedDate == nil ? "最近 · \(trendDayFormatter.string(from: summary.date))" : trendDayFormatter.string(from: summary.date),
                        systemImage: selectedDate == nil ? "clock.arrow.circlepath" : "hand.tap"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Spacer()
                    if selectedDate != nil {
                        Button("看最近") { selectedDate = nil }
                            .font(.caption)
                    }
                }
                headerValues(for: summary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
        }
    }

    @ViewBuilder
    private func headerValues(for summary: DayLog) -> some View {
        switch metric {
        case .deficit:
            HStack(spacing: 18) {
                metricValue("缺口", summary.calorieDeficit.signedKcalText, color: deficitReached(summary) ? .deficitReached : .deficitShort)
                if targetDeficit > 0 {
                    metricValue("目标", "\(Int(targetDeficit)) kcal")
                }
            }
        case .energy:
            HStack(spacing: 18) {
                metricValue("摄入", summary.intakeCalories.kcalText)
                metricValue("消耗", summary.totalBurnCalories.kcalText)
                metricValue("净", summary.calorieDeficit.signedKcalText)
            }
        case .weight:
            metricValue("体重", summary.weightKg > 0 ? String(format: "%.1f kg", summary.weightKg) : "—")
        case .macros:
            HStack(spacing: 18) {
                metricValue("蛋白", "\(Int(summary.proteinGrams)) g", color: .macroProtein)
                metricValue("碳水", "\(Int(summary.carbsGrams)) g", color: .macroCarbs)
                metricValue("脂肪", "\(Int(summary.fatGrams)) g", color: .macroFat)
            }
        case .recovery:
            HStack(spacing: 18) {
                metricValue("睡眠", summary.sleepHours.map { String(format: "%.1f h", $0) } ?? "—")
                metricValue("饮水", summary.waterMl.map { "\(Int($0)) ml" } ?? "—")
                metricValue("静息心率", summary.restingHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
            }
        }
    }

    private func metricValue(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    /// 选中某天时高亮该天，未选中为全亮。
    private func barOpacity(_ summary: DayLog) -> Double {
        guard selectedDate != nil, let active = activeSummary else { return 1 }
        return Calendar.current.isDate(summary.date, inSameDayAs: active.date) ? 1 : 0.3
    }

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .deficit:
            Chart {
                ForEach(summaries) { summary in
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("缺口", summary.calorieDeficit)
                    )
                    .foregroundStyle(deficitReached(summary) ? Color.deficitReached : Color.deficitShort)
                    .opacity(barOpacity(summary))
                }
                if targetDeficit > 0 {
                    RuleMark(y: .value("目标", targetDeficit))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("目标 \(Int(targetDeficit))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartYAxis { valueAxis }
            .chartXAxis { dateAxis }
            .chartXSelection(value: $selectedDate)

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
                selectionRule
            }
            .chartYAxis { valueAxis }
            .chartXAxis { dateAxis }
            .chartXSelection(value: $selectedDate)

        case .weight:
            let points = summaries.filter { $0.weightKg > 0 }
            if points.count < 2 {
                ContentUnavailableView(
                    "体重数据不足",
                    systemImage: "scalemass",
                    description: Text("生成几天建议、且健康里有体重记录后，这里会显示体重趋势。")
                )
            } else {
                Chart {
                    ForEach(points) { summary in
                        LineMark(
                            x: .value("日期", summary.date, unit: .day),
                            y: .value("kg", summary.weightKg)
                        )
                        .foregroundStyle(by: .value("类型", "每日体重"))
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("日期", summary.date, unit: .day),
                            y: .value("kg", summary.weightKg)
                        )
                        .foregroundStyle(by: .value("类型", "每日体重"))
                    }
                    ForEach(movingAveragePoints(points)) { point in
                        LineMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("kg", point.weightKg)
                        )
                        .foregroundStyle(by: .value("类型", "7日均值"))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                    selectionRule
                }
                .chartForegroundStyleScale([
                    "每日体重": Color.secondary,
                    "7日均值": Color.accentColor
                ])
                .chartLegend(position: .top, alignment: .leading)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { valueAxis }
                .chartXAxis { dateAxis }
                .chartXSelection(value: $selectedDate)
            }

        case .macros:
            Chart {
                ForEach(summaries) { summary in
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.proteinGrams)
                    )
                    .foregroundStyle(by: .value("营养", "蛋白质"))
                    .position(by: .value("营养", "蛋白质"))
                    .opacity(barOpacity(summary))
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.carbsGrams)
                    )
                    .foregroundStyle(by: .value("营养", "碳水"))
                    .position(by: .value("营养", "碳水"))
                    .opacity(barOpacity(summary))
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("克", summary.fatGrams)
                    )
                    .foregroundStyle(by: .value("营养", "脂肪"))
                    .position(by: .value("营养", "脂肪"))
                    .opacity(barOpacity(summary))
                }
            }
            .chartForegroundStyleScale([
                "蛋白质": Color.macroProtein,
                "碳水": Color.macroCarbs,
                "脂肪": Color.macroFat
            ])
            .chartLegend(position: .top, alignment: .leading)
            .chartYAxis { valueAxis }
            .chartXAxis { dateAxis }
            .chartXSelection(value: $selectedDate)
        case .recovery:
            Chart {
                ForEach(summaries.filter { $0.sleepHours != nil }) { summary in
                    BarMark(
                        x: .value("日期", summary.date, unit: .day),
                        y: .value("睡眠小时", summary.sleepHours ?? 0)
                    )
                    .foregroundStyle((summary.sleepHours ?? 0) < 6 ? Color.orange : Color.blue)
                    .opacity(barOpacity(summary))
                }
            }
            .chartYScale(domain: 0...10)
            .chartYAxis { valueAxis }
            .chartXAxis { dateAxis }
            .chartXSelection(value: $selectedDate)
        }
    }

    private struct MovingWeightPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var weightKg: Double
    }

    private func movingAveragePoints(_ points: [DayLog]) -> [MovingWeightPoint] {
        let ordered = points.sorted { $0.date < $1.date }
        return ordered.indices.map { index in
            let start = max(0, index - 6)
            let window = ordered[start...index].map(\.weightKg)
            return MovingWeightPoint(
                date: ordered[index].date,
                weightKg: window.reduce(0, +) / Double(window.count)
            )
        }
    }

    /// 选中日期的竖向高亮线（用于折线图）。未选中时不绘制，避免污染坐标轴范围。
    @ChartContentBuilder
    private var selectionRule: some ChartContent {
        if selectedDate != nil, let active = activeSummary {
            RuleMark(x: .value("日期", active.date, unit: .day))
                .foregroundStyle(Color.secondary.opacity(0.3))
        }
    }

    private var valueAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel()
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
    let summary: DayLog

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
                if summary.weightKg > 0 {
                    Label(String(format: "%.1f kg", summary.weightKg), systemImage: "scalemass")
                }
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

private struct MealAdviceArchiveRow: View {
    let record: MealAdviceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(record.mealType.title) · \(DateFormatter.shortTime.string(from: record.mealDate))")
                    .font(.headline)
                Spacer()
                Text(record.mealCalories.kcalText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(record.mealDescription.isEmpty ? "未填写描述" : record.mealDescription)
                .font(.subheadline)
                .lineLimit(1)
            Text(record.mealReview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

/// 单日总结详情：完整热量明细 + 营养素/体重 + 当日饮食/运动清单 + AI 建议全文。
struct SummaryDetailView: View {
    let summary: DayLog

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
                LabeledContent("体脂率", value: summary.bodyFatPercentage.map { String(format: "%.1f%%", $0) } ?? "—")
                LabeledContent("BMI", value: summary.bodyMassIndex.map { String(format: "%.1f", $0) } ?? "—")
                LabeledContent("身体数据同步", value: summary.bodyMetricsSyncedAt.map { DateFormatter.csvDateTime.string(from: $0) } ?? "—")
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

private struct MealAdviceDetailView: View {
    let record: MealAdviceRecord

    var body: some View {
        List {
            Section("饮食记录") {
                LabeledContent("餐别", value: record.mealType.title)
                LabeledContent("时间", value: DateFormatter.dateHeader.string(from: record.mealDate) + " " + DateFormatter.shortTime.string(from: record.mealDate))
                LabeledContent("热量", value: record.mealCalories.kcalText)
                if !record.mealDescription.isEmpty {
                    Text(record.mealDescription)
                        .font(.body)
                }
            }

            Section("这一顿评价") {
                Text(record.mealReview)
                    .textSelection(.enabled)
            }

            Section("下一顿建议") {
                Text(record.nextMealAdvice)
                    .textSelection(.enabled)
            }

            if !record.snackAdvice.isEmpty {
                Section("零嘴建议") {
                    Text(record.snackAdvice)
                        .textSelection(.enabled)
                }
            }

            if !record.caution.isEmpty {
                Section("注意") {
                    Text(record.caution)
                        .textSelection(.enabled)
                }
            }

            if let snapshot = record.snapshot, !snapshot.todayMeals.isEmpty {
                Section("当日饮食快照") {
                    ForEach(snapshot.todayMeals, id: \.self) { meal in
                        Text(meal)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(record.mealType.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TrainingPerformanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingSession.date, order: .reverse) private var sessions: [TrainingSession]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]

    @State private var showingEditor = false
    @State private var editingSession: TrainingSession?

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("还没有训练表现记录", systemImage: "dumbbell")
                } description: {
                    Text("Apple 健康训练会自动同步，也可以手动记录动作、重量、次数、组数和 RPE。")
                } actions: {
                    Button("记录训练") { showingEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section("训练趋势") {
                    LabeledContent("近7天训练", value: "\(recentSessionCount) 次")
                    LabeledContent("近7天总容量", value: "\(Int(recentVolume.rounded())) kg")
                    LabeledContent(
                        "最近训练心率",
                        value: sessions.compactMap(\.averageHeartRate).first.map { "\(Int($0.rounded())) 次/分" } ?? "—"
                    )
                }

                Section("训练记录") {
                    ForEach(sessions) { session in
                        Button {
                            editingSession = session
                        } label: {
                            TrainingSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(session)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("训练表现")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("记录训练", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            TrainingSessionEditorView()
        }
        .sheet(item: $editingSession) { session in
            TrainingSessionEditorView(session: session)
        }
    }

    private var recentSessions: [TrainingSession] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return sessions.filter { $0.date >= start }
    }

    private var recentSessionCount: Int { recentSessions.count }
    private var recentVolume: Double { recentSessions.reduce(0) { $0 + $1.totalVolumeKg } }

    private func delete(_ session: TrainingSession) {
        for exercise in exercises where exercise.trainingSessionID == session.id {
            modelContext.delete(exercise)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

private struct TrainingSessionRow: View {
    let session: TrainingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title)
                    .font(.headline)
                Spacer()
                Text(DateFormatter.dateHeader.string(from: session.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(Int(session.durationMinutes.rounded())) 分钟", systemImage: "clock")
                Label(session.activeCalories.kcalText, systemImage: "flame")
                if !session.sets.isEmpty {
                    Label("\(session.sets.count) 组", systemImage: "list.number")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if session.totalVolumeKg > 0 {
                Text("训练容量 \(Int(session.totalVolumeKg.rounded())) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TrainingSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]

    let session: TrainingSession?

    @State private var date: Date
    @State private var title: String
    @State private var durationMinutes: Double
    @State private var activeCalories: Double
    @State private var note: String
    @State private var sets: [TrainingSetRecord]

    init(session: TrainingSession? = nil) {
        self.session = session
        _date = State(initialValue: session?.date ?? .now)
        _title = State(initialValue: session?.title ?? "")
        _durationMinutes = State(initialValue: session?.durationMinutes ?? 0)
        _activeCalories = State(initialValue: session?.activeCalories ?? 0)
        _note = State(initialValue: session?.note ?? "")
        _sets = State(initialValue: session?.sets ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("训练") {
                    DatePicker("时间", selection: $date)
                    TextField("训练名称，例如 胸部力量", text: $title)
                    LabeledDoubleFieldRow(title: "时长", unit: "分钟", value: $durationMinutes)
                    LabeledDoubleFieldRow(title: "活动热量", unit: "kcal", value: $activeCalories)
                    TextField("备注", text: $note, axis: .vertical)
                }

                Section {
                    ForEach($sets) { $set in
                        TrainingSetEditorRow(set: $set)
                    }
                    .onDelete { sets.remove(atOffsets: $0) }

                    Button {
                        let exerciseName = sets.last?.exerciseName ?? ""
                        let nextNumber = sets.filter { $0.exerciseName == exerciseName }.count + 1
                        sets.append(TrainingSetRecord(
                            exerciseName: exerciseName,
                            setNumber: nextNumber,
                            weightKg: 0,
                            repetitions: 0
                        ))
                    } label: {
                        Label("添加动作组", systemImage: "plus")
                    }
                } header: {
                    Text("动作表现")
                } footer: {
                    Text("容量按重量 × 次数汇总；RPE 建议填写 1-10。")
                }
            }
            .navigationTitle(session == nil ? "记录训练" : "编辑训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target: TrainingSession
        if let session {
            target = session
            target.date = date
            target.title = title
            target.durationMinutes = max(0, durationMinutes)
            target.activeCalories = max(0, activeCalories)
            target.note = note
            target.sets = normalizedSets
            target.updatedAt = .now
        } else {
            target = TrainingSession(
                date: date,
                title: title,
                source: .manual,
                durationMinutes: max(0, durationMinutes),
                activeCalories: max(0, activeCalories),
                sets: normalizedSets,
                note: note
            )
            modelContext.insert(target)
        }

        if let exercise = exercises.first(where: { $0.trainingSessionID == target.id }) {
            exercise.date = target.date
            exercise.workoutType = target.title
            exercise.durationMinutes = target.durationMinutes
            exercise.activeCalories = target.activeCalories
        } else if target.source == .manual {
            modelContext.insert(ExerciseEntry(
                date: target.date,
                source: .manual,
                workoutType: target.title,
                durationMinutes: target.durationMinutes,
                activeCalories: target.activeCalories,
                trainingSessionID: target.id
            ))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("保存训练表现失败：\(error.localizedDescription)", category: "训练")
        }
    }

    private var normalizedSets: [TrainingSetRecord] {
        var counters: [String: Int] = [:]
        return sets
            .filter { !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { value in
                var item = value
                let key = item.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                counters[key, default: 0] += 1
                item.exerciseName = key
                item.setNumber = counters[key] ?? 1
                item.weightKg = max(0, item.weightKg)
                item.repetitions = max(0, item.repetitions)
                if let rpe = item.rpe { item.rpe = min(max(rpe, 1), 10) }
                return item
            }
    }
}

private struct TrainingSetEditorRow: View {
    @Binding var set: TrainingSetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("动作名称", text: $set.exerciseName)
                .font(.headline)
            HStack {
                TextField("重量kg", value: $set.weightKg, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                TextField("次数", value: $set.repetitions, format: .number)
                    .keyboardType(.numberPad)
                TextField(
                    "RPE",
                    value: Binding(
                        get: { set.rpe ?? 0 },
                        set: { set.rpe = $0 > 0 ? $0 : nil }
                    ),
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
            }
            TextField("本组备注", text: $set.note)
        }
        .padding(.vertical, 4)
    }
}
