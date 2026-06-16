import XCTest
@testable import FitnessAssistant

/// `DayMetricsCalculator` 是数据重构后的唯一聚合源，这里覆盖最关键的不变量：
/// 活动消耗去重、体重回退链、目标缺口口径、摄入合计。
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
            summaries: [], checkIns: [], trainingPlans: []
        )
        XCTAssertEqual(metrics.healthActiveCalories, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.manualActiveCalories, 100, accuracy: 0.001)
        // 健康聚合 400 + 手动 100 = 500；单次 workout 300 已含在聚合内，不再叠加。
        XCTAssertEqual(metrics.activeCalories, 500, accuracy: 0.001)
    }

    /// 体重统一回退链：当天打卡优先于当天总结。
    func testWeightFallbackPrefersTodayCheckInOverSummary() {
        let now = Date()
        let profile = makeProfile()
        let checkIn = DailyCheckIn(date: now, weightKg: 70)
        let summary = DailySummary(date: now, weightKg: 71)
        let metrics = DayMetricsCalculator.metrics(
            for: now, profile: profile, meals: [], exercises: [],
            summaries: [summary], checkIns: [checkIn], trainingPlans: []
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
            summaries: [], checkIns: [], trainingPlans: []
        )
        XCTAssertEqual(metrics.intakeCalories, 800, accuracy: 0.001)
        XCTAssertEqual(metrics.proteinGrams, 50, accuracy: 0.001)
        XCTAssertEqual(metrics.carbsGrams, 80, accuracy: 0.001)
        XCTAssertEqual(metrics.fatGrams, 25, accuracy: 0.001)
    }
}
