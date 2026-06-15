import Foundation
import SwiftData

// MARK: - 值类型（序列化进 JSON 列）

/// 单个训练动作。Identifiable 用于 SwiftUI 列表，编解码时排除 id（同 FoodOptionComponent 约定）。
struct TrainingExerciseItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// 组数描述，例如 "3~4 组"。
    var sets: String
    /// 次数描述，例如 "6~12 次"。
    var reps: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case name
        case sets
        case reps
        case note
    }

    init(
        id: UUID = UUID(),
        name: String,
        sets: String = "",
        reps: String = "",
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.note = note
    }
}

/// 每周某一天的安排。
struct TrainingDayPlan: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 周几，例如 "周一"。
    var dayLabel: String
    /// 当天重点，例如 "力量 A" / "休息，步数达标"。
    var focus: String
    var exercises: [TrainingExerciseItem]
    /// 有氧/步数安排，例如 "练后 15min 坡度快走"。
    var cardio: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case dayLabel
        case focus
        case exercises
        case cardio
        case note
    }

    init(
        id: UUID = UUID(),
        dayLabel: String,
        focus: String = "",
        exercises: [TrainingExerciseItem] = [],
        cardio: String = "",
        note: String = ""
    ) {
        self.id = id
        self.dayLabel = dayLabel
        self.focus = focus
        self.exercises = exercises
        self.cardio = cardio
        self.note = note
    }
}

/// 餐次示例（饮食结构里的具体一餐）。
struct TrainingMealExample: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 例如 "工作日早餐（公司）"。
    var title: String
    var content: String
    var calories: Double

    enum CodingKeys: String, CodingKey {
        case title
        case content
        case calories
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String = "",
        calories: Double = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.calories = calories
    }
}

/// 喂给 AI 的输入快照：自动获取的身体数据 + 用户手填项。
struct TrainingPlanInput: Codable {
    // 自动（来自 UserProfile / Apple 健康 / 计算）
    var gender: String
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var bodyFatPercentage: Double?
    var bmi: Double?
    var bmr: Double
    var goal: String
    /// 近 7 天训练次数。
    var recentWeeklyWorkouts: Int
    var avgDailySteps: Double?

    // 手填
    var targetWeightKg: Double?
    var targetWeeks: Int?
    var activityLevel: String
    var trainingDaysPerWeek: Int
    var trainingExperience: String
    /// 力量 / 有氧 / 混合等偏好。
    var trainingTypePreference: String
    /// 忌口、过敏、是否吃素、每天几餐等。
    var dietPreference: String
    var sleepHours: Double?
    var extraNote: String
}

/// AI 输出的完整方案。
struct TrainingPlanResult: Codable {
    /// 目标可行性评估（对应模板的"先说实话"）。
    var realisticGoalNote: String
    var bmr: Double
    var tdee: Double
    var dailyCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var macroNote: String
    var weeklySchedule: [TrainingDayPlan]
    /// 训练要点/原则。
    var trainingPrinciples: String
    /// 饮食结构与食材建议。
    var dietStructure: String
    var mealExamples: [TrainingMealExample]
    /// 监测与调整建议。
    var monitoringAdvice: String
    var summary: String
}

// MARK: - SwiftData 模型

@Model
final class TrainingPlan {
    var id: UUID
    var title: String
    var goalRaw: String = FitnessGoal.fatLoss.rawValue
    /// 用户输入快照（JSON 列，透明编解码）。
    var inputJSON: String
    /// AI 生成结果（JSON 列，透明编解码）。
    var resultJSON: String
    // 列表卡片用的反规范化标量，避免每次解码 resultJSON。
    var dailyCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var trainingDaysPerWeek: Int
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        goal: FitnessGoal = .fatLoss,
        input: TrainingPlanInput? = nil,
        result: TrainingPlanResult? = nil,
        dailyCalories: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        trainingDaysPerWeek: Int = 0,
        summary: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.goalRaw = goal.rawValue
        self.inputJSON = Self.encode(input)
        self.resultJSON = Self.encode(result)
        self.dailyCalories = dailyCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var goal: FitnessGoal {
        get { FitnessGoal(rawValue: goalRaw) ?? .fatLoss }
        set { goalRaw = newValue.rawValue }
    }

    var input: TrainingPlanInput? {
        get { Self.decode(TrainingPlanInput.self, from: inputJSON) }
        set { inputJSON = Self.encode(newValue) }
    }

    var result: TrainingPlanResult? {
        get { Self.decode(TrainingPlanResult.self, from: resultJSON) }
        set { resultJSON = Self.encode(newValue) }
    }

    /// 训练计划产出的目标缺口 = TDEE − 每日目标热量。供今日仪表盘与总结页对照达标线使用。
    /// 与每日实际热量差（BMR + 活动 − 摄入）口径不同，仅作目标线。
    var targetDailyDeficitKcal: Double {
        guard let tdee = result?.tdee, tdee > 0 else { return 0 }
        return max(0, tdee - dailyCalories)
    }

    var macroEnergyTotal: Double {
        proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
    }

    var proteinEnergyRatio: Double {
        guard macroEnergyTotal > 0 else { return 0 }
        return proteinGrams * 4 / macroEnergyTotal
    }

    var carbsEnergyRatio: Double {
        guard macroEnergyTotal > 0 else { return 0 }
        return carbsGrams * 4 / macroEnergyTotal
    }

    var fatEnergyRatio: Double {
        guard macroEnergyTotal > 0 else { return 0 }
        return fatGrams * 9 / macroEnergyTotal
    }

    private static func encode<T: Encodable>(_ value: T?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8), !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
