import Foundation
import SwiftData

struct FoodOptionComponent: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var portionDescription: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var note: String

    enum CodingKeys: String, CodingKey {
        case name
        case portionDescription
        case calories
        case proteinGrams
        case carbsGrams
        case fatGrams
        case note
    }

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String = "",
        calories: Double,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.note = note
    }
}
struct FoodOptionEstimate: Codable {
    var name: String
    var kind: String?
    var portionDescription: String
    var components: [FoodOptionComponent]
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidence: Double
    var recommendationScore: Double
    var recommendationReason: String
    var summary: String
}

struct FoodOptionSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: String
    var portionDescription: String
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var recommendationScore: Double
    var recommendationReason: String
    var components: [FoodOptionComponent]
}

@Model
final class FoodOption {
    var id: UUID
    var name: String
    var kindRaw: String = FoodOptionKind.single.rawValue
    var photoLocalPath: String?
    var sourceDescription: String
    var portionDescription: String
    var componentsJSON: String
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidence: Double
    var recommendationScore: Double
    var recommendationReason: String
    var aiSummary: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: FoodOptionKind = .single,
        photoLocalPath: String? = nil,
        sourceDescription: String = "",
        portionDescription: String = "",
        components: [FoodOptionComponent] = [],
        totalCalories: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        confidence: Double = 0,
        recommendationScore: Double = 0,
        recommendationReason: String = "",
        aiSummary: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.photoLocalPath = photoLocalPath
        self.sourceDescription = sourceDescription
        self.portionDescription = portionDescription
        self.componentsJSON = Self.encodeComponents(components)
        self.totalCalories = totalCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.confidence = confidence
        self.recommendationScore = recommendationScore
        self.recommendationReason = recommendationReason
        self.aiSummary = aiSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: FoodOptionKind {
        get { FoodOptionKind(rawValue: kindRaw) ?? .single }
        set { kindRaw = newValue.rawValue }
    }

    var components: [FoodOptionComponent] {
        get { Self.decodeComponents(componentsJSON) }
        set { componentsJSON = Self.encodeComponents(newValue) }
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

    var snapshot: FoodOptionSnapshot {
        FoodOptionSnapshot(
            id: id,
            name: name,
            kind: kind.title,
            portionDescription: portionDescription,
            totalCalories: totalCalories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            recommendationScore: recommendationScore,
            recommendationReason: recommendationReason,
            components: components
        )
    }

    func mealItems(optionNote: String = "") -> [MealFoodItem] {
        if components.isEmpty {
            return [
                MealFoodItem(
                    name: name,
                    calories: totalCalories,
                    proteinGrams: proteinGrams,
                    carbsGrams: carbsGrams,
                    fatGrams: fatGrams,
                    note: optionNote.isEmpty ? portionDescription : "\(portionDescription)；\(optionNote)"
                )
            ]
        }

        return components.map { component in
            MealFoodItem(
                name: component.name,
                calories: component.calories,
                proteinGrams: component.proteinGrams,
                carbsGrams: component.carbsGrams,
                fatGrams: component.fatGrams,
                note: [component.portionDescription, component.note, optionNote]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "；")
            )
        }
    }

    private static func encodeComponents(_ components: [FoodOptionComponent]) -> String {
        guard let data = try? JSONEncoder().encode(components) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeComponents(_ json: String) -> [FoodOptionComponent] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([FoodOptionComponent].self, from: data)) ?? []
    }
}
