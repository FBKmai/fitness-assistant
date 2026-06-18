import XCTest
@testable import FitnessAssistant

/// `DayMetricsCalculator` 是数据重构后的唯一聚合源，这里覆盖最关键的不变量：
/// 活动消耗去重、体重单源、目标缺口口径、摄入合计。
final class DayMetricsCalculatorTests: XCTestCase {

    private func makeProfile() -> UserProfile {
        UserProfile(
            heightCm: 175,
            currentWeightKg: 75,
            gender: .male,
            targetDailyDeficitKcal: 500
        )
    }

    /// HealthKit 当日聚合已包含单次 workout 的活动能量，绝不能再把单次 workout 累加进去。
    /// 这是重构前 MealsView 单餐建议的真实 bug。
    func testActiveCaloriesDeduplicatesHealthAggregateAndWorkouts() {
        let now = Date()
        let profile = makeProfile()
        let exercises = [
            ExerciseEntry(date: now, source: .healthKit, workoutType: "每日活动合计", activeCalories: 400, steps: 8000, healthKitWorkoutID: "daily-\(now.dayKey)"),
            ExerciseEntry(date: now, source: .healthKit, workoutType: "跑步", durationMinutes: 30, activeCalories: 300, healthKitWorkoutID: "workout-1"),
            ExerciseEntry(date: now, source: .manual, workoutType: "力量", activeCalories: 100)
        ]
        let metrics = DayMetricsCalculator.metrics(
            for: now, profile: profile, meals: [], exercises: exercises,
            dayLogs: [], trainingPlans: []
        )
        XCTAssertEqual(metrics.healthActiveCalories, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.manualActiveCalories, 100, accuracy: 0.001)
        // 健康聚合 400 + 手动 100 = 500；单次 workout 300 已含在聚合内，不再叠加。
        XCTAssertEqual(metrics.activeCalories, 500, accuracy: 0.001)
    }

    /// 体重单源：来自当天 DayLog。
    func testWeightComesFromTodayDayLog() {
        let now = Date()
        let profile = makeProfile()
        let log = DayLog(date: now, weightKg: 70)
        let metrics = DayMetricsCalculator.metrics(
            for: now, profile: profile, meals: [], exercises: [],
            dayLogs: [log], trainingPlans: []
        )
        XCTAssertEqual(metrics.weightKg ?? 0, 70, accuracy: 0.001)
    }

    /// 无训练计划时，目标缺口回退到档案设置。
    func testEffectiveDeficitTargetFallsBackToProfileWhenNoPlan() {
        let profile = makeProfile()
        let target = DayMetricsCalculator.effectiveDeficitTarget(profile: profile, trainingPlans: [])
        XCTAssertEqual(target, 500, accuracy: 0.001)
    }

    /// 摄入合计当天全部餐食（不再按 isConfirmed 分流）。
    func testIntakeSumsAllMealsForDay() {
        let now = Date()
        let profile = makeProfile()
        let meals = [
            MealEntry(date: now, totalCalories: 500, proteinGrams: 30, carbsGrams: 50, fatGrams: 15),
            MealEntry(date: now, totalCalories: 300, proteinGrams: 20, carbsGrams: 30, fatGrams: 10)
        ]
        let metrics = DayMetricsCalculator.metrics(
            for: now, profile: profile, meals: meals, exercises: [],
            dayLogs: [], trainingPlans: []
        )
        XCTAssertEqual(metrics.intakeCalories, 800, accuracy: 0.001)
        XCTAssertEqual(metrics.proteinGrams, 50, accuracy: 0.001)
        XCTAssertEqual(metrics.carbsGrams, 80, accuracy: 0.001)
        XCTAssertEqual(metrics.fatGrams, 25, accuracy: 0.001)
    }

