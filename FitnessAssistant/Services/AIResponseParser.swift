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
