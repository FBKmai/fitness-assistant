import Foundation
import SwiftData

/// 近 7 天趋势中的单日数据点。
struct DayTrend: Codable {
    var date: Date
    var intakeCalories: Double
    var calorieDeficit: Double
    var weightKg: Double?
}

struct DailySnapshot: Codable {
    var date: Date
    var goal: String
    var targetDailyDeficitKcal: Double
    // 身体数据
    var heightCm: Double
    var weightKg: Double
    var bodyFatPercentage: Double? = nil
    var bodyMassIndex: Double? = nil
    var bodyMetricsMeasuredAt: Date? = nil
    var gender: String
    var age: Int
    var bmr: Double
    // 当日热量
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
    // 当日三大营养素合计（克）
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var averageMealConfidence: Double?
    var unconfirmedMealCount: Int?
    var manualActiveCalories: Double?
    var meals: [String]
    var workouts: [String]
    // 近 7 天趋势（不含今天）
    var recentDays: [DayTrend]
    var analysis: FatLossAnalysis?
}

struct DietCoachSnapshot: Codable {
    /// 当前时间，让 AI 判断现在是哪一餐。
    var requestedAt: Date
    var goal: String
    var targetDailyDeficitKcal: Double
    var heightCm: Double
    var weightKg: Double
    var bodyFatPercentage: Double? = nil
    var bodyMassIndex: Double? = nil
    var bodyMetricsMeasuredAt: Date? = nil
    var gender: String
    var age: Int
    var bmr: Double
    var todayIntakeCalories: Double
    var todayActiveCalories: Double
    var todayRestingCalories: Double
    var todayTotalBurnCalories: Double
    var todayCalorieDeficit: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var averageMealConfidence: Double?
    var todayMeals: [String]
    var todayWorkouts: [String]
    /// 最近几天的饮食记录（不含今天），辅助判断。
    var recentMeals: [String]
    /// 最近几天的训练/活动消耗（不含今天）。
    var recentWorkouts: [String]
    var selectedFoodOptions: [FoodOptionSnapshot]
    var recentDays: [DayTrend]
    var analysis: FatLossAnalysis
}

/// 「问 AI 怎么吃」多轮对话中的一条消息。
struct DietCoachTurn: Codable, Identifiable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct DailyAdvice: Codable {
    var summary: String
    var todayMealAdvice: String?
    var snackAdvice: String?
    var tomorrowDietAdvice: String
    var tomorrowExerciseAdvice: String
    var recoveryAdvice: String
}

@Model
final class DailySummary {
    var id: UUID
    var date: Date
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
    // 当日身体指标与三大营养素（克），用于趋势图。新增属性带内联默认值便于 SwiftData 轻量迁移。
    var weightKg: Double = 0
    var bodyFatPercentage: Double? = nil
    var bodyMassIndex: Double? = nil
    var bodyMetricsSyncedAt: Date? = nil
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var adviceText: String
    var snapshotJSON: String
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        intakeCalories: Double = 0,
        activeCalories: Double = 0,
        restingCalories: Double = 0,
        totalBurnCalories: Double = 0,
        calorieDeficit: Double = 0,
        weightKg: Double = 0,
        bodyFatPercentage: Double? = nil,
        bodyMassIndex: Double? = nil,
        bodyMetricsSyncedAt: Date? = nil,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        adviceText: String = "",
        snapshot: DailySnapshot? = nil,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.intakeCalories = intakeCalories
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.totalBurnCalories = totalBurnCalories
        self.calorieDeficit = calorieDeficit
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyMassIndex = bodyMassIndex
        self.bodyMetricsSyncedAt = bodyMetricsSyncedAt
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.adviceText = adviceText
        self.snapshotJSON = Self.encodeSnapshot(snapshot)
        self.generatedAt = generatedAt
    }

    var snapshot: DailySnapshot? {
        get { Self.decodeSnapshot(snapshotJSON) }
        set { snapshotJSON = Self.encodeSnapshot(newValue) }
    }

    private static func encodeSnapshot(_ snapshot: DailySnapshot?) -> String {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeSnapshot(_ json: String) -> DailySnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DailySnapshot.self, from: data)
    }
}
