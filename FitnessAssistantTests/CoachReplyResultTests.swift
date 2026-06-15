import XCTest
@testable import FitnessAssistant

final class CoachReplyResultTests: XCTestCase {
    func testDecodesCoachReplyWrappedInMarkdown() throws {
        let content = """
        ```json
        {
          "replyText": "晚餐绿灯，米饭吃半碗，牛肉加倍。",
          "scenario": "foodDecision",
          "riskLevel": "normal",
          "suggestedRecords": [
            {
              "kind": "meal",
              "title": "牛肉饭",
              "mealTypeRaw": "dinner",
              "textDescription": "双倍牛肉饭，米饭半碗",
              "totalCalories": 520,
              "proteinGrams": 45,
              "carbsGrams": 55,
              "fatGrams": 12
            }
          ],
          "memoryPatch": {
            "foodPreferences": ["牛肉饭"],
            "avoidances": ["高钠腌菜"]
          }
        }
        ```
        """

        let result = try AIResponseParser.decodeJSONObject(CoachReplyResult.self, from: content)

        XCTAssertEqual(result.scenario, .foodDecision)
        XCTAssertEqual(result.suggestedRecords.count, 1)
        XCTAssertEqual(result.memoryPatch?.foodPreferences, ["牛肉饭"])

        let meal = try XCTUnwrap(result.suggestedRecords.first?.makeMealEntry())
        XCTAssertEqual(meal.mealType, .dinner)
        XCTAssertEqual(meal.textDescription, "双倍牛肉饭，米饭半碗")
        XCTAssertEqual(meal.totalCalories, 520)
        XCTAssertTrue(meal.isConfirmed)
    }

    func testCoachReplyDefaultsEmptyCollections() throws {
        let result = try AIResponseParser.decodeJSONObject(CoachReplyResult.self, from: #"{"replyText":"继续保持"}"#)

        XCTAssertEqual(result.replyText, "继续保持")
        XCTAssertEqual(result.scenario, .general)
        XCTAssertEqual(result.suggestedRecords.count, 0)
        XCTAssertEqual(result.riskLevel, "normal")
    }

    func testSuggestedExerciseAndCheckInConversions() {
        let exerciseRecord = CoachSuggestedRecord(
            kind: .exercise,
            title: "椭圆机",
            workoutType: "椭圆机",
            durationMinutes: 35,
            activeCalories: 320,
            steps: 1000
        )
        let exercise = exerciseRecord.makeExerciseEntry()

        XCTAssertEqual(exercise?.workoutType, "椭圆机")
        XCTAssertEqual(exercise?.activeCalories ?? 0, 320)

        let checkInRecord = CoachSuggestedRecord(
            kind: .checkIn,
            title: "今日打卡",
            weightKg: 80.2,
            sleepHours: 6.5,
            waterMl: 2200,
            symptoms: "鼻塞"
        )
        let checkIn = DailyCheckIn()
        checkIn.apply(checkInRecord)

        XCTAssertEqual(checkIn.weightKg, 80.2)
        XCTAssertEqual(checkIn.sleepHours ?? 0, 6.5)
        XCTAssertEqual(checkIn.waterMl ?? 0, 2200)
        XCTAssertEqual(checkIn.symptoms, "鼻塞")
    }
}
