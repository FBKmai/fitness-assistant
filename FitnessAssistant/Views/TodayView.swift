import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]
    @Query(sort: \MealAdviceRecord.createdAt, order: .reverse) private var mealAdviceRecords: [MealAdviceRecord]
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]

    @State private var isWorking = false
    @State private var statusMessage = "打开后可同步健康数据并刷新今日仪表盘"
    @State private var todayWeightText = ""
    @State private var sleepHoursText = ""
    @State private var waterMlText = ""
    @State private var hungerLevel = 5.0
    @State private var moodText = ""
    @State private var symptomsText = ""
    @State private var checkInNoteText = ""

    /// 由 MainTabView 注入，用于空态快捷按钮切换到「饮食」「运动」Tab。
    var selection: Binding<Int>? = nil

    private var profile: UserProfile? { profiles.first }
    private var todayMeals: [MealEntry] { meals.filter { Calendar.current.isDateInToday($0.date) } }
    private var confirmedMeals: [MealEntry] { todayMeals.filter(\.isConfirmed) }
    private var todayExercises: [ExerciseEntry] { exercises.filter { Calendar.current.isDateInToday($0.date) } }
    private var todaySummary: DailySummary? { summaries.first { Calendar.current.isDateInToday($0.date) } }
    private var todayCheckIn: DailyCheckIn? { checkIns.first { Calendar.current.isDateInToday($0.date) } }
    private var latestTodayMealAdvice: MealAdviceRecord? {
        mealAdviceRecords.first { Calendar.current.isDateInToday($0.mealDate) }
    }

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
    private var todayBodyFatPercentage: Double? { todaySummary?.bodyFatPercentage }
    private var todayBodyMassIndex: Double? { todaySummary?.bodyMassIndex }
    private var bodyMetricsSyncedText: String {
        guard let date = todaySummary?.bodyMetricsSyncedAt else { return "尚未同步" }
        return DateFormatter.shortTime.string(from: date)
    }
    private var todayMealSignature: String {
        confirmedMeals
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
                    if let todayCheckIn {
                        if let sleepHours = todayCheckIn.sleepHours {
                            LabeledContent("睡眠", value: "\(String(format: "%.1f", sleepHours)) 小时")
                        }
                        if let waterMl = todayCheckIn.waterMl {
                            LabeledContent("饮水", value: "\(Int(waterMl.rounded())) ml")
                        }
                        if !todayCheckIn.symptoms.isEmpty {
                            LabeledContent("身体状态", value: todayCheckIn.symptoms)
                        }
                    }
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

                Section("每日打卡") {
                    HStack {
                        TextField("睡眠 小时", text: $sleepHoursText)
                            .keyboardType(.decimalPad)
                        Text("小时")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("饮水 ml", text: $waterMlText)
                            .keyboardType(.decimalPad)
                        Text("ml")
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $hungerLevel, in: 1...10, step: 1) {
                        LabeledContent("饥饿感", value: "\(Int(hungerLevel))/10")
                    }
                    TextField("心情", text: $moodText)
                    TextField("身体状态/症状", text: $symptomsText, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("备注", text: $checkInNoteText, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        saveDailyCheckIn()
                    } label: {
                        Label("保存今日打卡", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text("这些数据会进入 AI 教练上下文，用于判断训练强度、晚餐安排、体重波动和恢复风险。")
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
                } else if !confirmedMeals.isEmpty {
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

                if let advice = todaySummary?.adviceText, !advice.isEmpty {
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
                refreshCheckInFields()
            }
            .task {
                await syncHealthKitOnly(silent: true)
                if todaySummary == nil {
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

    private func refreshCheckInFields() {
        guard let todayCheckIn else { return }
        if sleepHoursText.isEmpty, let sleepHours = todayCheckIn.sleepHours {
            sleepHoursText = String(format: "%.1f", sleepHours)
        }
        if waterMlText.isEmpty, let waterMl = todayCheckIn.waterMl {
            waterMlText = String(format: "%.0f", waterMl)
        }
        if let hunger = todayCheckIn.hungerLevel {
            hungerLevel = Double(hunger)
        }
        if moodText.isEmpty {
            moodText = todayCheckIn.mood
        }
        if symptomsText.isEmpty {
            symptomsText = todayCheckIn.symptoms
        }
        if checkInNoteText.isEmpty {
            checkInNoteText = todayCheckIn.note
        }
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
        let checkIn = upsertTodayCheckIn()
        checkIn.weightKg = weight

        do {
            try modelContext.save()
            statusMessage = "今日体重已保存，正在刷新建议..."
            Task { await syncAndGenerateSummary(silent: true) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveDailyCheckIn() {
        let checkIn = upsertTodayCheckIn()
        checkIn.sleepHours = sleepHoursText.doubleValue
        checkIn.waterMl = waterMlText.doubleValue
        checkIn.hungerLevel = Int(hungerLevel.rounded())
        checkIn.mood = moodText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.symptoms = symptomsText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.note = checkInNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkIn.updatedAt = .now

        if let weight = todayWeightValue, isValidWeight(weight) {
            checkIn.weightKg = weight
        }
        if let todaySummary {
            checkIn.bodyFatPercentage = todaySummary.bodyFatPercentage
            checkIn.bodyMassIndex = todaySummary.bodyMassIndex
        }

        do {
            try modelContext.save()
            statusMessage = "今日打卡已保存，AI 教练上下文已更新。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func upsertTodayCheckIn() -> DailyCheckIn {
        if let todayCheckIn {
            return todayCheckIn
        }
        let checkIn = DailyCheckIn(date: Calendar.current.startOfDay(for: .now))
        modelContext.insert(checkIn)
        return checkIn
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
            refreshTodayCheckInFromHealth(healthSnapshot)
            refreshTodaySummaryFromHealth(healthSnapshot, profile: profile)
            try modelContext.save()

            if !silent {
                statusMessage = healthSnapshot.bodyMetrics.hasAnyValue
                    ? "已同步 Apple 健康身体数据 \(DateFormatter.shortTime.string(from: .now))"
                    : "Apple 健康今天还没有体脂秤数据，可先手动保存体重。"
            }
        } catch {
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
            refreshTodayCheckInFromHealth(healthSnapshot)
            try modelContext.save()

            let summary = try await buildSummary(profile: profile, healthSnapshot: healthSnapshot)
            upsertSummary(summary)
            try modelContext.save()
            statusMessage = "已更新 \(DateFormatter.shortTime.string(from: .now))"
        } catch {
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

    private func refreshTodayCheckInFromHealth(_ snapshot: HealthSnapshot) {
        guard snapshot.bodyMetrics.hasAnyValue || snapshot.sleepHours != nil else { return }
        let checkIn = upsertTodayCheckIn()
        if let weight = snapshot.bodyMetrics.weightKg, isValidWeight(weight) {
            checkIn.weightKg = weight
        }
        if let bodyFat = snapshot.bodyMetrics.bodyFatPercentage {
            checkIn.bodyFatPercentage = bodyFat
        }
        if let bmi = snapshot.bodyMetrics.bodyMassIndex {
            checkIn.bodyMassIndex = bmi
        }
        if let sleepHours = snapshot.sleepHours {
            checkIn.sleepHours = sleepHours
        }
        checkIn.updatedAt = .now
        refreshCheckInFields()
    }

    private func refreshTodaySummaryFromHealth(_ snapshot: HealthSnapshot, profile: UserProfile) {
        guard let todaySummary else { return }

        let confirmedMeals = todayMeals.filter(\.isConfirmed)
        let manualCalories = todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
        let intake = confirmedMeals.reduce(0) { $0 + $1.totalCalories }
        let computation = CalorieCalculator.compute(
            intakeCalories: intake,
            healthKitActiveCalories: snapshot.activeEnergyKcal,
            manualActiveCalories: manualCalories,
            healthKitRestingCalories: nil,
            profile: profile
        )

        todaySummary.intakeCalories = computation.intakeCalories
        todaySummary.activeCalories = computation.activeCalories
        todaySummary.restingCalories = computation.restingCalories
        todaySummary.totalBurnCalories = computation.totalBurnCalories
        todaySummary.calorieDeficit = computation.calorieDeficit
        todaySummary.weightKg = snapshot.bodyMetrics.weightKg ?? profile.currentWeightKg
        if let bodyFat = snapshot.bodyMetrics.bodyFatPercentage {
            todaySummary.bodyFatPercentage = bodyFat
        }
        if let bodyMassIndex = snapshot.bodyMetrics.bodyMassIndex {
            todaySummary.bodyMassIndex = bodyMassIndex
        }
        if snapshot.bodyMetrics.hasAnyValue {
            todaySummary.bodyMetricsSyncedAt = snapshot.bodyMetrics.measuredAt ?? .now
        }

        if var existingSnapshot = todaySummary.snapshot {
            existingSnapshot.weightKg = todaySummary.weightKg
            existingSnapshot.bodyFatPercentage = todaySummary.bodyFatPercentage
            existingSnapshot.bodyMassIndex = todaySummary.bodyMassIndex
            existingSnapshot.bodyMetricsMeasuredAt = todaySummary.bodyMetricsSyncedAt
            existingSnapshot.intakeCalories = computation.intakeCalories
            existingSnapshot.activeCalories = computation.activeCalories
            existingSnapshot.restingCalories = computation.restingCalories
            existingSnapshot.totalBurnCalories = computation.totalBurnCalories
            existingSnapshot.calorieDeficit = computation.calorieDeficit
            existingSnapshot.analysis = FatLossAnalyzer.analyze(snapshot: existingSnapshot)
            todaySummary.snapshot = existingSnapshot
        }
    }

    private func buildSummary(
        profile: UserProfile,
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
            "\(meal.mealType.title) \(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
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
        let bodyFatPercentage = healthSnapshot.bodyMetrics.bodyFatPercentage ?? todaySummary?.bodyFatPercentage
        let bodyMassIndex = healthSnapshot.bodyMetrics.bodyMassIndex ?? todaySummary?.bodyMassIndex
        let bodyMetricsMeasuredAt = healthSnapshot.bodyMetrics.measuredAt ?? todaySummary?.bodyMetricsSyncedAt

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
            bodyFatPercentage: bodyFatPercentage,
            bodyMassIndex: bodyMassIndex,
            bodyMetricsMeasuredAt: bodyMetricsMeasuredAt,
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

        let adviceText = localSummaryText(snapshot: snapshot)

        return DailySummary(
            date: Calendar.current.startOfDay(for: .now),
            intakeCalories: computation.intakeCalories,
            activeCalories: computation.activeCalories,
            restingCalories: computation.restingCalories,
            totalBurnCalories: computation.totalBurnCalories,
            calorieDeficit: computation.calorieDeficit,
            weightKg: profile.currentWeightKg,
            bodyFatPercentage: bodyFatPercentage,
            bodyMassIndex: bodyMassIndex,
            bodyMetricsSyncedAt: bodyMetricsMeasuredAt,
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
            existing.bodyFatPercentage = newSummary.bodyFatPercentage
            existing.bodyMassIndex = newSummary.bodyMassIndex
            existing.bodyMetricsSyncedAt = newSummary.bodyMetricsSyncedAt
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
