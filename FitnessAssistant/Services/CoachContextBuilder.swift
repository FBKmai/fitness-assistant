import Foundation

enum CoachContextBuilder {
    static func build(
        profile: UserProfile,
        dayLogs: [DayLog],
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        foodOptions: [FoodOption],
        trainingPlans: [TrainingPlan],
        memory: CoachMemory?,
        carryovers: [CoachDailyCarryoverSnapshot] = [],
        now: Date = .now,
        healthSnapshot: HealthSnapshot? = nil
    ) -> CoachContextSnapshot {
        let calendar = Calendar.current
        let todayInterval = calendar.dayInterval(containing: now)
        let todayStart = todayInterval.start
        let todayLog = dayLogs.first { calendar.isDate($0.date, inSameDayAs: now) }

        let todayMeals = meals.filter { todayInterval.contains($0.date) }
        let todayExercises = exercises.filter { todayInterval.contains($0.date) }

        // 今日派生指标统一走唯一聚合源：活动消耗去重、目标缺口口径、体重回退链、analysis、近 7 天趋势。
        let metrics = DayMetricsCalculator.metrics(
            for: now,
            profile: profile,
            meals: meals,
            exercises: exercises,
            dayLogs: dayLogs,
            trainingPlans: trainingPlans,
            healthSnapshot: healthSnapshot
        )
        let analysis = metrics.analysis

        let dailyHealthAggregate = todayExercises.first(where: isDailyHealthAggregate)
        let steps = healthSnapshot?.steps ?? dailyHealthAggregate?.steps ?? 0

        let today = CoachDailyMetrics(
            date: todayStart,
            intakeCalories: metrics.intakeCalories,
            activeCalories: metrics.activeCalories,
            restingCalories: metrics.restingCalories,
            totalBurnCalories: metrics.totalBurnCalories,
            calorieDeficit: metrics.calorieDeficit,
            proteinGrams: metrics.proteinGrams,
            carbsGrams: metrics.carbsGrams,
            fatGrams: metrics.fatGrams,
            confirmedMealCount: todayMeals.count,
            unconfirmedMealCount: 0,
            workoutCount: todayExercises.filter { !isDailyHealthAggregate($0) }.count,
            steps: steps,
            weightKg: metrics.weightKg,
            bodyFatPercentage: metrics.bodyFatPercentage,
            bodyMassIndex: metrics.bodyMassIndex,
            sleepHours: healthSnapshot?.sleepHours ?? todayLog?.sleepHours,
            waterMl: todayLog?.waterMl,
            hungerLevel: todayLog?.hungerLevel,
            mood: todayLog?.mood ?? "",
            symptoms: todayLog?.symptoms ?? "",
            note: todayLog?.note ?? ""
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

        // 单一日表后不再需要 mergedDays 缝合：直接对 DayLog 取近 N 天。
        let recentLogs = dayLogs
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }
        let recent7Days = recentDaySnapshots(recentLogs, limit: 7)
        let recent30Days = recentDaySnapshots(recentLogs, limit: 30)

        return CoachContextSnapshot(
            requestedAt: now,
            profile: CoachProfileSnapshot(
                goal: profile.goal.title,
                targetDailyDeficitKcal: metrics.effectiveDeficitTarget,
                heightCm: profile.heightCm,
                weightKg: metrics.weightKg ?? profile.currentWeightKg,
                bodyFatPercentage: metrics.bodyFatPercentage,
                bodyMassIndex: metrics.bodyMassIndex,
                gender: profile.gender.title,
                age: profile.age,
                bmr: metrics.restingCalories
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
            recentCarryovers: carryovers
                .filter { $0.date < todayStart }
                .sorted { $0.date > $1.date }
                .prefix(7)
                .map { $0 },
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

    private static func recentDaySnapshots(_ logs: [DayLog], limit: Int) -> [CoachDaySummarySnapshot] {
        let calendar = Calendar.current
        return logs.prefix(limit).map { log in
            CoachDaySummarySnapshot(
                date: calendar.startOfDay(for: log.date),
                intakeCalories: log.intakeCalories,
                activeCalories: log.activeCalories,
                calorieDeficit: log.calorieDeficit,
                weightKg: valueIfPositive(log.weightKg),
                proteinGrams: log.proteinGrams,
                carbsGrams: log.carbsGrams,
                fatGrams: log.fatGrams,
                sleepHours: log.sleepHours,
                waterMl: log.waterMl
            )
        }
    }

    private static func isDailyHealthAggregate(_ exercise: ExerciseEntry) -> Bool {
        exercise.source == .healthKit && (exercise.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
    }

    private static func valueIfPositive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
