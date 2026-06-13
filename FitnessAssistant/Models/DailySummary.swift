import Foundation
import SwiftData

struct DailySnapshot: Codable {
    var date: Date
    var goal: String
    var targetDailyDeficitKcal: Double
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
    var meals: [String]
    var workouts: [String]
}

struct DailyAdvice: Codable {
    var summary: String
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
