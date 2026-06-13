import XCTest
@testable import FitnessAssistant

final class AIResponseParserTests: XCTestCase {
    func testDecodesJSONWrappedInMarkdown() throws {
        let content = """
        ```json
        {"summary":"正常","tomorrowDietAdvice":"多吃蛋白质","tomorrowExerciseAdvice":"快走","recoveryAdvice":"早睡"}
        ```
        """

        let advice = try AIResponseParser.decodeJSONObject(DailyAdvice.self, from: content)

        XCTAssertEqual(advice.summary, "正常")
        XCTAssertEqual(advice.tomorrowExerciseAdvice, "快走")
    }

    func testThrowsForInvalidJSON() {
        XCTAssertThrowsError(try AIResponseParser.decodeJSONObject(DailyAdvice.self, from: "不是 JSON"))
    }
}
