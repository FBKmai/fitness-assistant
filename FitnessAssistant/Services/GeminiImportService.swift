import Foundation

struct GeminiImportPreview: Identifiable {
    let id = UUID()
    var ageYears: Int?
    var heightCm: Double?
    var initialWeightKg: Double?
    var targetWeightKg: Double?
    var commonFoods: [String]
    var notes: [String]
}

enum GeminiImportError: LocalizedError {
    case invalidFile
    case noUsefulData

    var errorDescription: String? {
        switch self {
        case .invalidFile: "无法识别这份 Gemini JSON 对话文件"
        case .noUsefulData: "文件中没有提取到可导入的固定档案"
        }
    }
}

enum GeminiImportService {
    static func preview(data: Data) throws -> GeminiImportPreview {
        let json = try JSONSerialization.jsonObject(with: data)
        let records: [[String: Any]]
        if let values = json as? [[String: Any]] {
            records = values
        } else if let object = json as? [String: Any],
                  let values = object["messages"] as? [[String: Any]] {
            records = values
        } else {
            throw GeminiImportError.invalidFile
        }

        let userTexts = records.compactMap { record -> String? in
            guard (record["role"] as? String) == "user",
                  let contents = record["contents"] as? [[String: Any]] else { return nil }
            let texts = contents.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["content"] as? String
            }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }

        let joined = userTexts.joined(separator: "\n")
        let age = latestInt(
            patterns: [
                #"(\d{1,3})\s*岁"#
            ],
            in: userTexts
        ).flatMap { (10...100).contains($0) ? $0 : nil }
        let height = latestNumber(
            patterns: [
                #"身高(?:是|为|：|:)?\s*(\d{3}(?:\.\d+)?)\s*(?:cm|厘米|公分)?"#
            ],
            in: userTexts
        )
        let initialWeight = latestNumber(
            patterns: [
                #"2月27(?:日)?(?:是|为|：|:)?\s*(\d{2,3}(?:\.\d+)?)\s*(?:kg|公斤)"#,
                #"最开始(?:的)?体重(?:是|为|：|:)?\s*(\d{2,3}(?:\.\d+)?)"#
            ],
            in: userTexts
        )
        let targetWeight = latestNumber(
            patterns: [
                #"回到\s*(\d{2,3}(?:\.\d+)?)\s*(?:kg|公斤)"#,
                #"目标体重(?:是|为|：|:)?\s*(\d{2,3}(?:\.\d+)?)"#
            ],
            in: userTexts
        )

        let foodCandidates = [
            FoodCandidate(name: "鸡排", aliases: ["鸡排", "原味鸡排"], minimumOccurrences: 3),
            FoodCandidate(name: "亨氏黄芥末", aliases: ["亨氏黄芥末", "亨氏的纯黄芥末酱", "黄芥末酱", "黄芥末"], minimumOccurrences: 3),
            FoodCandidate(name: "牛肉饭", aliases: ["牛肉饭"], minimumOccurrences: 3),
            FoodCandidate(name: "鳕鱼", aliases: ["鳕鱼", "鳕鱼排"], minimumOccurrences: 3),
            FoodCandidate(name: "羊排", aliases: ["羊排"], minimumOccurrences: 3),
            FoodCandidate(name: "全麦吐司", aliases: ["全麦吐司", "全麦土司"], minimumOccurrences: 3),
            FoodCandidate(name: "鸡蛋", aliases: ["鸡蛋", "水煮蛋", "茶叶蛋"], minimumOccurrences: 5),
            FoodCandidate(name: "蒸饺", aliases: ["蒸饺"], minimumOccurrences: 5),
            FoodCandidate(name: "香蕉", aliases: ["香蕉"], minimumOccurrences: 3),
            FoodCandidate(name: "苹果气泡美式", aliases: ["苹果气泡美式"], minimumOccurrences: 2),
            FoodCandidate(name: "西兰花", aliases: ["西兰花"], minimumOccurrences: 3),
            FoodCandidate(name: "生菜", aliases: ["生菜"], minimumOccurrences: 3)
        ]
        let commonFoods = foodCandidates
            .map { candidate in
                (
                    candidate.name,
                    candidate.aliases.reduce(0) { $0 + occurrences(of: $1, in: joined) },
                    candidate.minimumOccurrences
                )
            }
            .filter { $0.1 >= $0.2 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }

        var notes: [String] = [
            "只导入固定身体档案和常吃食物，不导入每日记录、旧建议或对话。",
            "对话中的年龄不会换算成生日；请保留或手动确认设置页生日。"
        ]
        if let age {
            notes.append("识别到年龄 \(age) 岁，仅用于核对，不会自动修改生日。")
        }
        if height == nil { notes.append("没有识别到明确身高。") }
        if initialWeight == nil { notes.append("没有识别到明确初始体重。") }

        let preview = GeminiImportPreview(
            ageYears: age,
            heightCm: height,
            initialWeightKg: initialWeight,
            targetWeightKg: targetWeight,
            commonFoods: commonFoods,
            notes: notes
        )
        guard age != nil || height != nil || initialWeight != nil || targetWeight != nil || !commonFoods.isEmpty else {
            throw GeminiImportError.noUsefulData
        }
        return preview
    }

    private struct FoodCandidate {
        var name: String
        var aliases: [String]
        var minimumOccurrences: Int
    }

    private static func latestNumber(patterns: [String], in texts: [String]) -> Double? {
        for text in texts.reversed() {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(
                        in: text,
                        range: NSRange(text.startIndex..., in: text)
                      ),
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text),
                      let value = Double(text[range]) else { continue }
                return value
            }
        }
        return nil
    }

    private static func latestInt(patterns: [String], in texts: [String]) -> Int? {
        latestNumber(patterns: patterns, in: texts).map { Int($0.rounded()) }
    }

    private static func occurrences(of term: String, in text: String) -> Int {
        guard !term.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
