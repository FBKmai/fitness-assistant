import Foundation

enum Gender: String, CaseIterable, Codable, Identifiable {
    case unspecified
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: "未指定"
        case .male: "男"
        case .female: "女"
        }
    }
}

enum FitnessGoal: String, CaseIterable, Codable, Identifiable {
    case fatLoss
    case maintain
    case muscleGain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fatLoss: "减脂"
        case .maintain: "维持"
        case .muscleGain: "增肌"
        }
    }
}

enum ExerciseSource: String, CaseIterable, Codable, Identifiable {
    case healthKit
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthKit: "Apple 健康"
        case .manual: "手动记录"
        }
    }
}

enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "零嘴"
        case .other: "其他"
        }
    }
}

enum FoodOptionKind: String, CaseIterable, Codable, Identifiable {
    case single
    case combo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "单品"
        case .combo: "套餐"
        }
    }
}

/// 日常活动水平，对应训练计划里的活动系数（PAL），用于估算 TDEE。
enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary
    case light
    case moderate
    case active

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: "久坐（几乎不动）"
        case .light: "轻度活动"
        case .moderate: "中度活动"
        case .active: "高强度体力"
        }
    }

    /// Physical Activity Level 系数：TDEE ≈ BMR × palFactor。
    var palFactor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        }
    }
}

/// 训练经验/年限，影响计划的动作选择与强度。
enum TrainingExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "初学者"
        case .intermediate: "有基础"
        case .advanced: "资深"
        }
    }
}
