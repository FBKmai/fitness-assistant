import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var heightCm: Double
    var currentWeightKg: Double
    var genderRaw: String
    var birthday: Date
    var goalRaw: String
    var targetDailyDeficitKcal: Double
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        heightCm: Double = 170,
        currentWeightKg: Double = 70,
        gender: Gender = .unspecified,
        birthday: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
        goal: FitnessGoal = .fatLoss,
        targetDailyDeficitKcal: Double = 500,
        reminderHour: Int = 22,
        reminderMinute: Int = 30,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.heightCm = heightCm
        self.currentWeightKg = currentWeightKg
        self.genderRaw = gender.rawValue
        self.birthday = birthday
        self.goalRaw = goal.rawValue
        self.targetDailyDeficitKcal = targetDailyDeficitKcal
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var gender: Gender {
        get { Gender(rawValue: genderRaw) ?? .unspecified }
        set { genderRaw = newValue.rawValue }
    }

    var goal: FitnessGoal {
        get { FitnessGoal(rawValue: goalRaw) ?? .fatLoss }
        set { goalRaw = newValue.rawValue }
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 30
    }
}
