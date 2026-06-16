import XCTest
@testable import FitnessAssistant

final class CSVExporterTests: XCTestCase {
    func testCSVQuotesCommasQuotesAndNewlines() {
        let meal = MealEntry(
            textDescription: "鸡胸肉, 米饭 \"半碗\"\n加青菜",
            estimatedItems: [
                MealFoodItem(name: "鸡胸肉", calories: 180, proteinGrams: 32, carbsGrams: 0, fatGrams: 4)
            ],
            totalCalories: 520,
            proteinGrams: 40,
            carbsGrams: 60,
            fatGrams: 10,
            confidence: 0.8,
            isConfirmed: true
        )

        let csv = CSVExporter.mealsCSV([meal])

        XCTAssertTrue(csv.contains("\"鸡胸肉, 米饭 \"\"半碗\"\""))
        XCTAssertTrue(csv.contains("鸡胸肉: 180.0kcal"))
    }

    func testExportWritesUTF8BOMFiles() throws {
        let urls = try CSVExporter.export(meals: [], exercises: [], dayLogs: [])
        let data = try Data(contentsOf: urls[0])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }
}
