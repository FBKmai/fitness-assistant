import Foundation

/// 某一天的全部派生指标——全局唯一聚合源。
///
/// 取代原先散落在 `TodayView` / `MealsView` / `CoachContextBuilder` / `FoodHubView`
/// 的重复聚合与各异口径。所有「今日/某天」的热量、营养、活动消耗、缺口、体重、
/// 趋势与规则化判断都从这里产出，杜绝重复计算与口径分叉。
struct DayMetrics {
    var date: Date
    // 摄入与三大营养（当天全部餐食合计）
    var intakeCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var vegetableGrams: Double
    // 热量（活动消耗已去重：健康聚合 + 手动，绝不累加单次 workout）
    var healthActiveCalories: Double
    var manualActiveCalories: Double
    var activeCalories: Double
    var bmrEstimate: Double
    var restingCalories: Double
    var restingEnergySource: RestingEnergySource
    var totalBurnCalories: Double
    var calorieDeficit: Double
    // 身体数据（体重优先使用 DayLog，避免用户确认值被 HealthKit 覆盖）
    var weightKg: Double?
    var bodyFatPercentage: Double?
    var bodyMassIndex: Double?
    var bodyMetricsMeasuredAt: Date?
    // 餐食质量
    var averageMealConfidence: Double?
    // 目标缺口（训练计划优先，回退到档案设置）
    var effectiveDeficitTarget: Double
    var deficitReached: Bool
    // 喂 AI / 展示用的快照（DTO 适配器，字段保持原状）
    var dailySnapshot: DailySnapshot

    var analysis: FatLossAnalysis { dailySnapshot.analysis ?? FatLossAnalyzer.analyze(snapshot: dailySnapshot) }
    var recentDays: [DayTrend] { dailySnapshot.recentDays }
    var mealsText: [String] { dailySnapshot.meals }
    var workoutsText: [String] { dailySnapshot.workouts }
}