    func testHealthKitRestingEnergyWinsAndMissingValueFallsBackToBMR() {
        let now = Date()
        let profile = makeProfile()
        let health = HealthSnapshot(
            date: now,
            steps: 0,
            activeEnergyKcal: 300,
            basalEnergyKcal: 1_520,
            averageHeartRate: nil,
            restingHeartRate: nil,
            sleepHours: nil,
            workouts: [],
            bodyMetrics: HealthBodyMetrics()
        )

        let healthMetrics = DayMetricsCalculator.metrics(
            for: now,
            profile: profile,
            meals: [],
            exercises: [],
            dayLogs: [],
            trainingPlans: [],
            healthSnapshot: health
        )
        XCTAssertEqual(healthMetrics.restingCalories, 1_520, accuracy: 0.001)
        XCTAssertEqual(healthMetrics.restingEnergySource.rawValue, RestingEnergySource.healthKit.rawValue)

        let fallbackMetrics = DayMetricsCalculator.metrics(
            for: now,
            profile: profile,
            meals: [],
            exercises: [],
            dayLogs: [],
            trainingPlans: []
        )
        XCTAssertEqual(fallbackMetrics.restingCalories, fallbackMetrics.bmrEstimate, accuracy: 0.001)
        XCTAssertEqual(fallbackMetrics.restingEnergySource.rawValue, RestingEnergySource.bmrEstimate.rawValue)
    }

    func testConfirmedDayLogWeightWinsOverHealthKitSnapshot() {
        let now = Date()
        let profile = makeProfile()
        let log = DayLog(date: now, weightKg: 79.35)
        let health = HealthSnapshot(
            date: now,
            steps: 0,
            activeEnergyKcal: 0,
            basalEnergyKcal: nil,
            averageHeartRate: nil,
            restingHeartRate: nil,
            sleepHours: nil,
            workouts: [],
            bodyMetrics: HealthBodyMetrics(weightKg: 89.35)
        )

        let metrics = DayMetricsCalculator.metrics(
            for: now,
            profile: profile,
            meals: [],
            exercises: [],
            dayLogs: [log],
            trainingPlans: [],
            healthSnapshot: health
        )

        XCTAssertEqual(metrics.weightKg ?? 0, 79.35, accuracy: 0.001)
    }

    func testWeightAnomalyRejectsMistypedValue() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let logs = (1...7).map { offset in
            DayLog(
                date: calendar.date(byAdding: .day, value: -offset, to: today)!,
                weightKg: 79.2 + Double(offset) * 0.05
            )
        }

        XCTAssertNotNil(
            TrendSafetyAnalyzer.weightAnomaly(
                proposedKg: 89.35,
                on: today,
                dayLogs: logs
            )
        )
        XCTAssertNil(
            TrendSafetyAnalyzer.weightAnomaly(
                proposedKg: 79.35,
                on: today,
                dayLogs: logs
            )
        )
    }

    func testTrendAveragePlateauAndRecalculationAfterCorrection() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let logs = (0..<14).map { offset in
            DayLog(
                date: calendar.date(byAdding: .day, value: -offset, to: today)!,
                weightKg: 80,
                intakeCalories: 1_800
            )
        }

        let plateau = TrendSafetyAnalyzer.weightTrend(
            dayLogs: logs,
            targetWeightKg: 70,
            currentWeightKg: 80,
            calendar: calendar
        )
        XCTAssertEqual(plateau.sevenDayAverage ?? 0, 80, accuracy: 0.001)
        XCTAssertTrue(plateau.isPlateau)

        logs[0].weightKg = 79
        let recalculated = TrendSafetyAnalyzer.weightTrend(
            dayLogs: logs,
            targetWeightKg: 70,
            currentWeightKg: 79,
            calendar: calendar
        )
        XCTAssertNotEqual(
            plateau.fourteenDayRateKgPerWeek,
            recalculated.fourteenDayRateKgPerWeek
        )
    }

    func testRapidWeightLossCreatesSafetyAlert() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let logs = (0..<7).map { offset in
            DayLog(
                date: calendar.date(byAdding: .day, value: -offset, to: today)!,
                weightKg: 80 + Double(offset) * 0.35,
                intakeCalories: 1_800
            )
        }

        let alerts = TrendSafetyAnalyzer.alerts(dayLogs: logs, currentWeightKg: 80)
        XCTAssertTrue(alerts.contains { $0.message.contains("1%") })
    }

    func testFoodAliasMatchesNaturalReference() {
        let option = FoodOption(
            name: "原味鸡排",
            aliases: ["鸡排", "空气炸锅鸡排"]
        )

        XCTAssertTrue(option.matches("鸡排"))
        XCTAssertTrue(option.matches("之前那个鸡排"))
        XCTAssertFalse(option.matches("羊排"))
    }
}
