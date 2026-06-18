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

    func testNewProposalsProtocolTakesPriorityOverLegacyRecords() throws {
        let content = """
        {
          "replyText": "请先确认体重更正。",
          "proposals": [
            {
              "action": "update",
              "kind": "checkIn",
              "title": "体重更正",
              "oldValueSummary": "89.35 kg",
              "weightKg": 79.35
            }
          ],
          "suggestedRecords": [
            {
              "kind": "meal",
              "title": "旧协议记录"
            }
          ]
        }
        """

        let result = try AIResponseParser.decodeJSONObject(CoachReplyResult.self, from: content)

        XCTAssertEqual(result.proposals.count, 1)
        XCTAssertEqual(result.proposals.first?.action, .update)
        XCTAssertEqual(result.proposals.first?.kind, .checkIn)
        XCTAssertEqual(result.proposals.first?.weightKg ?? 0, 79.35, accuracy: 0.001)
    }

    func testGeminiImportExtractsOnlyStableProfileAndCommonFoods() throws {
        let records: [[String: Any]] = [
            [
                "role": "user",
                "contents": [
                    ["type": "text", "content": "我的身高是172，24岁，静息心率54。"]
                ]
            ],
            [
                "role": "user",
                "contents": [
                    ["type": "text", "content": "2月27是86kg。"]
                ]
            ],
            [
                "role": "user",
                "contents": [
                    ["type": "text", "content": "鸡排鸡排鸡排，黄芥末酱，黄芥末，亨氏的纯黄芥末酱。"]
                ]
            ],
            [
                "role": "user",
                "contents": [
                    ["type": "text", "content": "今早体重89.35，是79.35打错了。"]
                ]
            ],
            [
                "role": "model",
                "contents": [
                    ["type": "text", "content": "这段回答不应作为导入档案来源。"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: records)

        let preview = try GeminiImportService.preview(data: data)

        XCTAssertEqual(preview.ageYears, 24)
        XCTAssertEqual(preview.heightCm ?? 0, 172, accuracy: 0.001)
        XCTAssertEqual(preview.initialWeightKg ?? 0, 86, accuracy: 0.001)
        XCTAssertNil(preview.targetWeightKg)
        XCTAssertTrue(preview.commonFoods.contains("鸡排"))
        XCTAssertTrue(preview.commonFoods.contains("亨氏黄芥末"))
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

    func testCoachDailyCarryoverDefaultsMissingArrays() throws {
        let content = #"{"summary":"今天晚餐偏咸，明天重点控钠补水。","nextDayFocus":["早餐补蛋白"]}"#

        let carryover = try AIResponseParser.decodeJSONObject(CoachDailyCarryover.self, from: content)

        XCTAssertEqual(carryover.summary, "今天晚餐偏咸，明天重点控钠补水。")
        XCTAssertEqual(carryover.importantNotes, [])
        XCTAssertEqual(carryover.foodWarnings, [])
        XCTAssertEqual(carryover.trainingWarnings, [])
        XCTAssertEqual(carryover.nextDayFocus, ["早餐补蛋白"])
    }
}
