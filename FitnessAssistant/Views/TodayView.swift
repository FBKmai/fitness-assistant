import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataStore.self) private var store
    @EnvironmentObject private var healthKitService: HealthKitService

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \MealAdviceRecord.createdAt, order: .reverse) private var mealAdviceRecords: [MealAdviceRecord]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]

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
                        Task {
                            guard let profile else { return }
                            await store.syncHealthOnly(profile: profile, exercises: exercises, dayLogs: dayLogs)
                            refreshTodayWeightText()
                        }
                    } label: {
                        Label("从 Apple 健康同步身体数据", systemImage: "heart.text.square")
                    }
                    .disabled(store.isWorking)
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
                        Task {
                            guard let profile else { return }
                            await store.syncAndGenerateToday(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, trainingPlans: trainingPlans)
                        }
                    } label: {
                        if store.isWorking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("处理中…")
                            }
                        } else {
                            Label("同步并刷新今日数据", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(store.isWorking)
                } footer: {
                    Text(store.statusMessage)
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
                store.configure(context: modelContext, health: healthKitService)
                refreshTodayWeightText()
            }
            .task {
                store.configure(context: modelContext, health: healthKitService)
                guard let profile else { return }
                await store.syncHealthOnly(profile: profile, exercises: exercises, dayLogs: dayLogs, silent: true)
                if todayLog?.hasSummary != true {
                    await store.syncAndGenerateToday(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, trainingPlans: trainingPlans, silent: true)
                }
                refreshTodayWeightText()
            }
            .onChange(of: todayMealSignature) { _, newValue in
                guard !newValue.isEmpty, let profile else { return }
                Task { await store.syncAndGenerateToday(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, trainingPlans: trainingPlans, silent: true) }
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
        // 体重唯一写入口（经 DataStore）。保存成功后刷新今日总结。
        guard store.recordWeight(weight, profile: profile, dayLogs: dayLogs) else { return }
        store.statusMessage = "今日体重已保存，正在刷新建议..."
        Task {
            await store.syncAndGenerateToday(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, trainingPlans: trainingPlans, silent: true)
        }
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
