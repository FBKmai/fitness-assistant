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

@Model
final class MealEntry {
    var id: UUID
    var date: Date
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
