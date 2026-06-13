import Foundation

enum CSVExporter {
    static func export(meals: [MealEntry], exercises: [ExerciseEntry], summaries: [DailySummary]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitnessAssistantExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let mealURL = directory.appendingPathComponent("meals.csv")
        let exerciseURL = directory.appendingPathComponent("exercise.csv")
        let summaryURL = directory.appendingPathComponent("daily_summaries.csv")

        try write(csv: mealsCSV(meals), to: mealURL)
        try write(csv: exercisesCSV(exercises), to: exerciseURL)
        try write(csv: summariesCSV(summaries), to: summaryURL)

        return [mealURL, exerciseURL, summaryURL]
    }

    static func mealsCSV(_ meals: [MealEntry]) -> String {
        var rows = [["日期", "描述", "总热量(kcal)", "蛋白质(g)", "碳水(g)", "脂肪(g)", "置信度", "已确认", "食物明细"]]
        rows += meals.sorted { $0.date < $1.date }.map { meal in
            [
                DateFormatter.csvDateTime.string(from: meal.date),
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

    static func summariesCSV(_ summaries: [DailySummary]) -> String {
        var rows = [["日期", "摄入(kcal)", "活动消耗(kcal)", "基础消耗(kcal)", "总消耗(kcal)", "热量差(kcal)", "建议", "生成时间"]]
        rows += summaries.sorted { $0.date < $1.date }.map { summary in
            [
                DateFormatter.csvDate.string(from: summary.date),
                format(summary.intakeCalories),
                format(summary.activeCalories),
                format(summary.restingCalories),
                format(summary.totalBurnCalories),
                format(summary.calorieDeficit),
                summary.adviceText,
                DateFormatter.csvDateTime.string(from: summary.generatedAt)
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
