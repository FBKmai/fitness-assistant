import Foundation
import Combine

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case emptyResponse
    case invalidResponse(Int, String)
    case invalidJSON(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先在设置中填写 API Key"
        case .invalidBaseURL:
            "AI Base URL 无效"
        case .emptyResponse:
            "AI 没有返回内容"
        case .invalidResponse(let status, let body):
            "AI 请求失败：HTTP \(status) \(body)"
        case .invalidJSON(let content):
            "AI 返回的 JSON 无法解析：\(content)"
        case .transport(let message):
            message
        }
    }
}

final class AIClient: ObservableObject {
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func estimateMeal(text: String, imageData: Data?, settings: AISettings) async throws -> MealEstimate {
        try await estimateMeal(text: text, imageDataList: imageData.map { [$0] } ?? [], settings: settings)
    }

    func estimateMeal(text: String, imageDataList: [Data], settings: AISettings) async throws -> MealEstimate {
        let systemPrompt = """
        你是一个营养记录助手。根据用户的文字或餐食照片估算热量和三大营养素。
        只返回 JSON，不要使用 markdown。所有数值使用 kcal 或克。
        JSON 格式：
        {
          "items": [{"name": "食物名", "calories": 0, "proteinGrams": 0, "carbsGrams": 0, "fatGrams": 0, "note": "估算依据"}],
          "totalCalories": 0,
          "proteinGrams": 0,
          "carbsGrams": 0,
          "fatGrams": 0,
          "confidence": 0.0,
          "summary": "一句中文总结"
        }
        """

        let userText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请根据图片估算这餐的热量。"
            : text

        let userContent: ChatContent
        if imageDataList.isEmpty {
            userContent = .text(userText)
        } else {
            var parts: [ChatContentPart] = [.text(userText)]
            parts += imageDataList.map { imageData in
                .imageURL("data:image/jpeg;base64,\(imageData.base64EncodedString())")
            }
            userContent = .parts(parts)
        }

        let model = imageDataList.isEmpty ? settings.modelName : settings.visionModelName
        let content = try await complete(
            model: model,
            settings: settings,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: userContent)
            ],
            temperature: 0.2,
            jsonMode: true
        )

        return try AIResponseParser.decodeJSONObject(MealEstimate.self, from: content)
    }

    func generateDailyAdvice(snapshot: DailySnapshot, settings: AISettings) async throws -> DailyAdvice {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文健身饮食监督助手。根据当天摄入、消耗、热量差、饮食和运动记录，为用户生成第二天建议。
        目标是减脂，建议要现实、可执行，不提供医疗诊断。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "summary": "当天情况总结",
          "tomorrowDietAdvice": "第二天饮食建议",
          "tomorrowExerciseAdvice": "第二天运动建议",
          "recoveryAdvice": "恢复和注意事项"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            settings: settings,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true
        )

        return try AIResponseParser.decodeJSONObject(DailyAdvice.self, from: content)
    }

    func testConnection(settings: AISettings) async throws -> String {
        let content = try await complete(
            model: settings.modelName,
            settings: settings,
            messages: [
                ChatMessage(role: "system", content: .text("You are a connectivity test endpoint. Reply with exactly OK.")),
                ChatMessage(role: "user", content: .text("Reply OK."))
            ],
            temperature: 0,
            jsonMode: false
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OK" : trimmed
    }

    private func complete(
        model: String,
        settings: AISettings,
        messages: [ChatMessage],
        temperature: Double,
        jsonMode: Bool
    ) async throws -> String {
        guard let apiKey = try keychain.read(settings.apiKeychainKey), !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        guard let url = chatCompletionsURL(from: settings.baseURL) else {
            throw AIClientError.invalidBaseURL
        }

        let requestBody = ChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            responseFormat: jsonMode ? ChatResponseFormat(type: "json_object") : nil,
            maxTokens: jsonMode ? 2000 : 32
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIClientError.transport(Self.transportMessage(for: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.emptyResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.invalidResponse(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIClientError.emptyResponse
        }
        return content
    }

    private func chatCompletionsURL(from baseURL: String) -> URL? {
        var trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.localizedCaseInsensitiveContains("://") {
            trimmedBaseURL = "https://\(trimmedBaseURL)"
        }
        while trimmedBaseURL.hasSuffix("/") {
            trimmedBaseURL.removeLast()
        }
        if trimmedBaseURL.hasSuffix("/chat/completions") {
            return URL(string: trimmedBaseURL)
        }
        return URL(string: "\(trimmedBaseURL)/chat/completions")
    }

    private static func transportMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed,
                NSURLErrorServerCertificateHasBadDate,
                NSURLErrorServerCertificateUntrusted,
                NSURLErrorServerCertificateHasUnknownRoot,
                NSURLErrorServerCertificateNotYetValid,
                NSURLErrorClientCertificateRejected,
                NSURLErrorClientCertificateRequired:
                return "TLS错误导致安全连接失败。请确认 Base URL 使用 https://api.deepseek.com，不要带空格，并检查手机时间和网络代理。"
            case NSURLErrorCannotFindHost:
                return "无法找到 AI 服务域名。请检查 Base URL，例如 DeepSeek 使用 https://api.deepseek.com。"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "无法连接 AI 服务。请检查网络、代理或稍后重试。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var responseFormat: ChatResponseFormat?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponseFormat: Encodable {
    var type: String
}

private struct ChatMessage: Encodable {
    var role: String
    var content: ChatContent
}

private enum ChatContent: Encodable {
    case text(String)
    case parts([ChatContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private struct ChatContentPart: Encodable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    static func text(_ value: String) -> ChatContentPart {
        ChatContentPart(type: "text", text: value, imageURL: nil)
    }

    static func imageURL(_ value: String) -> ChatContentPart {
        ChatContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: value))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
    }
}

private struct ImageURL: Encodable {
    var url: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}
