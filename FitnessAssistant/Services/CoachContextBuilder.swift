import Foundation

enum CoachContextBuilder {
    static func build(
        profile: UserProfile,
        checkIns: [DailyCheckIn],
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        summaries: [DailySummary],
        foodOptions: [FoodOption],
        trainingPlans: [TrainingPlan],
        memory: CoachMemory?,
        now: Date = .now,
        healthSnapshot: HealthSnapshot? = nil
    ) -> CoachContextSnapshot {
        let calendar = Calendar.current
        let todayInterval = calendar.dayInterval(containing: now)
        let todayStart = todayInterval.start
        let todayCheckIn = checkIns.first { calendar.isDate($0.date, inSameDayAs: now) }
        // 目标缺口统一口径（训练计划优先，回退档案），与今日页 / 单餐建议一致。
        let deficitTarget = DayMetricsCalculator.effectiveDeficitTarget(profile: profile, trainingPlans: trainingPlans)

        let todayMeals = meals.filter { todayInterval.contains($0.date) }
        let confirmedMeals = todayMeals.filter(\.isConfirmed)
        let todayExercises = exercises.filter { todayInterval.contains($0.date) }
        let todaySummary = summaries.first { calendar.isDate($0.date, inSameDayAs: now) }

        let intake = confirmedMeals.reduce(0) { $0 + $1.totalCalories }
        let protein = confirmedMeals.reduce(0) { $0 + $1.proteinGrams }
        let carbs = confirmedMeals.reduce(0) { $0 + $1.carbsGrams }
        let fat = confirmedMeals.reduce(0) { $0 + $1.fatGrams }
        let manualActiveCalories = todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
        let dailyHealthAggregate = todayExercises.first {
            $0.source == .healthKit && ($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
        }
        let healthActiveCalories = healthSnapshot?.activeEnergyKcal ?? dailyHealthAggregate?.activeCalories ?? 0
        let activeCalories = max(0, healthActiveCalories) + max(0, manualActiveCalories)
        let restingCalories = CalorieCalculator.bmr(profile: profile)
        let totalBurnCalories = activeCalories + restingCalories
        let calorieDeficit = totalBurnCalories - intake

        let weight = healthSnapshot?.bodyMetrics.weightKg
            ?? valueIfPositive(todayCheckIn?.weightKg)
            ?? valueIfPositive(todaySummary?.weightKg)
            ?? profile.currentWeightKg
        let bodyFat = healthSnapshot?.bodyMetrics.bodyFatPercentage
            ?? todayCheckIn?.bodyFatPercentage
            ?? todaySummary?.bodyFatPercentage
        let bmi = healthSnapshot?.bodyMetrics.bodyMassIndex
            ?? todayCheckIn?.bodyMassIndex
            ?? todaySummary?.bodyMassIndex
        let sleepHours = healthSnapshot?.sleepHours ?? todayCheckIn?.sleepHours
        let steps = healthSnapshot?.steps ?? dailyHealthAggregate?.steps ?? 0

        let recentSummaries = summaries
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }
        let recentCheckIns = checkIns
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }

        var dailySnapshot = DailySnapshot(
            date: now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: deficitTarget,
            heightCm: profile.heightCm,
            weightKg: weight,
            bodyFatPercentage: bodyFat,
            bodyMassIndex: bmi,
            bodyMetricsMeasuredAt: healthSnapshot?.bodyMetrics.measuredAt ?? todayCheckIn?.updatedAt ?? todaySummary?.bodyMetricsSyncedAt,
            gender: profile.gender.title,
            age: profile.age,
            bmr: restingCalories,
            intakeCalories: intake,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurnCalories,
            calorieDeficit: calorieDeficit,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            averageMealConfidence: averageConfidence(confirmedMeals),
            unconfirmedMealCount: todayMeals.filter { !$0.isConfirmed }.count,
            manualActiveCalories: manualActiveCalories,
            meals: confirmedMeals.map(mealText),
            workouts: todayExercises.map(exerciseText),
            recentDays: Array(recentSummaries.prefix(7)).map {
                DayTrend(date: $0.date, intakeCalories: $0.intakeCalories, calorieDeficit: $0.calorieDeficit, weightKg: valueIfPositive($0.weightKg))
            },
            analysis: nil
        )
        dailySnapshot.analysis = FatLossAnalyzer.analyze(snapshot: dailySnapshot)
        let analysis = dailySnapshot.analysis ?? FatLossAnalyzer.analyze(snapshot: dailySnapshot)

        let today = CoachDailyMetrics(
            date: todayStart,
            intakeCalories: intake,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurnCalories,
            calorieDeficit: calorieDeficit,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            confirmedMealCount: confirmedMeals.count,
            unconfirmedMealCount: todayMeals.filter { !$0.isConfirmed }.count,
            workoutCount: todayExercises.filter { !isDailyHealthAggregate($0) }.count,
            steps: steps,
            weightKg: weight,
            bodyFatPercentage: bodyFat,
            bodyMassIndex: bmi,
            sleepHours: sleepHours,
            waterMl: todayCheckIn?.waterMl,
            hungerLevel: todayCheckIn?.hungerLevel,
            mood: todayCheckIn?.mood ?? "",
            symptoms: todayCheckIn?.symptoms ?? "",
            note: todayCheckIn?.note ?? ""
        )

