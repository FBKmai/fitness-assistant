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
    var brand: String?
    var aliases: [String]?
    var portionDescription: String
    var servingWeightGrams: Double?
    var components: [FoodOptionComponent]
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double?
    var sodiumMg: Double?
    var confidence: Double
    var recommendationScore: Double
    var recommendationReason: String
    var summary: String
}

struct FoodOptionSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var brand: String
    var aliases: [String]
    var kind: String
    var portionDescription: String
    var servingWeightGrams: Double
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sodiumMg: Double
    var dataSource: String
    var confidence: Double
    var recommendationScore: Double
    var recommendationReason: String
    var components: [FoodOptionComponent]
}

@Model
final class FoodOption {
    var id: UUID
    var name: String
    var brand: String = ""
    var aliasesJSON: String = "[]"
    var kindRaw: String = FoodOptionKind.single.rawValue
    /// 商品条码（EAN/UPC 等），扫码记餐用于精确命中。空表示未绑定。新增字段带默认值便于轻量迁移。
    var barcode: String = ""
    var photoLocalPath: String?
    var sourceDescription: String
    var portionDescription: String
    var servingWeightGrams: Double = 0
    var componentsJSON: String
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double = 0
    var sodiumMg: Double = 0
    var dataSource: String = "manual"
    var confidence: Double
    var recommendationScore: Double
    var recommendationReason: String
    var aiSummary: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        aliases: [String] = [],
        kind: FoodOptionKind = .single,
        barcode: String = "",
        photoLocalPath: String? = nil,
        sourceDescription: String = "",
        portionDescription: String = "",
        servingWeightGrams: Double = 0,
        components: [FoodOptionComponent] = [],
        totalCalories: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        sodiumMg: Double = 0,
        dataSource: String = "manual",
        confidence: Double = 0,
        recommendationScore: Double = 0,
        recommendationReason: String = "",
        aiSummary: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.aliasesJSON = Self.encodeStrings(aliases)
        self.kindRaw = kind.rawValue
        self.barcode = barcode
        self.photoLocalPath = photoLocalPath
        self.sourceDescription = sourceDescription
        self.portionDescription = portionDescription
        self.servingWeightGrams = servingWeightGrams
        self.componentsJSON = Self.encodeComponents(components)
        self.totalCalories = totalCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sodiumMg = sodiumMg
        self.dataSource = dataSource
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

    var aliases: [String] {
        get { Self.decodeStrings(aliasesJSON) }
        set { aliasesJSON = Self.encodeStrings(newValue) }
    }

    var normalizedSearchTerms: [String] {
        ([name, brand] + aliases)
            .map(Self.normalizeTerm)
            .filter { !$0.isEmpty }
    }

    func matches(_ text: String) -> Bool {
        let normalized = Self.normalizeTerm(text)
        guard !normalized.isEmpty else { return false }
        return normalizedSearchTerms.contains { term in
            term == normalized || term.contains(normalized) || normalized.contains(term)
        }
    }

    func addAliases(_ values: [String]) {
        var merged = aliases
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !matches(trimmed) else { continue }
            merged.append(trimmed)
        }
        aliases = Array(merged.prefix(30))
        updatedAt = .now
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
            brand: brand,
            aliases: aliases,
            kind: kind.title,
            portionDescription: portionDescription,
            servingWeightGrams: servingWeightGrams,
            totalCalories: totalCalories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sodiumMg: sodiumMg,
            dataSource: dataSource,
            confidence: confidence,
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

    private static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func normalizeTerm(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "的", with: "")
            .replacingOccurrences(of: "之前那个", with: "")
            .replacingOccurrences(of: "之前的", with: "")
    }
}
