import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \MealAdviceRecord.createdAt, order: .reverse) private var mealAdviceRecords: [MealAdviceRecord]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]

    @State private var isWorking = false
    @State private var statusMessage = "打开后可同步健康数据并刷新今日仪表盘"
    @State private var todayWeightText = ""

    /// 由 MainTabView 注入，用于空态快捷按钮切换到「饮食」「运动」Tab。
    var selection: Binding<Int>? = nil

    private var profile: UserProfile? { profiles.first }
    private var todayMeals: [MealEntry] { meals.filter { Calendar.current.isDateInToday($0.date) } }
    private var todayExercises: [ExerciseEntry] { exercises.filter { Calendar.current.isDateInToday($0.date) } }
    private var todayLog: DayLog? { dayLogs.first { Calendar.current.isDateInToday($0.date) } }
    private var latestTodayMealAdvice: MealAdviceRecord? {
        mealAdviceRecords.first { Calendar.current.isDateInToday($0.mealDate) }
    }

    /// 今日仪表盘的唯一数据源（活动消耗去重、目标缺口口径、体重回退链、analysis）。
    private var todayMetrics: DayMetrics? {
        guard let profile else { return nil }
        return DayMetricsCalculator.metrics(
            for: .now,
            profile: profile,
            meals: meals,
            exercises: exercises,
            dayLogs: dayLogs,
            trainingPlans: trainingPlans
        )
    }

    private var intakeCalories: Double { todayMetrics?.intakeCalories ?? 0 }
    private var liveActiveCalories: Double { todayMetrics?.activeCalories ?? 0 }
    private var restingCalories: Double { todayMetrics?.restingCalories ?? 0 }
    private var deficit: Double { todayMetrics?.calorieDeficit ?? 0 }
    /// 目标缺口优先取最新训练计划算出的缺口（TDEE − 每日目标热量），无训练计划时回退到设置里的目标缺口。
    private var effectiveDeficitTarget: Double {
        guard let profile else { return 0 }
        return DayMetricsCalculator.effectiveDeficitTarget(profile: profile, trainingPlans: trainingPlans)
    }
    private var deficitTarget: Double { effectiveDeficitTarget }
    private var deficitReached: Bool { todayMetrics?.deficitReached ?? false }
    private var deficitTint: Color { deficitReached ? .deficitReached : .deficitShort }
    private var hasTodayRecords: Bool { !todayMeals.isEmpty || !todayExercises.isEmpty }
    private var todayWeightValue: Double? { todayWeightText.doubleValue }
    private var todayBodyFatPercentage: Double? { todayMetrics?.bodyFatPercentage }
    private var todayBodyMassIndex: Double? { todayMetrics?.bodyMassIndex }
    private var bodyMetricsSyncedText: String {
        guard let date = todayLog?.bodyMetricsSyncedAt else { return "尚未同步" }
        return DateFormatter.shortTime.string(from: date)
    }
    private var todayMealSignature: String {
        todayMeals
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.mealTypeRaw):\($0.date.timeIntervalSince1970):\($0.totalCalories):\($0.proteinGrams):\($0.carbsGrams):\($0.fatGrams)" }
            .joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppMetrics.tileSpacing) {
                        MetricTile(title: "摄入", value: intakeCalories.kcalValue, systemImage: "fork.knife")
                        MetricTile(title: "热量差", value: deficit.signedKcalValue, systemImage: "plusminus", highlighted: true, tint: deficitTint)
                    }
                    HStack(spacing: AppMetrics.tileSpacing) {
                        MetricTile(title: "活动", value: liveActiveCalories.kcalValue, systemImage: "flame")
                        MetricTile(title: "基础", value: restingCalories.kcalValue, systemImage: "bed.double")
                    }
                    if deficitTarget > 0 {
                        MetricProgressBar(title: "距每日缺口目标 \(Int(deficitTarget)) kcal", current: deficit, target: deficitTarget, tint: deficitTint)
                            .padding(.top, 6)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                Section {
                    HStack {
                        TextField("体重 kg", text: $todayWeightText)
                            .keyboardType(.decimalPad)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        saveTodayWeight()
                    } label: {
                        Label("保存今日体重", systemImage: "scalemass")
                    }
                    .disabled(!isValidWeight(todayWeightValue))
                    Button {
                        Task { await syncHealthKitOnly() }
                    } label: {
                        Label("从 Apple 健康同步身体数据", systemImage: "heart.text.square")
                    }
                    .disabled(isWorking)
                    LabeledContent("体脂率", value: todayBodyFatPercentage.map { String(format: "%.1f%%", $0) } ?? "—")
                    LabeledContent("BMI", value: todayBodyMassIndex.map { String(format: "%.1f", $0) } ?? "—")
                    LabeledContent("身体数据同步", value: bodyMetricsSyncedText)
                } header: {
                    Text("今日身体数据")
                } footer: {
                    Text("体脂秤写入 Apple 健康后，打开 App 或点击同步会读取当天最新体重、体脂率和 BMI；没有当天体重时可临时手动填写。")
                }

                if !hasTodayRecords {
                    Section {
                        ContentUnavailableView {
                            Label("今天还没有记录", systemImage: "square.and.pencil")
                        } description: {
                            Text("记录今天的饮食和运动，获取专属的热量分析与明日建议。")
                        } actions: {
                            Button {
                                selection?.wrappedValue = 2
                            } label: {
                                Label("记录饮食", systemImage: "fork.knife")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                selection?.wrappedValue = 3
                            } label: {
                                Label("记录运动", systemImage: "figure.run")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("今日状态") {
                    LabeledContent("HealthKit", value: healthKitService.authorizationStatusDescription)
                    LabeledContent("饮食记录", value: "\(todayMeals.count) 条")
                    LabeledContent("运动记录", value: "\(todayExercises.count) 条")
                    if let todayLog {
                        if let sleepHours = todayLog.sleepHours {
                            LabeledContent("睡眠", value: "\(String(format: "%.1f", sleepHours)) 小时")
                        }
                        if let waterMl = todayLog.waterMl {
                            LabeledContent("饮水", value: "\(Int(waterMl.rounded())) ml")
                        }
                        if !todayLog.symptoms.isEmpty {
                            LabeledContent("身体状态", value: todayLog.symptoms)
                        }
                    }
                    if let analysis = todayMetrics?.analysis {
                        LabeledContent("减脂判断", value: analysis.energyStatus)
                        LabeledContent("数据可信度", value: "\(Int((analysis.dataQualityScore * 100).rounded()))%")
                    }
                    if let generatedAt = todayLog?.generatedAt {
                        LabeledContent("建议生成", value: DateFormatter.shortTime.string(from: generatedAt))
                    } else {
                        LabeledContent("建议生成", value: "未生成")
                    }
                }

                if let latestTodayMealAdvice {
                    Section("今日饮食回复") {
                        LabeledContent("餐别", value: "\(latestTodayMealAdvice.mealType.title) · \(DateFormatter.shortTime.string(from: latestTodayMealAdvice.mealDate))")
                        AdviceTextBlock(title: "这一顿评价", text: latestTodayMealAdvice.mealReview)
                        AdviceTextBlock(title: "下一顿建议", text: latestTodayMealAdvice.nextMealAdvice)
                        AdviceTextBlock(title: "零嘴建议", text: latestTodayMealAdvice.snackAdvice)
                        if !latestTodayMealAdvice.caution.isEmpty {
                            AdviceTextBlock(title: "注意", text: latestTodayMealAdvice.caution)
                        }
                    }
                } else if !todayMeals.isEmpty {
                    Section("今日饮食回复") {
                        ContentUnavailableView {
                            Label("还没有单餐评价", systemImage: "text.bubble")
                        } description: {
                            Text("新增或编辑一条饮食记录并保存后，这里会显示 AI 对那一顿的评价和下一顿建议。")
                        }
                    }
                }

                Section {
                    Button {
                        Task { await syncAndGenerateSummary() }
                    } label: {
                        if isWorking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("处理中…")
                            }
                        } else {
                            Label("同步并刷新今日数据", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(statusMessage)
                }

                if let advice = todayLog?.adviceText, !advice.isEmpty {
                    Section("今日数据摘要") {
                        Text(advice)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("今日")
            .onAppear {
                refreshTodayWeightText()
            }
            .task {
                await syncHealthKitOnly(silent: true)
                if todayLog?.hasSummary != true {
                    await syncAndGenerateSummary(silent: true)
                }
            }
            .onChange(of: todayMealSignature) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await syncAndGenerateSummary(silent: true) }
            }
        }
    }

    private func refreshTodayWeightText() {
        guard todayWeightText.isEmpty, let profile else { return }
        todayWeightText = String(format: "%.1f", profile.currentWeightKg)
    }

    private func isValidWeight(_ value: Double?) -> Bool {
        guard let value else { return false }
        return (30...250).contains(value)
    }

    private func saveTodayWeight() {
        guard let profile, let weight = todayWeightValue, isValidWeight(weight) else { return }
        // 体重唯一写入口：一致写入 档案 + 当天 DayLog。
        WeightWriter.record(weight, profile: profile, context: modelContext, dayLogs: dayLogs)

        do {
            try modelContext.save()
            statusMessage = "今日体重已保存，正在刷新建议..."
            Task { await syncAndGenerateSummary(silent: true) }
        } catch {
            AppLog.error("保存今日体重失败：\(error.localizedDescription)", category: "今日")
            statusMessage = error.localizedDescription
        }
    }

    private func upsertTodayLog() -> DayLog {
        if let todayLog {
            return todayLog
        }
        let log = DayLog(date: Calendar.current.startOfDay(for: .now))
        modelContext.insert(log)
        return log
    }

    @MainActor
    private func syncHealthKitOnly(silent: Bool = false) async {
        guard let profile else { return }
        if isWorking { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 Apple 健康身体数据..." }
        defer { isWorking = false }

        do {
            try? await healthKitService.requestAuthorization()
            let healthSnapshot = try await healthKitService.fetchSnapshot(for: .now)
            upsertHealthEntries(from: healthSnapshot, profile: profile)
            refreshTodayLogFromHealth(healthSnapshot)
            try modelContext.save()

            if !silent {
                statusMessage = healthSnapshot.bodyMetrics.hasAnyValue
                    ? "已同步 Apple 健康身体数据 \(DateFormatter.shortTime.string(from: .now))"
                    : "Apple 健康今天还没有体脂秤数据，可先手动保存体重。"
            }
        } catch {
            AppLog.error("同步 Apple 健康数据失败：\(error.localizedDescription)", category: "今日")
            if !silent {
                statusMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func syncAndGenerateSummary(silent: Bool = false) async {
        guard let profile else { return }
        if isWorking { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 HealthKit..." }
        defer { isWorking = false }

        do {
            try? await healthKitService.requestAuthorization()
            let healthSnapshot = try await healthKitService.fetchSnapshot(for: .now)
            upsertHealthEntries(from: healthSnapshot, profile: profile)
            refreshTodayLogFromHealth(healthSnapshot)
            generateTodaySummary(profile: profile, healthSnapshot: healthSnapshot)
            try modelContext.save()
            statusMessage = "已更新 \(DateFormatter.shortTime.string(from: .now))"
        } catch {
            AppLog.error("同步并生成今日总结失败：\(error.localizedDescription)", category: "今日")
            statusMessage = error.localizedDescription
        }
    }

    private func upsertHealthEntries(from snapshot: HealthSnapshot, profile: UserProfile) {
        if let weight = snapshot.bodyMetrics.weightKg, isValidWeight(weight) {
            profile.currentWeightKg = weight
            profile.updatedAt = .now
            todayWeightText = String(format: "%.1f", weight)
        }

        let aggregateID = "daily-\(snapshot.date.dayKey)"
        let aggregate = exercises.first { $0.healthKitWorkoutID == aggregateID }
        if let aggregate {
            aggregate.date = snapshot.date
            aggregate.workoutType = "每日活动合计"
            aggregate.activeCalories = snapshot.activeEnergyKcal
            aggregate.steps = snapshot.steps
        } else {
            modelContext.insert(ExerciseEntry(
                date: snapshot.date,
                source: .healthKit,
                workoutType: "每日活动合计",
                activeCalories: snapshot.activeEnergyKcal,
                steps: snapshot.steps,
                healthKitWorkoutID: aggregateID
            ))
        }

        for workout in snapshot.workouts {
            let existing = exercises.first { $0.healthKitWorkoutID == workout.id }
            if let existing {
                existing.date = workout.startDate
                existing.workoutType = workout.activityName
                existing.durationMinutes = workout.durationMinutes
                existing.activeCalories = workout.activeCalories
            } else {
                modelContext.insert(ExerciseEntry(
                    date: workout.startDate,
                    source: .healthKit,
                    workoutType: workout.activityName,
                    durationMinutes: workout.durationMinutes,
                    activeCalories: workout.activeCalories,
                    healthKitWorkoutID: workout.id
                ))
            }
        }
    }

    /// 把 Apple 健康的当日身体数据写进当天 DayLog（体重/体脂/BMI/睡眠/同步时间）。
    private func refreshTodayLogFromHealth(_ snapshot: HealthSnapshot) {
        guard snapshot.bodyMetrics.hasAnyValue || snapshot.sleepHours != nil else { return }
        let log = upsertTodayLog()
        if let weight = snapshot.bodyMetrics.weightKg, isValidWeight(weight) {
            log.weightKg = weight
        }
        if let bodyFat = snapshot.bodyMetrics.bodyFatPercentage {
            log.bodyFatPercentage = bodyFat
        }
        if let bmi = snapshot.bodyMetrics.bodyMassIndex {
            log.bodyMassIndex = bmi
        }
        if let sleepHours = snapshot.sleepHours {
            log.sleepHours = sleepHours
        }
        if snapshot.bodyMetrics.hasAnyValue {
            log.bodyMetricsSyncedAt = snapshot.bodyMetrics.measuredAt ?? .now
        }
        log.updatedAt = .now
    }

    /// 生成当日总结并写进当天 DayLog（缓存热量/营养 + AI 摘要 + 快照 + 生成时间）。
    /// 派生指标全部来自唯一聚合源 DayMetrics，含本次 HealthKit 实时快照。
    private func generateTodaySummary(profile: UserProfile, healthSnapshot: HealthSnapshot) {
        let metrics = DayMetricsCalculator.metrics(
            for: .now,
            profile: profile,
            meals: meals,
            exercises: exercises,
            dayLogs: dayLogs,
            trainingPlans: trainingPlans,
            healthSnapshot: healthSnapshot
        )
        let snapshot = metrics.dailySnapshot
        let log = upsertTodayLog()
        log.intakeCalories = metrics.intakeCalories
        log.activeCalories = metrics.activeCalories
        log.restingCalories = metrics.restingCalories
        log.totalBurnCalories = metrics.totalBurnCalories
        log.calorieDeficit = metrics.calorieDeficit
        log.proteinGrams = metrics.proteinGrams
        log.carbsGrams = metrics.carbsGrams
        log.fatGrams = metrics.fatGrams
        if let weight = metrics.weightKg { log.weightKg = weight }
        if let bodyFat = metrics.bodyFatPercentage { log.bodyFatPercentage = bodyFat }
        if let bmi = metrics.bodyMassIndex { log.bodyMassIndex = bmi }
        if let measuredAt = metrics.bodyMetricsMeasuredAt { log.bodyMetricsSyncedAt = measuredAt }
        log.adviceText = localSummaryText(snapshot: snapshot)
        log.snapshot = snapshot
        log.generatedAt = .now
        log.updatedAt = .now
    }

    private func localSummaryText(snapshot: DailySnapshot) -> String {
        let analysis = snapshot.analysis ?? FatLossAnalyzer.analyze(snapshot: snapshot)
        let warnings = analysis.warnings.isEmpty ? "" : "\n\n注意：\(analysis.warnings.joined(separator: "；"))"
        return """
        \(analysis.energyStatus)：\(analysis.energyMessage)

        今日摄入 \(snapshot.intakeCalories.kcalText)，活动消耗 \(snapshot.activeCalories.kcalText)，热量差 \(snapshot.calorieDeficit.signedKcalText)。

        蛋白质：\(Int(snapshot.proteinGrams.rounded()))g（目标约 \(Int(analysis.proteinTargetLowerGrams.rounded()))-\(Int(analysis.proteinTargetUpperGrams.rounded()))g）。脂肪状态：\(analysis.fatStatus)。

        下一步：\(analysis.nextActions.joined(separator: "；"))

        需要 AI 给饭前饭后、训练前后或明日安排时，请到「教练」Tab 继续对话。\(warnings)
        """
    }
}

private struct AdviceTextBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
