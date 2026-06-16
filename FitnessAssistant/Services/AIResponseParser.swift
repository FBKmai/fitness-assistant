import Foundation

enum AIResponseParser {
    static func decodeJSONObject<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let json = extractJSONObject(from: content)
        guard let data = json.data(using: .utf8) else {
            AppLog.error("解析 \(T.self) 失败：返回内容无法转为 UTF-8 数据。原始返回：\(content)", category: "AI解析")
            throw AIClientError.invalidJSON(content)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLog.error(
                "解析 \(T.self) 失败（返回 \(content.count) 字符）：\(error)\n原始返回：\(content)",
                category: "AI解析"
            )
            throw AIClientError.invalidJSON(content)
        }
    }

    /// 当严格 JSON 解析失败（最常见于模型把输出截断、JSON 没闭合）时，
    /// 尽量从原始文本里抢救出 `replyText` 字段的字符串值，让用户至少能看到回答正文。
    /// 返回 nil 表示连正文都抢救不出来（例如根本没开始写 replyText）。
    static func salvageReplyText(from content: String) -> String? {
        guard let keyRange = content.range(of: "\"replyText\"") else { return nil }
        let afterKey = content[keyRange.upperBound...]
        guard let colon = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = afterKey[afterKey.index(after: colon)...]
        guard let openQuote = afterColon.firstIndex(of: "\"") else { return nil }

        var result = ""
        var index = afterColon.index(after: openQuote)
        var escaped = false
        while index < afterColon.endIndex {
            let ch = afterColon[index]
            if escaped {
                switch ch {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                default: result.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                break // 字符串正常结束
            } else {
                result.append(ch)
            }
            index = afterColon.index(after: index)
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 解析教练回复。教练现在以「自然文本为主 + 末尾可选 ```json 结构化块」的格式返回，
    /// 本方法绝不抛错：正文一定能拿到；结构化块（场景/建议记录/记忆）best-effort 解析，
    /// 失败就只丢按钮、不丢正文。同时兼容模型直接返回 JSON 对象的旧格式。
    static func parseCoachReply(from content: String) -> CoachReplyResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return CoachReplyResult(replyText: "（AI 没有返回内容，请重试）") }

        // 1) 围栏格式：正文在前，结构化数据在 ```json 块里
        if let fenced = extractFencedJSON(from: trimmed) {
            let extras = decodeCoachExtras(from: fenced.json)
            var replyText = fenced.textBefore
            if replyText.isEmpty,
               let rt = extras?.replyText?.trimmingCharacters(in: .whitespacesAndNewlines), !rt.isEmpty {
                replyText = rt
            }
            if replyText.isEmpty { replyText = trimmed }
            return CoachReplyResult(
                replyText: replyText,
                scenario: extras?.scenario ?? .general,
                suggestedRecords: extras?.suggestedRecords ?? [],
                memoryPatch: extras?.memoryPatch,
                riskLevel: (extras?.riskLevel?.isEmpty == false) ? extras!.riskLevel! : "normal"
            )
        }

        // 2) 模型直接返回了 JSON 对象（旧格式或忽略了指令）
        if trimmed.hasPrefix("{") {
            if let data = extractJSONObject(from: trimmed).data(using: .utf8),
               let full = try? JSONDecoder().decode(CoachReplyResult.self, from: data),
               !full.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return full
            }
            if let salvaged = salvageReplyText(from: trimmed) {
                return CoachReplyResult(replyText: salvaged)
            }
        }

        // 3) 纯自然语言回答
        return CoachReplyResult(replyText: trimmed)
    }

    /// 提取第一个 ``` 代码块：返回围栏前的正文与块内文本。容忍块未闭合（被截断）。
    private static func extractFencedJSON(from text: String) -> (textBefore: String, json: String)? {
        guard let fence = text.range(of: "```") else { return nil }
        let before = String(text[..<fence.lowerBound])
        var rest = text[fence.upperBound...]
        // 跳过可选的语言标识行（如 json）
        if let newline = rest.firstIndex(of: "\n") {
            let lang = rest[..<newline].trimmingCharacters(in: .whitespaces)
            if lang.count <= 8 {
                rest = rest[rest.index(after: newline)...]
            }
        }
        let json: Substring
        if let close = rest.range(of: "```") {
            json = rest[..<close.lowerBound]
        } else {
            json = rest // 未闭合（截断），取剩余全部
        }
        return (
            before.trimmingCharacters(in: .whitespacesAndNewlines),
            String(json).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func decodeCoachExtras(from json: String) -> CoachReplyExtras? {
        let object = extractJSONObject(from: json)
        guard let data = object.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoachReplyExtras.self, from: data)
    }

    static func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

/// 教练回复里可选的结构化部分（来自正文末尾的 ```json 块）。逐字段容错解析，
/// 单个字段坏掉不影响其它字段。
private struct CoachReplyExtras: Decodable {
    var replyText: String?
    var scenario: CoachScenario?
    var riskLevel: String?
    var suggestedRecords: [CoachSuggestedRecord]?
    var memoryPatch: CoachMemoryPatch?

    enum CodingKeys: String, CodingKey {
        case replyText, scenario, riskLevel, suggestedRecords, memoryPatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replyText = (try? container.decodeIfPresent(String.self, forKey: .replyText)) ?? nil
        let rawScenario = (try? container.decodeIfPresent(String.self, forKey: .scenario)) ?? nil
        scenario = rawScenario.flatMap { CoachScenario(rawValue: $0) }
        riskLevel = (try? container.decodeIfPresent(String.self, forKey: .riskLevel)) ?? nil
        suggestedRecords = (try? container.decodeIfPresent([CoachSuggestedRecord].self, forKey: .suggestedRecords)) ?? nil
        memoryPatch = (try? container.decodeIfPresent(CoachMemoryPatch.self, forKey: .memoryPatch)) ?? nil
    }
}
