import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var aiClient: AIClient

    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]

    @State private var isWorking = false
    @State private var statusMessage = "打开后可同步健康数据并生成今日建议"
    @State private var showingDietCoach = false
    @State private var todayWeightText = ""

    /// 由 MainTabView 注入，用于空态快捷按钮切换到「饮食」「运动」Tab。
    var selection: Binding<Int>? = nil

    private var profile: UserProfile? { profiles.first }
    private var aiSettings: AISettings? { settings.first }
    private var todayMeals: [MealEntry] { meals.filter { Calendar.current.isDateInToday($0.date) } }
    private var confirmedMeals: [MealEntry] { todayMeals.filter(\.isConfirmed) }
    private var todayExercises: [ExerciseEntry] { exercises.filter { Calendar.current.isDateInToday($0.date) } }
    private var todaySummary: DailySummary? { summaries.first { Calendar.current.isDateInToday($0.date) } }

    private var intakeCalories: Double {
        confirmedMeals.reduce(0) { $0 + $1.totalCalories }
    }

    private var manualActiveCalories: Double {
        todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
    }

    private var healthKitAggregateActiveCalories: Double {
        todayExercises.first {
            $0.source == .healthKit && ($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
        }?.activeCalories ?? 0
    }

    private var liveActiveCalories: Double {
        todaySummary?.activeCalories ?? (healthKitAggregateActiveCalories + manualActiveCalories)
    }

    private var restingCalories: Double { profile.map { CalorieCalculator.bmr(profile: $0) } ?? 0 }
    private var deficit: Double { restingCalories + liveActiveCalories - intakeCalories }
    private var deficitTarget: Double { profile?.targetDailyDeficitKcal ?? 0 }
    private var deficitReached: Bool { deficitTarget > 0 && deficit >= deficitTarget }
    private var deficitTint: Color { deficitReached ? .deficitReached : .deficitShort }
    private var hasTodayRecords: Bool { !todayMeals.isEmpty || !todayExercises.isEmpty }
    private var todayWeightValue: Double? { todayWeightText.doubleValue }
    private var todayMealSignature: String {
        confirmedMeals
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.totalCalories):\($0.proteinGrams):\($0.carbsGrams):\($0.fatGrams)" }
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

                Section("今日体重") {
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
                } footer: {
                    Text("体重由你每天手动填写，不再从 Apple 健康读取；保存后会更新基础代谢和今日判断。")
                }

                if !hasTodayRecords {
                    Section {
                        ContentUnavailableView {
                            Label("今天还没有记录", systemImage: "square.and.pencil")
                        } description: {
                            Text("记录今天的饮食和运动，获取专属的热量分析与明日建议。")
                        } actions: {
                            Button {
                                selection?.wrappedValue = 1
                            } label: {
                                Label("记录饮食", systemImage: "fork.knife")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                selection?.wrappedValue = 2
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
                    if let analysis = todaySummary?.snapshot?.analysis {
                        LabeledContent("减脂判断", value: analysis.energyStatus)
                        LabeledContent("数据可信度", value: "\(Int((analysis.dataQualityScore * 100).rounded()))%")
                    }
                    if let todaySummary {
                        LabeledContent("建议生成", value: DateFormatter.shortTime.string(from: todaySummary.generatedAt))
                    } else {
                        LabeledContent("建议生成", value: "未生成")
                    }
                }

                Section {
                    Button {
                        showingDietCoach = true
                    } label: {
                        Label("问 AI 现在怎么吃", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .disabled(profile == nil || aiSettings == nil)
                } footer: {
                    Text("结合今天记录、近 7 天趋势和你的即时问题，给出这一餐及后续安排建议。")
                }

                if let mealReply = buildMealReply() {
                    Section("今日饮食回复") {
                        Text(mealReply.overall)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        MealAdviceRow(title: "早餐", text: mealReply.breakfast)
                        MealAdviceRow(title: "午餐", text: mealReply.lunch)
                        MealAdviceRow(title: "晚餐", text: mealReply.dinner)
                        MealAdviceRow(title: "零嘴", text: mealReply.snack)
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
                            Label("同步并生成今日建议", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(statusMessage)
                }

                if let advice = todaySummary?.adviceText, !advice.isEmpty {
                    Section("今日总结与明日建议") {
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
                if todaySummary == nil {
                    await syncAndGenerateSummary(silent: true)
                }
            }
            .onChange(of: todayMealSignature) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await syncAndGenerateSummary(silent: true) }
            }
            .sheet(isPresented: $showingDietCoach) {
                if let profile, let aiSettings {
                    DietCoachSheet(
                        profile: profile,
                        settings: aiSettings,
                        meals: meals,
                        exercises: exercises,
                        summaries: summaries
                    )
                }
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
        profile.currentWeightKg = weight
        profile.updatedAt = .now

        if let todaySummary {
            todaySummary.weightKg = weight
        }

        do {
            try modelContext.save()
            statusMessage = "今日体重已保存，正在刷新建议..."
            Task { await syncAndGenerateSummary(silent: true) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func buildMealReply() -> MealReply? {
        guard let profile, !confirmedMeals.isEmpty else { return nil }

        let protein = confirmedMeals.reduce(0) { $0 + $1.proteinGrams }
        let carbs = confirmedMeals.reduce(0) { $0 + $1.carbsGrams }
        let fat = confirmedMeals.reduce(0) { $0 + $1.fatGrams }
        var snapshot = DailySnapshot(
            date: .now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: profile.targetDailyDeficitKcal,
            heightCm: profile.heightCm,
            weightKg: profile.currentWeightKg,
            gender: profile.gender.title,
            age: profile.age,
            bmr: restingCalories,
            intakeCalories: intakeCalories,
            activeCalories: liveActiveCalories,
            restingCalories: restingCalories,
            totalBurnCalories: restingCalories + liveActiveCalories,
            calorieDeficit: deficit,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            averageMealConfidence: nil,
            unconfirmedMealCount: todayMeals.filter { !$0.isConfirmed }.count,
            manualActiveCalories: manualActiveCalories,
            meals: confirmedMeals.map(\.textDescription),
            workouts: todayExercises.map(\.workoutType),
            recentDays: [],
            analysis: nil
        )
        snapshot.analysis = FatLossAnalyzer.analyze(snapshot: snapshot)
        let analysis = snapshot.analysis ?? FatLossAnalyzer.analyze(snapshot: snapshot)
        let proteinGap = max(0, analysis.proteinTargetLowerGrams - protein)
        let targetText = deficitTarget > 0 ? "目标缺口 \(Int(deficitTarget)) kcal" : "未设置目标缺口"

        let overall = "当前热量差 = 基础 \(Int(restingCalories.rounded())) + 活动 \(Int(liveActiveCalories.rounded())) - 摄入 \(Int(intakeCalories.rounded())) = \(Int(deficit.rounded())) kcal；\(targetText)。\(analysis.energyMessage)"
        let breakfast = proteinGap > 35
            ? "优先补蛋白：鸡蛋/牛奶/无糖酸奶/豆浆任选 1-2 份，主食选燕麦、全麦面包或玉米。"
            : "保持高蛋白和稳定碳水，避免只喝咖啡或空腹太久。"
        let lunch = deficit > analysis.recommendedDeficitUpperBound
            ? "不要再压得太低，吃一份掌心大小蛋白 + 1 拳主食 + 2 拳蔬菜。"
            : "一份瘦肉/鱼虾/豆腐 + 半碗到一碗主食 + 2 拳蔬菜，少油少酱。"
        let dinner = liveActiveCalories > 0
            ? "如果晚上还要运动，晚餐保留适量碳水；运动后饿了补蛋白，不用高油夜宵补偿。"
            : "晚餐以蛋白和蔬菜为主，主食按饥饿感半碗左右，别为了缺口极端少吃。"
        let snack = proteinGap > 20
            ? "零嘴优先选无糖酸奶、牛奶、茶叶蛋、低脂奶酪或水果；少选饼干、炸物、奶茶。"
            : "想吃零嘴就控制在 100-200 kcal，选水果、酸奶、坚果小份或无糖饮料。"

        return MealReply(
            overall: overall,
            breakfast: breakfast,
            lunch: lunch,
            dinner: dinner,
            snack: snack
        )
    }

    @MainActor
    private func syncAndGenerateSummary(silent: Bool = false) async {
        guard let profile, let aiSettings else { return }
        if isWorking { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 HealthKit..." }
        defer { isWorking = false }

        do {
            try? await healthKitService.requestAuthorization()
            let healthSnapshot = try await healthKitService.fetchSnapshot(for: .now)
            upsertHealthEntries(from: healthSnapshot, profile: profile)
            try modelContext.save()

            let summary = try await buildSummary(profile: profile, settings: aiSettings, healthSnapshot: healthSnapshot)
            upsertSummary(summary)
            try modelContext.save()
            statusMessage = "已更新 \(DateFormatter.shortTime.string(from: .now))"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func upsertHealthEntries(from snapshot: HealthSnapshot, profile: UserProfile) {
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

    private func buildSummary(
        profile: UserProfile,
        settings: AISettings,
        healthSnapshot: HealthSnapshot
    ) async throws -> DailySummary {
        let confirmedMeals = todayMeals.filter(\.isConfirmed)
        let manualCalories = todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
        let intake = confirmedMeals.reduce(0) { $0 + $1.totalCalories }
        let computation = CalorieCalculator.compute(
            intakeCalories: intake,
            healthKitActiveCalories: healthSnapshot.activeEnergyKcal,
            manualActiveCalories: manualCalories,
            healthKitRestingCalories: nil,
            profile: profile
        )

        let mealTexts = confirmedMeals.map { meal in
            "\(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
        }
        let workoutTexts = todayExercises.map { exercise in
            "\(exercise.source.title) \(exercise.workoutType) \(exercise.activeCalories.kcalText)"
        }
        let totalProtein = confirmedMeals.reduce(0) { $0 + $1.proteinGrams }
        let totalCarbs = confirmedMeals.reduce(0) { $0 + $1.carbsGrams }
        let totalFat = confirmedMeals.reduce(0) { $0 + $1.fatGrams }
        let confidenceValues = confirmedMeals.map(\.confidence).filter { $0 > 0 }
        let averageMealConfidence = confidenceValues.isEmpty
            ? nil
            : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let unconfirmedMealCount = todayMeals.filter { !$0.isConfirmed }.count

        // 近 7 天趋势（不含今天），summaries 已按日期倒序排列。
        let todayStart = Calendar.current.startOfDay(for: .now)
        let recentDays = summaries
            .filter { $0.date < todayStart }
            .prefix(7)
            .map { day in
                DayTrend(
                    date: day.date,
                    intakeCalories: day.intakeCalories,
                    calorieDeficit: day.calorieDeficit,
                    weightKg: day.weightKg > 0 ? day.weightKg : nil
                )
            }

        var snapshot = DailySnapshot(
            date: .now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: profile.targetDailyDeficitKcal,
            heightCm: profile.heightCm,
            weightKg: profile.currentWeightKg,
            gender: profile.gender.title,
            age: profile.age,
            bmr: CalorieCalculator.bmr(profile: profile),
            intakeCalories: computation.intakeCalories,
            activeCalories: computation.activeCalories,
            restingCalories: computation.restingCalories,
            totalBurnCalories: computation.totalBurnCalories,
            calorieDeficit: computation.calorieDeficit,
            proteinGrams: totalProtein,
            carbsGrams: totalCarbs,
            fatGrams: totalFat,
            averageMealConfidence: averageMealConfidence,
            unconfirmedMealCount: unconfirmedMealCount,
            manualActiveCalories: manualCalories,
            meals: mealTexts,
            workouts: workoutTexts,
            recentDays: Array(recentDays),
            analysis: nil
        )
        snapshot.analysis = FatLossAnalyzer.analyze(snapshot: snapshot)

        let adviceText: String
        do {
            let advice = try await aiClient.generateDailyAdvice(snapshot: snapshot, settings: settings)
            var sections = [
                advice.summary,
            ]
            if let todayMealAdvice = advice.todayMealAdvice, !todayMealAdvice.isEmpty {
                sections.append("今日饮食：\(todayMealAdvice)")
            }
            if let snackAdvice = advice.snackAdvice, !snackAdvice.isEmpty {
                sections.append("零嘴：\(snackAdvice)")
            }
            sections += [
                "明日饮食：\(advice.tomorrowDietAdvice)",
                "明日运动：\(advice.tomorrowExerciseAdvice)",
                "恢复：\(advice.recoveryAdvice)"
            ]
            adviceText = sections.joined(separator: "\n\n")
        } catch {
            adviceText = fallbackAdvice(snapshot: snapshot, error: error)
        }

        return DailySummary(
            date: Calendar.current.startOfDay(for: .now),
            intakeCalories: computation.intakeCalories,
            activeCalories: computation.activeCalories,
            restingCalories: computation.restingCalories,
            totalBurnCalories: computation.totalBurnCalories,
            calorieDeficit: computation.calorieDeficit,
            weightKg: profile.currentWeightKg,
            proteinGrams: totalProtein,
            carbsGrams: totalCarbs,
            fatGrams: totalFat,
            adviceText: adviceText,
            snapshot: snapshot
        )
    }

    private func upsertSummary(_ newSummary: DailySummary) {
        if let existing = todaySummary {
            existing.intakeCalories = newSummary.intakeCalories
            existing.activeCalories = newSummary.activeCalories
            existing.restingCalories = newSummary.restingCalories
            existing.totalBurnCalories = newSummary.totalBurnCalories
            existing.calorieDeficit = newSummary.calorieDeficit
            existing.weightKg = newSummary.weightKg
            existing.proteinGrams = newSummary.proteinGrams
            existing.carbsGrams = newSummary.carbsGrams
            existing.fatGrams = newSummary.fatGrams
            existing.adviceText = newSummary.adviceText
            existing.snapshot = newSummary.snapshot
            existing.generatedAt = .now
        } else {
            modelContext.insert(newSummary)
        }
    }

    private func fallbackAdvice(snapshot: DailySnapshot, error: Error) -> String {
        let analysis = snapshot.analysis ?? FatLossAnalyzer.analyze(snapshot: snapshot)
        let warningText = analysis.warnings.isEmpty ? "" : "\n\n注意：\(analysis.warnings.joined(separator: "；"))"
        let actionText = analysis.nextActions.joined(separator: "；")
        return """
        \(analysis.energyStatus)：\(analysis.energyMessage)

        今日饮食：\(actionText)

        零嘴：优先选择无糖酸奶、牛奶、茶叶蛋、水果或少量坚果；如果今天摄入已经很低，不建议靠不吃正餐来换零食。

        明日饮食：继续按高蛋白、足量蔬菜、适量主食安排，训练日前后保留碳水。

        明天运动：保持中等强度活动，如果今天训练量较低，可以增加 30-45 分钟快走或力量训练。

        数据可信度：\(Int((analysis.dataQualityScore * 100).rounded()))%。AI 建议暂未生成：\(error.localizedDescription)\(warningText)
        """
    }
}

private struct MealReply {
    var overall: String
    var breakfast: String
    var lunch: String
    var dinner: String
    var snack: String
}

private struct MealAdviceRow: View {
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

private struct DietCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var aiClient: AIClient

    let profile: UserProfile
    let settings: AISettings
    let meals: [MealEntry]
    let exercises: [ExerciseEntry]
    let summaries: [DailySummary]

    @State private var question = "今天晚上要运动，现在是中午，我适合吃什么？"
    @State private var advice: DietCoachAdvice?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var todayMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var confirmedMeals: [MealEntry] {
        todayMeals.filter(\.isConfirmed)
    }

    private var todayExercises: [ExerciseEntry] {
        exercises.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todaySummary: DailySummary? {
        summaries.first { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("你的问题") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $question)
                            .frame(minHeight: 96)
                        if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("例如：今天晚上要力量训练，现在午餐适合吃什么？")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        Task { await askAI() }
                    } label: {
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("生成中…")
                            }
                        } else {
                            Label("生成饮食建议", systemImage: "sparkles")
                        }
                    }
                    .disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("当前数据") {
                    LabeledContent("今日摄入", value: totalIntake.kcalText)
                    LabeledContent("蛋白质", value: "\(Int(totalProtein.rounded())) g")
                    LabeledContent("碳水", value: "\(Int(totalCarbs.rounded())) g")
                    LabeledContent("脂肪", value: "\(Int(totalFat.rounded())) g")
                    LabeledContent("减脂判断", value: currentAnalysis.energyStatus)
                    LabeledContent("数据可信度", value: "\(Int((currentAnalysis.dataQualityScore * 100).rounded()))%")
                }

                if let advice {
                    Section("现在这一餐") {
                        Text(advice.currentMealAdvice)
                            .textSelection(.enabled)
                    }
                    Section("运动前后") {
                        Text(advice.workoutFuelAdvice)
                            .textSelection(.enabled)
                    }
                    Section("今天剩余安排") {
                        Text(advice.remainingDayPlan)
                            .textSelection(.enabled)
                    }
                    if !advice.caution.isEmpty {
                        Section("注意") {
                            Text(advice.caution)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("即时饮食建议")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func askAI() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let snapshot = buildDietCoachSnapshot()
        do {
            advice = try await aiClient.generateDietCoachAdvice(snapshot: snapshot, settings: settings)
        } catch {
            errorMessage = "AI 暂时不可用，已给出本地规则建议：\(error.localizedDescription)"
            advice = fallbackAdvice(snapshot: snapshot)
        }
    }

    private var totalIntake: Double {
        confirmedMeals.reduce(0) { $0 + $1.totalCalories }
    }

    private var totalProtein: Double {
        confirmedMeals.reduce(0) { $0 + $1.proteinGrams }
    }

    private var totalCarbs: Double {
        confirmedMeals.reduce(0) { $0 + $1.carbsGrams }
    }

    private var totalFat: Double {
        confirmedMeals.reduce(0) { $0 + $1.fatGrams }
    }

    private var currentAnalysis: FatLossAnalysis {
        FatLossAnalyzer.analyze(snapshot: buildDailySnapshotForCoach())
    }

    private func buildDietCoachSnapshot() -> DietCoachSnapshot {
        let dailySnapshot = buildDailySnapshotForCoach()
        let analysis = FatLossAnalyzer.analyze(snapshot: dailySnapshot)
        return DietCoachSnapshot(
            requestedAt: .now,
            userQuestion: question,
            goal: dailySnapshot.goal,
            targetDailyDeficitKcal: dailySnapshot.targetDailyDeficitKcal,
            heightCm: dailySnapshot.heightCm,
            weightKg: dailySnapshot.weightKg,
            gender: dailySnapshot.gender,
            age: dailySnapshot.age,
            bmr: dailySnapshot.bmr,
            todayIntakeCalories: dailySnapshot.intakeCalories,
            todayActiveCalories: dailySnapshot.activeCalories,
            todayRestingCalories: dailySnapshot.restingCalories,
            todayTotalBurnCalories: dailySnapshot.totalBurnCalories,
            todayCalorieDeficit: dailySnapshot.calorieDeficit,
            proteinGrams: dailySnapshot.proteinGrams,
            carbsGrams: dailySnapshot.carbsGrams,
            fatGrams: dailySnapshot.fatGrams,
            averageMealConfidence: dailySnapshot.averageMealConfidence,
            todayMeals: dailySnapshot.meals,
            todayWorkouts: dailySnapshot.workouts,
            recentDays: dailySnapshot.recentDays,
            analysis: analysis
        )
    }

    private func buildDailySnapshotForCoach() -> DailySnapshot {
        let manualCalories = todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
        let healthAggregateCalories = todayExercises.first {
            $0.source == .healthKit && ($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
        }?.activeCalories ?? 0
        let activeCalories = todaySummary?.activeCalories ?? (healthAggregateCalories + manualCalories)
        let restingCalories = CalorieCalculator.bmr(profile: profile)
        let totalBurn = activeCalories + restingCalories
        let deficit = totalBurn - totalIntake
        let confidenceValues = confirmedMeals.map(\.confidence).filter { $0 > 0 }
        let averageMealConfidence = confidenceValues.isEmpty
            ? nil
            : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let mealTexts = confirmedMeals.map { meal in
            "\(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
        }
        let workoutTexts = todayExercises.map { exercise in
            "\(exercise.source.title) \(exercise.workoutType) \(exercise.activeCalories.kcalText)"
        }
        let todayStart = Calendar.current.startOfDay(for: .now)
        let recentDays = summaries
            .filter { $0.date < todayStart }
            .prefix(7)
            .map { day in
                DayTrend(
                    date: day.date,
                    intakeCalories: day.intakeCalories,
                    calorieDeficit: day.calorieDeficit,
                    weightKg: day.weightKg > 0 ? day.weightKg : nil
                )
            }

        var snapshot = DailySnapshot(
            date: .now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: profile.targetDailyDeficitKcal,
            heightCm: profile.heightCm,
            weightKg: profile.currentWeightKg,
            gender: profile.gender.title,
            age: profile.age,
            bmr: CalorieCalculator.bmr(profile: profile),
            intakeCalories: totalIntake,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit,
            proteinGrams: totalProtein,
            carbsGrams: totalCarbs,
            fatGrams: totalFat,
            averageMealConfidence: averageMealConfidence,
            unconfirmedMealCount: todayMeals.filter { !$0.isConfirmed }.count,
            manualActiveCalories: manualCalories,
            meals: mealTexts,
            workouts: workoutTexts,
            recentDays: Array(recentDays),
            analysis: nil
        )
        snapshot.analysis = FatLossAnalyzer.analyze(snapshot: snapshot)
        return snapshot
    }

    private func fallbackAdvice(snapshot: DietCoachSnapshot) -> DietCoachAdvice {
        let analysis = snapshot.analysis
        let proteinGap = max(0, analysis.proteinTargetLowerGrams - snapshot.proteinGrams)
        let currentMeal = proteinGap > 20
            ? "这一餐优先补蛋白：选择一份瘦肉、鱼虾、鸡蛋、豆腐或无糖酸奶，搭配 2 拳蔬菜。若晚上要运动，再加半碗到一碗米饭、面、土豆或燕麦。"
            : "这一餐保持清爽均衡：一份优质蛋白 + 2 拳蔬菜 + 按饥饿感加入半碗主食，少油烹饪。"
        let workout = question.contains("运动") || question.contains("训练")
            ? "运动前 2-4 小时保留适量碳水和蛋白；运动后如果还饿，补一份蛋白和少量主食，不要用高油夜宵补偿。"
            : "如果今天后面没有高强度运动，主食按半碗左右开始，根据饥饿感和今日缺口调整。"
        let remaining = analysis.nextActions.joined(separator: "；")
        let caution = (analysis.warnings + analysis.dataQualityNotes).joined(separator: "；")
        return DietCoachAdvice(
            currentMealAdvice: currentMeal,
            workoutFuelAdvice: workout,
            remainingDayPlan: remaining.isEmpty ? analysis.energyMessage : remaining,
            caution: caution.isEmpty ? "这是本地规则建议，AI 恢复后可以生成更个性化的版本。" : caution
        )
    }
}
