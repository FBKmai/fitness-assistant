import XCTest
@testable import FitnessAssistant

final class CalorieCalculatorTests: XCTestCase {
    func testBMRFallbackUsesProfileWhenHealthKitRestingEnergyMissing() {
        let birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let profile = UserProfile(heightCm: 180, currentWeightKg: 80, gender: .male, birthday: birthday)

        let result = CalorieCalculator.compute(
            intakeCalories: 1800,
            healthKitActiveCalories: 450,
            manualActiveCalories: 100,
            healthKitRestingCalories: nil,
            profile: profile
        )

        XCTAssertEqual(result.activeCalories, 550, accuracy: 0.1)
        XCTAssertGreaterThan(result.restingCalories, 1600)
        XCTAssertEqual(result.totalBurnCalories - result.intakeCalories, result.calorieDeficit, accuracy: 0.1)
    }

    func testHealthKitRestingEnergyWinsOverBMR() {
        let profile = UserProfile(heightCm: 170, currentWeightKg: 70, gender: .unspecified)

        let result = CalorieCalculator.compute(
            intakeCalories: 2000,
            healthKitActiveCalories: 300,
            manualActiveCalories: 0,
            healthKitRestingCalories: 1500,
            profile: profile
        )

        XCTAssertEqual(result.restingCalories, 1500, accuracy: 0.1)
        XCTAssertEqual(result.totalBurnCalories, 1800, accuracy: 0.1)
        XCTAssertEqual(result.calorieDeficit, -200, accuracy: 0.1)
    }
}