enum DayMetricsCalculator {
    /// 计算指定日期的全部派生指标。`healthSnapshot` 仅在计算「今天」且手头有实时快照时传入。
    static func metrics(
        for date: Date,
        profile: UserProfile,
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        dayLogs: [DayLog],
        trainingPlans: [TrainingPlan],
        healthSnapshot: HealthSnapshot? = nil
    ) -> DayMetrics {
        let calendar = Calendar.current
        let interval = calendar.dayInterval(containing: date)
        let isToday = calendar.isDateInToday(date)

        let dayMeals = meals.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        let dayExercises = exercises.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        let dayLog = dayLogs.first { calendar.isDate($0.date, inSameDayAs: date) }

        // 摄入与营养：当天全部餐食合计（不再按 isConfirmed 分流——保存即计入）。
        let intake = dayMeals.reduce(0) { $0 + $1.totalCalories }
        let protein = dayMeals.reduce(0) { $0 + $1.proteinGrams }
        let carbs = dayMeals.reduce(0) { $0 + $1.carbsGrams }
        let fat = dayMeals.reduce(0) { $0 + $1.fatGrams }
        let fiber = dayMeals.reduce(0) { $0 + $1.fiberGrams }
        let vegetables = dayMeals.reduce(0) { $0 + $1.vegetableGrams }

        // 活动消耗唯一规则：HealthKit 当日聚合（或实时快照）+ 手动补录；绝不累加单次 workout。
        let manualActive = dayExercises
            .filter { $0.source == .manual }
            .reduce(0.0) { $0 + max(0, $1.activeCalories) }
        let aggregate = dayExercises.first(where: isDailyHealthAggregate)
        let healthActive = max(0, healthSnapshot?.activeEnergyKcal ?? aggregate?.activeCalories ?? 0)
        let active = healthActive + manualActive
        let bmrEstimate = max(0, CalorieCalculator.bmr(profile: profile))
        let healthResting = healthSnapshot?.basalEnergyKcal
            ?? ((dayLog?.restingEnergySourceRaw == RestingEnergySource.healthKit.rawValue)
                ? dayLog?.restingCalories
                : nil)
        let restingSource: RestingEnergySource = (healthResting ?? 0) > 0 ? .healthKit : .bmrEstimate
        let resting = max(0, healthResting ?? bmrEstimate)
        let totalBurn = active + resting
        let deficit = totalBurn - intake

        // DayLog 是体重单一写入口；HealthKit 同步会先更新 DayLog，
        // 用户确认的更正也保存在 DayLog，因此这里必须优先使用 DayLog。
        let healthMetrics = isToday ? healthSnapshot?.bodyMetrics : nil
        let weight = positive(dayLog?.weightKg)
            ?? healthMetrics?.weightKg
            ?? (isToday ? profile.currentWeightKg : nil)
        let bodyFat = healthMetrics?.bodyFatPercentage ?? dayLog?.bodyFatPercentage
        let bmi = healthMetrics?.bodyMassIndex ?? dayLog?.bodyMassIndex
        let measuredAt = healthMetrics?.measuredAt ?? dayLog?.bodyMetricsSyncedAt ?? dayLog?.updatedAt

        let target = effectiveDeficitTarget(profile: profile, trainingPlans: trainingPlans)

        let recentDays = dayLogs
            .filter { $0.date < interval.start && $0.hasSummary }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .map {
                DayTrend(
                    date: $0.date,
                    intakeCalories: $0.intakeCalories,
                    calorieDeficit: $0.calorieDeficit,
                    weightKg: positive($0.weightKg)
                )
            }

        var snapshot = DailySnapshot(
            date: date,
            goal: profile.goal.title,
            targetDailyDeficitKcal: target,
            heightCm: profile.heightCm,
            weightKg: weight ?? profile.currentWeightKg,
            bodyFatPercentage: bodyFat,
            bodyMassIndex: bmi,
            bodyMetricsMeasuredAt: measuredAt,
            gender: profile.gender.title,
            age: profile.age,
            bmr: bmrEstimate,
            intakeCalories: intake,
            activeCalories: active,
            restingCalories: resting,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit,
            restingEnergySource: restingSource.rawValue,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            vegetableGrams: vegetables,
            restingHeartRate: healthSnapshot?.restingHeartRate ?? dayLog?.restingHeartRate,
            averageHeartRate: healthSnapshot?.averageHeartRate ?? dayLog?.averageHeartRate,
            safetyWarnings: dayLog?.safetyWarnings ?? [],
            averageMealConfidence: averageConfidence(dayMeals),
            // 已退役「未确认餐」概念：恒为 0，不再据此扣数据质量分。
            unconfirmedMealCount: 0,
            manualActiveCalories: manualActive,
            meals: dayMeals.map(mealText),
            workouts: dayExercises.map(exerciseText),
            recentDays: Array(recentDays),
            analysis: nil
        )
        snapshot.analysis = FatLossAnalyzer.analyze(snapshot: snapshot)

        return DayMetrics(
            date: date,
            intakeCalories: intake,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            vegetableGrams: vegetables,
            healthActiveCalories: healthActive,
            manualActiveCalories: manualActive,
            activeCalories: active,
            bmrEstimate: bmrEstimate,
            restingCalories: resting,
            restingEnergySource: restingSource,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit,
            weightKg: weight,
            bodyFatPercentage: bodyFat,
            bodyMassIndex: bmi,
            bodyMetricsMeasuredAt: measuredAt,
            averageMealConfidence: averageConfidence(dayMeals),
            effectiveDeficitTarget: target,
            deficitReached: target > 0 && deficit >= target,
            dailySnapshot: snapshot
        )
    }

    /// 目标缺口唯一口径：始终使用 UserProfile 中的用户设置。
    static func effectiveDeficitTarget(profile: UserProfile, trainingPlans: [TrainingPlan]) -> Double {
        _ = trainingPlans
        return profile.targetDailyDeficitKcal
    }

    // MARK: - 私有

    private static func isDailyHealthAggregate(_ exercise: ExerciseEntry) -> Bool {
        exercise.source == .healthKit && (exercise.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
    }

    private static func averageConfidence(_ meals: [MealEntry]) -> Double? {
        let values = meals.map(\.confidence).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func mealText(_ meal: MealEntry) -> String {
        "\(meal.mealType.title) \(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
    }

    private static func exerciseText(_ exercise: ExerciseEntry) -> String {
        var text = "\(exercise.source.title) \(exercise.workoutType) \(exercise.activeCalories.kcalText)"
        if exercise.steps > 0 {
            text += " 步数\(Int(exercise.steps.rounded()))"
        }
        return text
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
