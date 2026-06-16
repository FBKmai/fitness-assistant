import Foundation
import Observation
import SwiftData

/// Phase C：集中「写入 + HealthKit 同步 + 生成今日总结」的单一编排入口。
///
/// View 通过它做写入/同步，避免把编排逻辑散落、重复在各视图里；读仍走 SwiftData `@Query`
/// （同一 mainContext，写入后自动反映到 UI），聚合仍走 `DayMetrics`。
/// 依赖在 `configure` 时注入，避免 App/View 初始化期触发 @MainActor 隔离问题。
@MainActor
@Observable
final class DataStore {
    private(set) var isWorking = false
    var statusMessage = "打开后可同步健康数据并刷新今日仪表盘"

    @ObservationIgnored private var context: ModelContext? = nil
    @ObservationIgnored private var health: HealthKitService? = nil

    nonisolated init() {}

    /// 注入 mainContext 与 HealthKit 服务（幂等）。使用方在 onAppear/task 调用一次即可。
    func configure(context: ModelContext, health: HealthKitService) {
        if self.context == nil { self.context = context }
        if self.health == nil { self.health = health }
    }

    var healthAuthorizationDescription: String {
        health?.authorizationStatusDescription ?? "未授权"
    }

    // MARK: - 体重单写入口

    @discardableResult
    func recordWeight(_ kg: Double, on date: Date = .now, profile: UserProfile, dayLogs: [DayLog]) -> Bool {
        guard let context, (30...250).contains(kg) else { return false }
        WeightWriter.record(kg, on: date, profile: profile, context: context, dayLogs: dayLogs)
        do {
            try context.save()
            return true
        } catch {
            AppLog.error("保存体重失败：\(error.localizedDescription)", category: "数据")
            return false
        }
    }

    // MARK: - HealthKit 同步（唯一入口）

    /// 只同步身体数据与运动条目，不生成总结。
    func syncHealthOnly(profile: UserProfile, exercises: [ExerciseEntry], dayLogs: [DayLog], silent: Bool = false) async {
        guard let context, let health, !isWorking else { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 Apple 健康身体数据..." }
        defer { isWorking = false }

        do {
            try? await health.requestAuthorization()
            let snapshot = try await health.fetchSnapshot(for: .now)
            upsertHealthEntries(snapshot, profile: profile, exercises: exercises, context: context)
            refreshTodayLogFromHealth(snapshot, dayLogs: dayLogs, context: context)
            try context.save()
            if !silent {
                statusMessage = snapshot.bodyMetrics.hasAnyValue
                    ? "已同步 Apple 健康身体数据 \(DateFormatter.shortTime.string(from: .now))"
                    : "Apple 健康今天还没有体脂秤数据，可先手动保存体重。"
            }
        } catch {
            AppLog.error("同步 Apple 健康数据失败：\(error.localizedDescription)", category: "今日")
            if !silent { statusMessage = error.localizedDescription }
        }
    }

    /// 同步 + 生成（或刷新）当天 DayLog 的热量总结。
    func syncAndGenerateToday(
        profile: UserProfile,
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        dayLogs: [DayLog],
        trainingPlans: [TrainingPlan],
        silent: Bool = false
    ) async {
        guard let context, let health, !isWorking else { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 HealthKit..." }
        defer { isWorking = false }

        do {
            try? await health.requestAuthorization()
            let snapshot = try await health.fetchSnapshot(for: .now)
            upsertHealthEntries(snapshot, profile: profile, exercises: exercises, context: context)
            refreshTodayLogFromHealth(snapshot, dayLogs: dayLogs, context: context)
            generateTodaySummary(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, trainingPlans: trainingPlans, healthSnapshot: snapshot, context: context)
            try context.save()
            statusMessage = "已更新 \(DateFormatter.shortTime.string(from: .now))"
        } catch {
            AppLog.error("同步并生成今日总结失败：\(error.localizedDescription)", category: "今日")
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - 私有编排

    private func upsertTodayLog(_ dayLogs: [DayLog], context: ModelContext) -> DayLog {
        if let today = dayLogs.first(where: { Calendar.current.isDateInToday($0.date) }) {
            return today
        }
        let log = DayLog(date: Calendar.current.startOfDay(for: .now))
        context.insert(log)
        return log
    }

    private func upsertHealthEntries(_ snapshot: HealthSnapshot, profile: UserProfile, exercises: [ExerciseEntry], context: ModelContext) {
        if let weight = snapshot.bodyMetrics.weightKg, (30...250).contains(weight) {
            profile.currentWeightKg = weight
            profile.updatedAt = .now
        }

        let aggregateID = "daily-\(snapshot.date.dayKey)"
        if let aggregate = exercises.first(where: { $0.healthKitWorkoutID == aggregateID }) {
            aggregate.date = snapshot.date
            aggregate.workoutType = "每日活动合计"
            aggregate.activeCalories = snapshot.activeEnergyKcal
            aggregate.steps = snapshot.steps
        } else {
            context.insert(ExerciseEntry(
                date: snapshot.date,
                source: .healthKit,
                workoutType: "每日活动合计",
                activeCalories: snapshot.activeEnergyKcal,
                steps: snapshot.steps,
                healthKitWorkoutID: aggregateID
            ))
        }

        for workout in snapshot.workouts {
            if let existing = exercises.first(where: { $0.healthKitWorkoutID == workout.id }) {
                existing.date = workout.startDate
                existing.workoutType = workout.activityName
                existing.durationMinutes = workout.durationMinutes
                existing.activeCalories = workout.activeCalories
            } else {
                context.insert(ExerciseEntry(
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

    private func refreshTodayLogFromHealth(_ snapshot: HealthSnapshot, dayLogs: [DayLog], context: ModelContext) {
        guard snapshot.bodyMetrics.hasAnyValue || snapshot.sleepHours != nil else { return }
        let log = upsertTodayLog(dayLogs, context: context)
        if let weight = snapshot.bodyMetrics.weightKg, (30...250).contains(weight) {
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

    private func generateTodaySummary(
        profile: UserProfile,
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        dayLogs: [DayLog],
        trainingPlans: [TrainingPlan],
        healthSnapshot: HealthSnapshot?,
        context: ModelContext
    ) {
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
        let log = upsertTodayLog(dayLogs, context: context)
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
        log.adviceText = Self.localSummaryText(snapshot: snapshot)
        log.snapshot = snapshot
        log.generatedAt = .now
        log.updatedAt = .now
    }

    /// 「今日数据摘要」的本地文案（仪表盘自身内容，非 AI 兜底）。
    static func localSummaryText(snapshot: DailySnapshot) -> String {
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
