import Foundation
import SwiftData

struct MealFoodItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var note: String

    enum CodingKeys: String, CodingKey {
        case name
        case calories
        case proteinGrams
        case carbsGrams
        case fatGrams
        case note
    }

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.note = note
    }
}

struct MealEstimate: Codable {
    var items: [MealFoodItem]
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidence: Double
    var summary: String
}

struct MealAdviceSnapshot: Codable {
    var mealID: UUID
    var mealType: String
    var mealDate: Date
    var mealDescription: String
    var mealCalories: Double
    var mealProteinGrams: Double
    var mealCarbsGrams: Double
    var mealFatGrams: Double
    var todayMeals: [String]
    var todayIntakeCalories: Double
    var todayProteinGrams: Double
    var todayCarbsGrams: Double
    var todayFatGrams: Double
    var todayActiveCalories: Double
    var todayRestingCalories: Double
    var todayCalorieDeficit: Double
    var goal: String
    var targetDailyDeficitKcal: Double
    var weightKg: Double
    var analysis: FatLossAnalysis
}

struct MealAdviceResponse: Codable {
    var mealReview: String
    var nextMealAdvice: String
    var snackAdvice: String
    var caution: String
}

@Model
final class MealEntry {
    var id: UUID
    var date: Date
    var mealTypeRaw: String = MealType.other.rawValue
    var textDescription: String
    var photoLocalPath: String?
    var estimatedItemsJSON: String
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidence: Double
    var isConfirmed: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        mealType: MealType = .other,
        textDescription: String = "",
        photoLocalPath: String? = nil,
        estimatedItems: [MealFoodItem] = [],
        totalCalories: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        confidence: Double = 0,
        isConfirmed: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.textDescription = textDescription
        self.photoLocalPath = photoLocalPath
        self.estimatedItemsJSON = Self.encodeItems(estimatedItems)
        self.totalCalories = totalCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.confidence = confidence
        self.isConfirmed = isConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .other }
        set { mealTypeRaw = newValue.rawValue }
    }

    var estimatedItems: [MealFoodItem] {
        get { Self.decodeItems(estimatedItemsJSON) }
        set { estimatedItemsJSON = Self.encodeItems(newValue) }
    }

    private static func encodeItems(_ items: [MealFoodItem]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeItems(_ json: String) -> [MealFoodItem] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MealFoodItem].self, from: data)) ?? []
    }
}

@Model
final class MealAdviceRecord {
    var id: UUID
    var mealID: UUID
    var mealDate: Date
    var mealTypeRaw: String
    var mealDescription: String
    var mealCalories: Double
    var mealReview: String
    var nextMealAdvice: String
    var snackAdvice: String
    var caution: String
    var snapshotJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        mealID: UUID,
        mealDate: Date,
        mealType: MealType,
        mealDescription: String,
        mealCalories: Double,
        mealReview: String,
        nextMealAdvice: String,
        snackAdvice: String,
        caution: String,
        snapshot: MealAdviceSnapshot,
        createdAt: Date = .now
    ) {
        self.id = id
        self.mealID = mealID
        self.mealDate = mealDate
        self.mealTypeRaw = mealType.rawValue
        self.mealDescription = mealDescription
        self.mealCalories = mealCalories
        self.mealReview = mealReview
        self.nextMealAdvice = nextMealAdvice
        self.snackAdvice = snackAdvice
        self.caution = caution
        self.snapshotJSON = Self.encodeSnapshot(snapshot)
        self.createdAt = createdAt
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .other }
        set { mealTypeRaw = newValue.rawValue }
    }

    var snapshot: MealAdviceSnapshot? {
        get { Self.decodeSnapshot(snapshotJSON) }
        set { snapshotJSON = Self.encodeSnapshot(newValue) }
    }

    private static func encodeSnapshot(_ snapshot: MealAdviceSnapshot?) -> String {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeSnapshot(_ json: String) -> MealAdviceSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MealAdviceSnapshot.self, from: data)
    }
}
