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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MetricTile(title: "摄入", value: intakeCalories.kcalText, systemImage: "fork.knife")
                        MetricTile(title: "热量差", value: (todaySummary?.calorieDeficit ?? 0).signedKcalText, systemImage: "plusminus")
                    }
                    HStack(spacing: 12) {
                        MetricTile(title: "活动", value: (todaySummary?.activeCalories ?? manualActiveCalories).kcalText, systemImage: "flame")
                        MetricTile(title: "基础", value: (todaySummary?.restingCalories ?? profile.map { CalorieCalculator.bmr(profile: $0) } ?? 0).kcalText, systemImage: "bed.double")
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

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
                        Label(isWorking ? "处理中" : "同步并生成今日建议", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isWorking)

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

private struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Double {
    var kcalText: String { "\(Int(rounded())) kcal" }
    var signedKcalText: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue) kcal" : "\(roundedValue) kcal"
    }
}
