import XCTest
@testable import FitnessAssistant

final class CoachContextBuilderTests: XCTestCase {
    func testBuildIncludesIntegratedContext() {
        let now = DateComponents(calendar: .current, year: 2026, month: 6, day: 15, hour: 12).date!
        let todayStart = Calendar.current.startOfDay(for: now)
        let profile = UserProfile(heightCm: 171, currentWeightKg: 86, gender: .male, birthday: DateComponents(calendar: .current, year: 2002, month: 1, day: 1).date!)
        let todayLog = DayLog(date: todayStart, weightKg: 85.5, sleepHours: 5.5, waterMl: 1200, hungerLevel: 7, mood: "疲惫", symptoms: "鼻塞")

        let lunch = MealEntry(
            date: now,
            mealType: .lunch,
            textDescription: "牛肉饭",
            totalCalories: 600,
            proteinGrams: 42,
            carbsGrams: 70,
            fatGrams: 15,
            confidence: 0.8,
            isConfirmed: true
        )
        let snack = MealEntry(
            date: now,
            mealType: .snack,
            textDescription: "零食",
            totalCalories: 900,
            proteinGrams: 1,
            carbsGrams: 100,
            fatGrams: 40,
            isConfirmed: true
        )
        let healthAggregate = ExerciseEntry(
            date: now,
            source: .healthKit,
            workoutType: "每日活动合计",
            activeCalories: 300,
            steps: 8000,
            healthKitWorkoutID: "daily-\(now.dayKey)"
        )
        let healthWorkout = ExerciseEntry(
            date: now,
            source: .healthKit,
            workoutType: "力量训练",
            activeCalories: 220,
            healthKitWorkoutID: "workout-1"
        )
        let manualWorkout = ExerciseEntry(
            date: now,
            source: .manual,
            workoutType: "补录有氧",
            activeCalories: 120
        )
        let foodOption = FoodOption(name: "双倍牛肉饭", totalCalories: 520, proteinGrams: 45, carbsGrams: 55, fatGrams: 12)
        let plan = TrainingPlan(title: "减脂训练计划", dailyCalories: 1800, proteinGrams: 150, carbsGrams: 180, fatGrams: 50, trainingDaysPerWeek: 4, summary: "力量+有氧")

        let context = CoachContextBuilder.build(
            profile: profile,
            dayLogs: [todayLog],
            meals: [lunch, snack],
            exercises: [healthAggregate, healthWorkout, manualWorkout],
            foodOptions: [foodOption],
            trainingPlans: [plan],
            memory: CoachMemory(foodPreferences: ["牛肉饭"]),
            now: now
        )

        // 退役 isConfirmed：当天全部餐食计入。
        XCTAssertEqual(context.today.intakeCalories, 1500)
        XCTAssertEqual(context.today.proteinGrams, 43)
        XCTAssertEqual(context.today.confirmedMealCount, 2)
        XCTAssertEqual(context.today.unconfirmedMealCount, 0)
        // 活动消耗去重：聚合 300 + 手动 120，单次 workout 220 不叠加。
        XCTAssertEqual(context.today.activeCalories, 420)
        XCTAssertEqual(context.today.steps, 8000)
        XCTAssertEqual(context.today.workoutCount, 2)
        XCTAssertEqual(context.today.sleepHours ?? 0, 5.5)
        XCTAssertEqual(context.today.waterMl ?? 0, 1200)
        XCTAssertEqual(context.foodOptions.count, 1)
        XCTAssertEqual(context.trainingPlans.first?.summary, "力量+有氧")
        XCTAssertEqual(context.memory?.foodPreferences, ["牛肉饭"])
    }

    func testRecentTrendsAreTruncated() {
        let now = DateComponents(calendar: .current, year: 2026, month: 6, day: 15, hour: 12).date!
        let profile = UserProfile(heightCm: 171, currentWeightKg: 86, gender: .male)
        let dayLogs = (1...35).compactMap { offset -> DayLog? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return DayLog(date: date, weightKg: 86 - Double(offset) * 0.1, intakeCalories: Double(offset), calorieDeficit: Double(offset * 10))
        }

        let context = CoachContextBuilder.build(
            profile: profile,
            dayLogs: dayLogs,
            meals: [],
            exercises: [],
            foodOptions: [],
            trainingPlans: [],
            memory: nil,
            now: now
        )

        XCTAssertEqual(context.recent7Days.count, 7)
        XCTAssertEqual(context.recent30Days.count, 30)
        XCTAssertTrue(context.recent7Days.allSatisfy { $0.date < Calendar.current.startOfDay(for: now) })
    }
}
