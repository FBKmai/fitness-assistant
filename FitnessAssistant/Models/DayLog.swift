import Foundation
import SwiftData

/// 「某一天」的单一记录——Phase B 合并自 `DailyCheckIn`（身体打卡）与 `DailySummary`（热量归档+AI建议）。
///
/// 每个自然日唯一一条。体重/体脂/BMI/睡眠/饮水等身体数据在此**物理单源**，
/// 不再分散到三张表；热量与营养是当日缓存（由 `DayMetrics` 计算后写入）；
/// `adviceText`/`snapshotJSON`/`generatedAt` 是当日 AI 建议归档（`generatedAt == nil` 表示尚未生成）。
@Model
final class DayLog {
    /// 自然日（startOfDay）。
    var date: Date
    // MARK: 身体数据
    var weightKg: Double = 0
    var bodyFatPercentage: Double? = nil
    var bodyMassIndex: Double? = nil
    var bodyMetricsSyncedAt: Date? = nil
    var sleepHours: Double? = nil
    var waterMl: Double? = nil
    var hungerLevel: Int? = nil
    var mood: String = ""
    var symptoms: String = ""
    var note: String = ""
    // MARK: 当日热量与营养（缓存，由 DayMetrics 计算后写入）
    var intakeCalories: Double = 0
    var activeCalories: Double = 0
    var restingCalories: Double = 0
    var totalBurnCalories: Double = 0
    var calorieDeficit: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var vegetableGrams: Double = 0
    /// `healthKit` 表示读取到 Apple 健康基础能量，`bmrEstimate` 表示使用公式估算。
    var restingEnergySourceRaw: String = "bmrEstimate"
    var restingHeartRate: Double? = nil
    var averageHeartRate: Double? = nil
    var safetyWarningsJSON: String = "[]"
    var reportIsStale: Bool = false
    // MARK: 当日 AI 建议归档
    var adviceText: String = ""
    var snapshotJSON: String = "{}"
    /// 当日总结/建议生成时间；nil 表示当天只有身体数据、尚未生成总结。
    var generatedAt: Date? = nil
    var createdAt: Date
    var updatedAt: Date

    init(
        date: Date = Calendar.current.startOfDay(for: .now),
        weightKg: Double = 0,
        bodyFatPercentage: Double? = nil,
        bodyMassIndex: Double? = nil,
        bodyMetricsSyncedAt: Date? = nil,
        sleepHours: Double? = nil,
        waterMl: Double? = nil,
        hungerLevel: Int? = nil,
        mood: String = "",
        symptoms: String = "",
        note: String = "",
        intakeCalories: Double = 0,
        activeCalories: Double = 0,
        restingCalories: Double = 0,
        totalBurnCalories: Double = 0,
        calorieDeficit: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        vegetableGrams: Double = 0,
        restingEnergySourceRaw: String = "bmrEstimate",
        restingHeartRate: Double? = nil,
        averageHeartRate: Double? = nil,
        safetyWarnings: [String] = [],
        reportIsStale: Bool = false,
        adviceText: String = "",
        snapshot: DailySnapshot? = nil,
        generatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyMassIndex = bodyMassIndex
        self.bodyMetricsSyncedAt = bodyMetricsSyncedAt
        self.sleepHours = sleepHours
        self.waterMl = waterMl
        self.hungerLevel = hungerLevel
        self.mood = mood
        self.symptoms = symptoms
        self.note = note
        self.intakeCalories = intakeCalories
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.totalBurnCalories = totalBurnCalories
        self.calorieDeficit = calorieDeficit
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.vegetableGrams = vegetableGrams
        self.restingEnergySourceRaw = restingEnergySourceRaw
        self.restingHeartRate = restingHeartRate
        self.averageHeartRate = averageHeartRate
        self.safetyWarningsJSON = Self.encodeStrings(safetyWarnings)
        self.reportIsStale = reportIsStale
        self.adviceText = adviceText
        self.snapshotJSON = Self.encodeSnapshot(snapshot)
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 是否已生成当日总结（用于趋势/总结页只展示有总结的日子）。
    var hasSummary: Bool { generatedAt != nil }

    /// 采纳教练建议中的身体打卡字段（与原 DailyCheckIn.apply 同口径）。
    func apply(_ suggestion: CoachSuggestedRecord) {
        if let weightKg = suggestion.weightKg { self.weightKg = weightKg }
        if let bodyFatPercentage = suggestion.bodyFatPercentage { self.bodyFatPercentage = bodyFatPercentage }
        if let bodyMassIndex = suggestion.bodyMassIndex { self.bodyMassIndex = bodyMassIndex }
        if let sleepHours = suggestion.sleepHours { self.sleepHours = sleepHours }
        if let waterMl = suggestion.waterMl { self.waterMl = waterMl }
        if let hungerLevel = suggestion.hungerLevel { self.hungerLevel = hungerLevel }
        if let mood = suggestion.mood { self.mood = mood }
        if let symptoms = suggestion.symptoms { self.symptoms = symptoms }
        if !suggestion.note.isEmpty { note = suggestion.note }
        updatedAt = .now
    }

    var snapshot: DailySnapshot? {
        get { Self.decodeSnapshot(snapshotJSON) }
        set { snapshotJSON = Self.encodeSnapshot(newValue) }
    }

    var safetyWarnings: [String] {
        get { Self.decodeStrings(safetyWarningsJSON) }
        set { safetyWarningsJSON = Self.encodeStrings(newValue) }
    }

    var restingEnergyIsEstimated: Bool {
        restingEnergySourceRaw != "healthKit"
    }

    private static func encodeSnapshot(_ snapshot: DailySnapshot?) -> String {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeSnapshot(_ json: String) -> DailySnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DailySnapshot.self, from: data)
    }

    private static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
