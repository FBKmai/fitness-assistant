import Foundation

enum AIResponseParser {
    static func decodeJSONObject<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let json = extractJSONObject(from: content)
        guard let data = json.data(using: .utf8) else { throw AIClientError.invalidJSON(content) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIClientError.invalidJSON(content)
        }
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
