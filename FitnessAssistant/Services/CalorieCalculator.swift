import Foundation

struct DailyEnergyComputation {
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
}

enum CalorieCalculator {
    static func bmr(profile: UserProfile) -> Double {
        let weight = max(profile.currentWeightKg, 1)
        let height = max(profile.heightCm, 1)
        let age = max(profile.age, 1)
        let base = 10 * weight + 6.25 * height - 5 * Double(age)

        switch profile.gender {
        case .male:
            return base + 5
        case .female:
            return base - 161
        case .unspecified:
            return base - 78
        }
    }

    static func compute(
        intakeCalories: Double,
        healthKitActiveCalories: Double,
        manualActiveCalories: Double,
        healthKitRestingCalories: Double?,
        profile: UserProfile
    ) -> DailyEnergyComputation {
        let activeCalories = max(0, healthKitActiveCalories) + max(0, manualActiveCalories)
        let restingCalories = max(0, healthKitRestingCalories ?? bmr(profile: profile))
        let totalBurn = restingCalories + activeCalories
        let deficit = totalBurn - max(0, intakeCalories)

        return DailyEnergyComputation(
            intakeCalories: max(0, intakeCalories),
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit
        )
    }
}