        let recentMeals = meals
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map(mealSnapshot)
        let recentExercises = exercises
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map(exerciseSnapshot)

        let recent7Days = mergedDays(summaries: recentSummaries, checkIns: recentCheckIns, limit: 7)
        let recent30Days = mergedDays(summaries: recentSummaries, checkIns: recentCheckIns, limit: 30)

        return CoachContextSnapshot(
            requestedAt: now,
            profile: CoachProfileSnapshot(
                goal: profile.goal.title,
                targetDailyDeficitKcal: deficitTarget,
                heightCm: profile.heightCm,
                weightKg: weight,
                bodyFatPercentage: bodyFat,
                bodyMassIndex: bmi,
                gender: profile.gender.title,
                age: profile.age,
                bmr: restingCalories
            ),
            today: today,
            todayMeals: todayMeals.sorted { $0.date < $1.date }.map(mealSnapshot),
            todayExercises: todayExercises.sorted { $0.date < $1.date }.map(exerciseSnapshot),
            recentMeals: Array(recentMeals),
            recentExercises: Array(recentExercises),
            recent7Days: recent7Days,
            recent30Days: recent30Days,
            foodOptions: foodOptions
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(40)
                .map(\.snapshot),
            trainingPlans: trainingPlans
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(5)
                .map(trainingPlanSnapshot),
            memory: memory?.snapshot,
            analysis: analysis,
            dataQualityNotes: analysis.dataQualityNotes
        )
    }

    private static func mealSnapshot(_ meal: MealEntry) -> CoachMealSnapshot {
        CoachMealSnapshot(
            id: meal.id,
            date: meal.date,
            mealType: meal.mealType.title,
            textDescription: meal.textDescription,
            totalCalories: meal.totalCalories,
            proteinGrams: meal.proteinGrams,
            carbsGrams: meal.carbsGrams,
            fatGrams: meal.fatGrams,
            isConfirmed: meal.isConfirmed
        )
    }

    private static func exerciseSnapshot(_ exercise: ExerciseEntry) -> CoachExerciseSnapshot {
        CoachExerciseSnapshot(
            id: exercise.id,
            date: exercise.date,
            source: exercise.source.title,
            workoutType: exercise.workoutType,
            durationMinutes: exercise.durationMinutes,
            activeCalories: exercise.activeCalories,
            steps: exercise.steps,
            isDailyHealthAggregate: isDailyHealthAggregate(exercise)
        )
    }

    private static func trainingPlanSnapshot(_ plan: TrainingPlan) -> CoachTrainingPlanSnapshot {
        CoachTrainingPlanSnapshot(
            id: plan.id,
            title: plan.title,
            goal: plan.goal.title,
            dailyCalories: plan.dailyCalories,
            proteinGrams: plan.proteinGrams,
            carbsGrams: plan.carbsGrams,
            fatGrams: plan.fatGrams,
            trainingDaysPerWeek: plan.trainingDaysPerWeek,
            summary: plan.summary,
            updatedAt: plan.updatedAt
        )
    }

    private static func mergedDays(
        summaries: [DailySummary],
        checkIns: [DailyCheckIn],
        limit: Int
    ) -> [CoachDaySummarySnapshot] {
        let calendar = Calendar.current
        var usedCheckInIDs = Set<UUID>()
        var days = summaries.prefix(limit).map { summary in
            let checkIn = checkIns.first { calendar.isDate($0.date, inSameDayAs: summary.date) }
            if let checkIn { usedCheckInIDs.insert(checkIn.id) }
            return CoachDaySummarySnapshot(
                date: calendar.startOfDay(for: summary.date),
                intakeCalories: summary.intakeCalories,
                activeCalories: summary.activeCalories,
                calorieDeficit: summary.calorieDeficit,
                weightKg: valueIfPositive(summary.weightKg) ?? valueIfPositive(checkIn?.weightKg),
                proteinGrams: summary.proteinGrams,
                carbsGrams: summary.carbsGrams,
                fatGrams: summary.fatGrams,
                sleepHours: checkIn?.sleepHours,
                waterMl: checkIn?.waterMl
            )
        }

        let extraCheckIns = checkIns
            .filter { !usedCheckInIDs.contains($0.id) }
            .prefix(max(0, limit - days.count))
            .map { checkIn in
                CoachDaySummarySnapshot(
                    date: calendar.startOfDay(for: checkIn.date),
                    intakeCalories: 0,
                    activeCalories: 0,
                    calorieDeficit: 0,
                    weightKg: valueIfPositive(checkIn.weightKg),
                    proteinGrams: 0,
                    carbsGrams: 0,
                    fatGrams: 0,
                    sleepHours: checkIn.sleepHours,
                    waterMl: checkIn.waterMl
                )
            }
        days.append(contentsOf: extraCheckIns)
        return Array(days.sorted { $0.date > $1.date }.prefix(limit))
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

    private static func isDailyHealthAggregate(_ exercise: ExerciseEntry) -> Bool {
        exercise.source == .healthKit && (exercise.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
    }

    private static func valueIfPositive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
