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

    /// 由 MainTabView 注入，用于空态快捷按钮切换到「饮食」「运动」Tab。
    var selection: Binding<Int>? = nil

    private var profile: UserProfile? { profiles.first }
    private var aiSettings: AISettings? { settings.first }
    private var todayMeals: [MealEntry] { meals.filter { Calendar.current.isDateInToday($0.date) } }
    private var todayExercises: [ExerciseEntry] { exercises.filter { Calendar.current.isDateInToday($0.date) } }
    private var todaySummary: DailySummary? { summaries.first { Calendar.current.isDateInToday($0.date) } }

    private var intakeCalories: Double {
        todayMeals.filter(\.isConfirmed).reduce(0) { $0 + $1.totalCalories }
    }

    private var manualActiveCalories: Double {
        todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
    }

    private var deficit: Double { todaySummary?.calorieDeficit ?? 0 }
    private var deficitTarget: Double { profile?.targetDailyDeficitKcal ?? 0 }
    private var deficitReached: Bool { deficitTarget > 0 && deficit >= deficitTarget }
    private var deficitTint: Color { deficitReached ? .deficitReached : .deficitShort }
    private var hasTodayRecords: Bool { !todayMeals.isEmpty || !todayExercises.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppMetrics.tileSpacing) {
                        MetricTile(title: "摄入", value: intakeCalories.kcalValue, systemImage: "fork.knife")
                        MetricTile(title: "热量差", value: deficit.signedKcalValue, systemImage: "plusminus", highlighted: true, tint: deficitTint)
                    }
                    HStack(spacing: AppMetrics.tileSpacing) {
                        MetricTile(title: "活动", value: (todaySummary?.activeCalories ?? manualActiveCalories).kcalValue, systemImage: "flame")
                        MetricTile(title: "基础", value: (todaySummary?.restingCalories ?? profile.map { CalorieCalculator.bmr(profile: $0) } ?? 0).kcalValue, systemImage: "bed.double")
                    }
                    if deficitTarget > 0 {
                        MetricProgressBar(title: "距每日缺口目标 \(Int(deficitTarget)) kcal", current: deficit, target: deficitTarget, tint: deficitTint)
                            .padding(.top, 6)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

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
                    if let todaySummary {
                        LabeledContent("建议生成", value: DateFormatter.shortTime.string(from: todaySummary.generatedAt))
                    } else {
                        LabeledContent("建议生成", value: "未生成")
                    }
                }

                if let advice = todaySummary?.adviceText, !advice.isEmpty {
                    Section("今日总结与明日建议") {
                        Text(advice)
                            .font(.body)
                            .textSelection(.enabled)
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
            }
            .navigationTitle("今日")
            .task {
                if todaySummary == nil {
                    await syncAndGenerateSummary(silent: true)
                }
            }
        }
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
        if let bodyMassKg = snapshot.bodyMassKg {
            profile.currentWeightKg = bodyMassKg
            profile.updatedAt = .now
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
            healthKitRestingCalories: healthSnapshot.basalEnergyKcal,
            profile: profile
        )

        let mealTexts = confirmedMeals.map { meal in
            "\(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText)"
        }
        let workoutTexts = todayExercises.map { exercise in
            "\(exercise.source.title) \(exercise.workoutType) \(exercise.activeCalories.kcalText)"
        }
        let snapshot = DailySnapshot(
            date: .now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: profile.targetDailyDeficitKcal,
            intakeCalories: computation.intakeCalories,
            activeCalories: computation.activeCalories,
            restingCalories: computation.restingCalories,
            totalBurnCalories: computation.totalBurnCalories,
            calorieDeficit: computation.calorieDeficit,
            meals: mealTexts,
            workouts: workoutTexts
        )

        let adviceText: String
        do {
            let advice = try await aiClient.generateDailyAdvice(snapshot: snapshot, settings: settings)
            adviceText = [
                advice.summary,
                "饮食：\(advice.tomorrowDietAdvice)",
                "运动：\(advice.tomorrowExerciseAdvice)",
                "恢复：\(advice.recoveryAdvice)"
            ].joined(separator: "\n\n")
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
            existing.adviceText = newSummary.adviceText
            existing.snapshot = newSummary.snapshot
            existing.generatedAt = .now
        } else {
            modelContext.insert(newSummary)
        }
    }

    private func fallbackAdvice(snapshot: DailySnapshot, error: Error) -> String {
        let gap = snapshot.calorieDeficit
        let trend = gap >= snapshot.targetDailyDeficitKcal ? "今天热量缺口已达到目标。" : "今天热量缺口还没有达到目标。"
        return """
        \(trend)

        明天饮食：优先保证蛋白质和蔬菜，主食按训练量调整，避免因为缺口不足而极端节食。

        明天运动：保持中等强度活动，如果今天训练量较低，可以增加 30-45 分钟快走或力量训练。

        AI 建议暂未生成：\(error.localizedDescription)
        """
    }
}
