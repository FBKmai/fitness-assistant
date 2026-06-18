import Foundation
import SwiftData

/// Phase B 一次性回填：把旧的 `DailySummary` + `DailyCheckIn` 按自然日合并进 `DayLog`。
///
/// 用 UserDefaults 标记保证只跑一次；幂等（已存在的 DayLog 直接复用、就地补字段），不丢数据。
/// 旧表本版仍保留在 schema 中（仅供本次读取），新数据一律写 DayLog，旧表下一版再移除。
enum DayLogMigration {
    private static let flagKey = "dayLogMigratedV1"

    @MainActor
    static func migrateIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let summaries = (try? context.fetch(FetchDescriptor<DailySummary>())) ?? []
        let checkIns = (try? context.fetch(FetchDescriptor<DailyCheckIn>())) ?? []
        if summaries.isEmpty && checkIns.isEmpty {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        let calendar = Calendar.current
        let existing = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        var byDay: [Date: DayLog] = [:]
        for log in existing { byDay[calendar.startOfDay(for: log.date)] = log }

        func logFor(_ date: Date) -> DayLog {
            let day = calendar.startOfDay(for: date)
            if let log = byDay[day] { return log }
            let log = DayLog(date: day)
            context.insert(log)
            byDay[day] = log
            return log
        }

        // 先并入热量/营养/AI 建议（来自 DailySummary）。
        for summary in summaries {
            let log = logFor(summary.date)
            log.intakeCalories = summary.intakeCalories
            log.activeCalories = summary.activeCalories
            log.restingCalories = summary.restingCalories
            log.totalBurnCalories = summary.totalBurnCalories
            log.calorieDeficit = summary.calorieDeficit
            log.proteinGrams = summary.proteinGrams
            log.carbsGrams = summary.carbsGrams
            log.fatGrams = summary.fatGrams
            if summary.weightKg > 0 { log.weightKg = summary.weightKg }
            if let v = summary.bodyFatPercentage { log.bodyFatPercentage = v }
            if let v = summary.bodyMassIndex { log.bodyMassIndex = v }
            if let v = summary.bodyMetricsSyncedAt { log.bodyMetricsSyncedAt = v }
            log.adviceText = summary.adviceText
            log.snapshotJSON = summary.snapshotJSON
            log.generatedAt = summary.generatedAt
            log.updatedAt = .now
        }

        // 再并入身体打卡（来自 DailyCheckIn），打卡的体征数据优先级更高（更贴近用户当天实测）。
        for checkIn in checkIns {
            let log = logFor(checkIn.date)
            if checkIn.weightKg > 0 { log.weightKg = checkIn.weightKg }
            if let v = checkIn.bodyFatPercentage { log.bodyFatPercentage = v }
            if let v = checkIn.bodyMassIndex { log.bodyMassIndex = v }
            if let v = checkIn.sleepHours { log.sleepHours = v }
            if let v = checkIn.waterMl { log.waterMl = v }
            if let v = checkIn.hungerLevel { log.hungerLevel = v }
            if !checkIn.mood.isEmpty { log.mood = checkIn.mood }
            if !checkIn.symptoms.isEmpty { log.symptoms = checkIn.symptoms }
            if !checkIn.note.isEmpty { log.note = checkIn.note }
            log.updatedAt = .now
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            AppLog.error("DayLog 迁移失败：\(error.localizedDescription)", category: "迁移")
            // 不置标记，下次启动重试。
        }
    }
}

/// 新版结构化数据迁移：保留旧 ExerciseEntry，同时为非日聚合运动创建 TrainingSession。
enum StructuredDataMigration {
    private static let flagKey = "structuredDataMigratedV2"

    @MainActor
    static func migrateIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let exercises = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>())) ?? []
        let oldCoachSessions = (try? context.fetch(FetchDescriptor<CoachChatSession>())) ?? []
        var existingHealthIDs = Set(sessions.compactMap(\.healthKitWorkoutID))
        var existingExerciseIDs = Set(sessions.map(\.id))

        for exercise in exercises {
            let isDailyAggregate = exercise.source == .healthKit
                && (exercise.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
            guard !isDailyAggregate else { continue }
            if let healthID = exercise.healthKitWorkoutID, existingHealthIDs.contains(healthID) {
                continue
            }
            if let sessionID = exercise.trainingSessionID, existingExerciseIDs.contains(sessionID) {
                continue
            }

            let session = TrainingSession(
                date: exercise.date,
                title: exercise.workoutType.isEmpty ? "训练" : exercise.workoutType,
                source: exercise.source,
                durationMinutes: exercise.durationMinutes,
                activeCalories: exercise.activeCalories,
                healthKitWorkoutID: exercise.healthKitWorkoutID,
                averageHeartRate: exercise.averageHeartRate,
                maxHeartRate: exercise.maxHeartRate,
                note: "由旧运动记录迁移"
            )
            context.insert(session)
            exercise.trainingSessionID = session.id
            existingExerciseIDs.insert(session.id)
            if let healthID = session.healthKitWorkoutID {
                existingHealthIDs.insert(healthID)
            }
        }

        // 旧教练对话保留在数据库中供回滚，但不进入新版教练界面与上下文。
        for session in oldCoachSessions {
            session.isArchived = true
            session.carryoverEnabled = false
            session.updatedAt = .now
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            AppLog.error("结构化训练迁移失败：\(error.localizedDescription)", category: "迁移")
        }
    }
}
