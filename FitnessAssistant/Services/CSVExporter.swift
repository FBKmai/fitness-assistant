import Foundation

enum CSVExporter {
    static func export(
        meals: [MealEntry],
        exercises: [ExerciseEntry],
        dayLogs: [DayLog] = []
    ) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitnessAssistantExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let mealURL = directory.appendingPathComponent("meals.csv")
        let exerciseURL = directory.appendingPathComponent("exercise.csv")
        let dayLogURL = directory.appendingPathComponent("day_log.csv")

        try write(csv: mealsCSV(meals), to: mealURL)
        try write(csv: exercisesCSV(exercises), to: exerciseURL)
        try write(csv: dayLogsCSV(dayLogs), to: dayLogURL)

        return [mealURL, exerciseURL, dayLogURL]
    }

    static func mealsCSV(_ meals: [MealEntry]) -> String {
        var rows = [["日期", "餐别", "描述", "总热量(kcal)", "蛋白质(g)", "碳水(g)", "脂肪(g)", "置信度", "已确认", "食物明细"]]
        rows += meals.sorted { $0.date < $1.date }.map { meal in
            [
                DateFormatter.csvDateTime.string(from: meal.date),
                meal.mealType.title,
                meal.textDescription,
                format(meal.totalCalories),
                format(meal.proteinGrams),
                format(meal.carbsGrams),
                format(meal.fatGrams),
                format(meal.confidence),
                meal.isConfirmed ? "是" : "否",
                meal.estimatedItems.map { "\($0.name): \(format($0.calories))kcal" }.joined(separator: "；")
            ]
        }
        return encode(rows)
    }

    static func exercisesCSV(_ exercises: [ExerciseEntry]) -> String {
        var rows = [["日期", "来源", "类型", "时长(分钟)", "活动热量(kcal)", "步数", "HealthKit ID"]]
        rows += exercises.sorted { $0.date < $1.date }.map { exercise in
            [
                DateFormatter.csvDateTime.string(from: exercise.date),
                exercise.source.title,
                exercise.workoutType,
                format(exercise.durationMinutes),
                format(exercise.activeCalories),
                format(exercise.steps),
                exercise.healthKitWorkoutID ?? ""
            ]
        }
        return encode(rows)
    }

    static func dayLogsCSV(_ logs: [DayLog]) -> String {
        var rows = [["日期", "摄入(kcal)", "活动消耗(kcal)", "基础消耗(kcal)", "总消耗(kcal)", "热量差(kcal)", "蛋白质(g)", "碳水(g)", "脂肪(g)", "体重(kg)", "体脂率(%)", "BMI", "睡眠(小时)", "饮水(ml)", "饥饿感(1-10)", "心情", "症状", "备注", "建议", "身体数据同步时间", "生成时间", "更新时间"]]
        rows += logs.sorted { $0.date < $1.date }.map { log in
            [
                DateFormatter.csvDate.string(from: log.date),
                format(log.intakeCalories),
                format(log.activeCalories),
                format(log.restingCalories),
                format(log.totalBurnCalories),
                format(log.calorieDeficit),
                format(log.proteinGrams),
                format(log.carbsGrams),
                format(log.fatGrams),
                log.weightKg > 0 ? format(log.weightKg) : "",
                log.bodyFatPercentage.map(format) ?? "",
                log.bodyMassIndex.map(format) ?? "",
                log.sleepHours.map(format) ?? "",
                log.waterMl.map(format) ?? "",
                log.hungerLevel.map(String.init) ?? "",
                log.mood,
                log.symptoms,
                log.note,
                log.adviceText,
                log.bodyMetricsSyncedAt.map { DateFormatter.csvDateTime.string(from: $0) } ?? "",
                log.generatedAt.map { DateFormatter.csvDateTime.string(from: $0) } ?? "",
                DateFormatter.csvDateTime.string(from: log.updatedAt)
            ]
        }
        return encode(rows)
    }

    private static func write(csv: String, to url: URL) throws {
        let content = "\u{FEFF}" + csv
        try content.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    private static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
