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
    @ObservationIgnored private let healthHistorySyncKey = "healthHistoryLastSyncV2"

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
    func recordWeight(
        _ kg: Double,
        on date: Date = .now,
        profile: UserProfile,
        dayLogs: [DayLog],
        reason: String = "用户手动记录",
        source: CorrectionSource = .user
    ) -> Bool {
        guard let context, (30...250).contains(kg) else { return false }
        let existing = dayLogs.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let oldValue = existing?.weightKg ?? 0
        let log = WeightWriter.record(kg, on: date, profile: profile, context: context, dayLogs: dayLogs)
        if oldValue > 0, abs(oldValue - kg) > 0.001 {
            context.insert(DataCorrection(
                entityType: "DayLog",
                entityID: Calendar.current.startOfDay(for: date).dayKey,
                fieldName: "weightKg",
                oldValue: String(oldValue),
                newValue: String(kg),
                effectiveDate: Calendar.current.startOfDay(for: date),
                reason: reason,
                source: source
            ))
            log.reportIsStale = true
        }
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
    func syncHealthOnly(
        profile: UserProfile,
        exercises: [ExerciseEntry],
        dayLogs: [DayLog],
        trainingSessions: [TrainingSession] = [],
        corrections: [DataCorrection] = [],
        silent: Bool = false
    ) async {
        guard let context, let health, !isWorking else { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 Apple 健康身体数据..." }
        defer { isWorking = false }

        do {
            try? await health.requestAuthorization()
            let activeCorrections = mergedActiveCorrections(corrections, context: context)
            let snapshots = try await healthSnapshotsForIncrementalSync(health)
            for snapshot in snapshots {
                upsertHealthEntries(
                    snapshot,
                    profile: profile,
                    exercises: exercises,
                    trainingSessions: trainingSessions,
                    corrections: activeCorrections,
                    context: context
                )
                refreshDayLogFromHealth(snapshot, dayLogs: dayLogs, corrections: activeCorrections, context: context)
            }
            try context.save()
            UserDefaults.standard.set(Date.now, forKey: healthHistorySyncKey)
            let snapshot = snapshots.last
            if !silent {
                statusMessage = snapshot?.bodyMetrics.hasAnyValue == true
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
        trainingSessions: [TrainingSession] = [],
        corrections: [DataCorrection] = [],
        silent: Bool = false
    ) async {
        guard let context, let health, !isWorking else { return }
        isWorking = true
        if !silent { statusMessage = "正在同步 HealthKit..." }
        defer { isWorking = false }

        do {
            try? await health.requestAuthorization()
            let activeCorrections = mergedActiveCorrections(corrections, context: context)
            let snapshot = try await health.fetchSnapshot(for: .now)
            upsertHealthEntries(
                snapshot,
                profile: profile,
                exercises: exercises,
                trainingSessions: trainingSessions,
                corrections: activeCorrections,
                context: context
            )
            refreshDayLogFromHealth(snapshot, dayLogs: dayLogs, corrections: activeCorrections, context: context)
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

    private func upsertHealthEntries(
        _ snapshot: HealthSnapshot,
        profile: UserProfile,
        exercises: [ExerciseEntry],
        trainingSessions: [TrainingSession],
        corrections: [DataCorrection],
        context: ModelContext
    ) {
        let currentWeightIsCorrected = corrections.contains {
            $0.isActive
                && $0.entityType == "DayLog"
                && $0.fieldName == "weightKg"
                && Calendar.current.isDate($0.effectiveDate, inSameDayAs: snapshot.date)
        }
        if !currentWeightIsCorrected,
           Calendar.current.isDateInToday(snapshot.date),
           let weight = snapshot.bodyMetrics.weightKg,
           (30...250).contains(weight) {
            profile.currentWeightKg = weight
            profile.updatedAt = .now
        }

        let aggregateID = "daily-\(snapshot.date.dayKey)"
        if let aggregate = exercises.first(where: { $0.healthKitWorkoutID == aggregateID }) {
            aggregate.date = snapshot.date
            aggregate.workoutType = "每日活动合计"
            aggregate.activeCalories = snapshot.activeEnergyKcal
            aggregate.steps = snapshot.steps
            aggregate.averageHeartRate = snapshot.averageHeartRate
        } else {
            context.insert(ExerciseEntry(
                date: snapshot.date,
                source: .healthKit,
                workoutType: "每日活动合计",
                activeCalories: snapshot.activeEnergyKcal,
                steps: snapshot.steps,
                healthKitWorkoutID: aggregateID,
                averageHeartRate: snapshot.averageHeartRate
            ))
        }

        for workout in snapshot.workouts {
            if let existing = exercises.first(where: { $0.healthKitWorkoutID == workout.id }) {
                existing.date = workout.startDate
                existing.workoutType = workout.activityName
                existing.durationMinutes = workout.durationMinutes
                existing.activeCalories = workout.activeCalories
                existing.averageHeartRate = workout.averageHeartRate
                existing.maxHeartRate = workout.maxHeartRate
            } else {
                context.insert(ExerciseEntry(
                    date: workout.startDate,
                    source: .healthKit,
                    workoutType: workout.activityName,
                    durationMinutes: workout.durationMinutes,
                    activeCalories: workout.activeCalories,
                    healthKitWorkoutID: workout.id,
                    averageHeartRate: workout.averageHeartRate,
                    maxHeartRate: workout.maxHeartRate
                ))
            }

            if let session = trainingSessions.first(where: { $0.healthKitWorkoutID == workout.id }) {
                session.date = workout.startDate
                session.title = workout.activityName
                session.durationMinutes = workout.durationMinutes
                session.activeCalories = workout.activeCalories
                session.averageHeartRate = workout.averageHeartRate
                session.maxHeartRate = workout.maxHeartRate
                session.updatedAt = .now
            } else {
                context.insert(TrainingSession(
                    date: workout.startDate,
                    title: workout.activityName,
                    source: .healthKit,
                    durationMinutes: workout.durationMinutes,
                    activeCalories: workout.activeCalories,
                    healthKitWorkoutID: workout.id,
                    averageHeartRate: workout.averageHeartRate,
                    maxHeartRate: workout.maxHeartRate
                ))
            }
        }
    }

    private func refreshDayLogFromHealth(
        _ snapshot: HealthSnapshot,
        dayLogs: [DayLog],
        corrections: [DataCorrection],
        context: ModelContext
    ) {
        let hasEnergy = (snapshot.basalEnergyKcal ?? 0) > 0 || snapshot.activeEnergyKcal > 0
        guard snapshot.bodyMetrics.hasAnyValue || snapshot.sleepHours != nil || hasEnergy else { return }
        let day = Calendar.current.startOfDay(for: snapshot.date)
        let log = dayLogs.first { Calendar.current.isDate($0.date, inSameDayAs: day) } ?? {
            let value = DayLog(date: day)
            context.insert(value)
            return value
        }()
        let weightIsCorrected = corrections.contains {
            $0.isActive
                && $0.entityType == "DayLog"
                && $0.fieldName == "weightKg"
                && Calendar.current.isDate($0.effectiveDate, inSameDayAs: day)
        }
        if !weightIsCorrected,
           let weight = snapshot.bodyMetrics.weightKg,
           (30...250).contains(weight) {
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
        if let basal = snapshot.basalEnergyKcal, basal > 0 {
            log.restingCalories = basal
            log.restingEnergySourceRaw = RestingEnergySource.healthKit.rawValue
        }
        log.activeCalories = max(0, snapshot.activeEnergyKcal)
        log.averageHeartRate = snapshot.averageHeartRate
        log.restingHeartRate = snapshot.restingHeartRate
        if snapshot.bodyMetrics.hasAnyValue {
            log.bodyMetricsSyncedAt = snapshot.bodyMetrics.measuredAt ?? .now
        }
        log.updatedAt = .now
    }

    private func healthSnapshotsForIncrementalSync(_ health: HealthKitService) async throws -> [HealthSnapshot] {
        let calendar = Calendar.current
        let lastSync = UserDefaults.standard.object(forKey: healthHistorySyncKey) as? Date
        let fallback = calendar.date(byAdding: .day, value: -89, to: .now) ?? .now
        let start = lastSync.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? fallback
        return try await health.fetchSnapshots(from: start, through: .now)
    }

    private func mergedActiveCorrections(
        _ provided: [DataCorrection],
        context: ModelContext
    ) -> [DataCorrection] {
        let stored = (try? context.fetch(FetchDescriptor<DataCorrection>())) ?? []
        var valuesByID: [UUID: DataCorrection] = [:]
        for correction in provided + stored where correction.isActive {
            valuesByID[correction.id] = correction
        }
        return Array(valuesByID.values)
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
        log.fiberGrams = metrics.fiberGrams
        log.vegetableGrams = metrics.vegetableGrams
        log.restingEnergySourceRaw = metrics.restingEnergySource.rawValue
        log.averageHeartRate = healthSnapshot?.averageHeartRate ?? log.averageHeartRate
        log.restingHeartRate = healthSnapshot?.restingHeartRate ?? log.restingHeartRate
        log.safetyWarnings = TrendSafetyAnalyzer.alerts(
            dayLogs: dayLogs,
            currentWeightKg: metrics.weightKg ?? profile.currentWeightKg
        ).map(\.message)
        if let weight = metrics.weightKg { log.weightKg = weight }
        if let bodyFat = metrics.bodyFatPercentage { log.bodyFatPercentage = bodyFat }
        if let bmi = metrics.bodyMassIndex { log.bodyMassIndex = bmi }
        if let measuredAt = metrics.bodyMetricsMeasuredAt { log.bodyMetricsSyncedAt = measuredAt }
        log.adviceText = Self.localSummaryText(snapshot: snapshot)
        log.snapshot = snapshot
        log.generatedAt = .now
        log.reportIsStale = false
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
