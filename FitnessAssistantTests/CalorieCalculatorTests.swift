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

    func testBMRWinsOverPartialHealthKitRestingEnergy() {
        let birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let profile = UserProfile(heightCm: 170, currentWeightKg: 70, gender: .unspecified, birthday: birthday)
        let expectedBMR = CalorieCalculator.bmr(profile: profile)

        let result = CalorieCalculator.compute(
            intakeCalories: 2000,
            healthKitActiveCalories: 300,
            manualActiveCalories: 0,
            healthKitRestingCalories: 1500,
            profile: profile
        )

        XCTAssertEqual(result.restingCalories, expectedBMR, accuracy: 0.1)
        XCTAssertEqual(result.totalBurnCalories, expectedBMR + 300, accuracy: 0.1)
        XCTAssertEqual(result.calorieDeficit, expectedBMR + 300 - 2000, accuracy: 0.1)
    }

    func testFatLossAnalyzerFlagsLowIntakeAndProtein() {
        let snapshot = DailySnapshot(
            date: .now,
            goal: "减脂",
            targetDailyDeficitKcal: 500,
            heightCm: 175,
            weightKg: 80,
            gender: "男",
            age: 30,
            bmr: 1750,
            intakeCalories: 1100,
            activeCalories: 500,
            restingCalories: 1750,
            totalBurnCalories: 2250,
            calorieDeficit: 1150,
            proteinGrams: 55,
            carbsGrams: 120,
            fatGrams: 25,
            averageMealConfidence: 0.8,
            unconfirmedMealCount: 0,
            manualActiveCalories: 0,
            meals: ["午餐 1100 kcal"],
            workouts: ["跑步 500 kcal"],
            recentDays: [],
            analysis: nil
        )

        let analysis = FatLossAnalyzer.analyze(snapshot: snapshot)

        XCTAssertEqual(analysis.energyStatus, "摄入过低")
        XCTAssertEqual(analysis.proteinStatus, "明显不足")
        XCTAssertTrue(analysis.warnings.contains { $0.contains("蛋白质明显不足") })
        XCTAssertLessThan(analysis.dataQualityScore, 1)
    }

    func testFatLossAnalyzerUsesRecentTrend() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let recentDays = (1...4).map { offset in
            DayTrend(
                date: calendar.date(byAdding: .day, value: -offset, to: today)!,
                intakeCalories: 1800,
                calorieDeficit: 650,
                weightKg: 80 - Double(offset) * 0.1
            )
        }
        let snapshot = DailySnapshot(
            date: .now,
            goal: "减脂",
            targetDailyDeficitKcal: 500,
            heightCm: 175,
            weightKg: 80,
            gender: "男",
            age: 30,
            bmr: 1750,
            intakeCalories: 1850,
            activeCalories: 450,
            restingCalories: 1750,
            totalBurnCalories: 2200,
            calorieDeficit: 350,
            proteinGrams: 140,
            carbsGrams: 180,
            fatGrams: 60,
            averageMealConfidence: 0.9,
            unconfirmedMealCount: 0,
            manualActiveCalories: 0,
            meals: ["早餐 600 kcal", "午餐 1250 kcal"],
            workouts: ["力量训练 300 kcal"],
            recentDays: recentDays,
            analysis: nil
        )

        let analysis = FatLossAnalyzer.analyze(snapshot: snapshot)

        XCTAssertEqual(analysis.proteinStatus, "达标")
        XCTAssertEqual(analysis.sevenDayAverageDeficit ?? 0, 650, accuracy: 0.1)
        XCTAssertNotNil(analysis.sevenDayWeightChangeKg)
        XCTAssertGreaterThan(analysis.dataQualityScore, 0.8)
    }
}
