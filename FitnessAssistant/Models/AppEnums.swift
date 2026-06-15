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
