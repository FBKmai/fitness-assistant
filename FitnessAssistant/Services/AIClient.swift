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

    func estimateMeal(text: String, imageData: Data?, settings: AISettings, bodyContext: String? = nil) async throws -> MealEstimate {
        try await estimateMeal(text: text, imageDataList: imageData.map { [$0] } ?? [], settings: settings, bodyContext: bodyContext)
    }

    func estimateMeal(text: String, imageDataList: [Data], settings: AISettings, bodyContext: String? = nil) async throws -> MealEstimate {
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

        let baseText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请根据图片估算这餐的热量。"
            : text
        // 附上身体资料，辅助模型判断份量（作用有限，仅供参考）。
        let userText = bodyContext.map { "\(baseText)\n\n（用户身体资料，仅供份量判断参考：\($0)）" } ?? baseText

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

        // 带图走视觉模型（MiMo），纯文字走文字模型（DeepSeek），各用各自的 Base URL 和 Key。
        let isVision = !imageDataList.isEmpty
        let content = try await complete(
            model: isVision ? settings.visionModelName : settings.modelName,
            baseURL: isVision ? settings.visionBaseURL : settings.baseURL,
            apiKeychainKey: isVision ? settings.visionAPIKeychainKey : settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: userContent)
            ],
            temperature: 0.2,
            jsonMode: true,
            maxTokens: 4000
        )

        return try AIResponseParser.decodeJSONObject(MealEstimate.self, from: content)
    }

    func generateDailyAdvice(snapshot: DailySnapshot, settings: AISettings) async throws -> DailyAdvice {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文健身饮食监督助手。下面的 JSON 包含用户的身体数据（身高、体重、体脂率、BMI、性别、年龄、基础代谢 bmr）、
        当天摄入/消耗/热量差、三大营养素合计、每餐与运动记录、近 7 天趋势 recentDays（每天的热量缺口和体重），
        以及 analysis 字段中的本地规则化减脂判断（缺口范围、蛋白目标、风险提醒和数据质量）。
        请综合这些数据为用户生成第二天建议：
        1. 结合身高、体重、体脂率、BMI、年龄、性别与 bmr 判断当天摄入是否过低或过高；
        2. 结合三大营养素点评蛋白质、碳水、脂肪是否合理（减脂期重点关注蛋白质是否充足）；
        3. 结合 recentDays 趋势说明最近进展（热量缺口是否稳定、体重变化方向）；若数据不足则说明无法判断趋势。
        4. 优先尊重 analysis 的风险和数据质量判断，不要建议极端节食或用过量运动弥补饮食。
        5. 热量差公式是：基础代谢 bmr + 活动消耗 activeCalories - 摄入 intakeCalories；targetDailyDeficitKcal 只用于判断是否达标，不参与热量差计算。
        6. todayMealAdvice 要包含今天剩余早餐/午餐/晚餐安排建议，snackAdvice 要单独给零嘴建议。
        目标是减脂，建议要现实、可执行、个性化，不提供医疗诊断。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "summary": "当天情况总结",
          "todayMealAdvice": "今天剩余三餐或下一餐怎么安排",
          "snackAdvice": "今天零嘴或加餐建议",
          "tomorrowDietAdvice": "第二天饮食建议",
          "tomorrowExerciseAdvice": "第二天运动建议",
          "recoveryAdvice": "恢复和注意事项"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 2000
        )

        return try AIResponseParser.decodeJSONObject(DailyAdvice.self, from: content)
    }

    func generateMealAdvice(snapshot: MealAdviceSnapshot, settings: AISettings) async throws -> MealAdviceResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文减脂饮食教练。用户刚保存了一条饮食记录，JSON 中包含这一顿的餐别、吃饭时间、热量和三大营养素，
        以及今天所有已记录饮食、今日热量差、目标缺口和本地规则化 analysis。
        请评价这一顿是否适合减脂，并给出下一顿怎么吃的建议。
        要具体、直接、可执行；不要空泛鼓励，不提供医疗诊断，不建议极端节食。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "mealReview": "对刚保存这顿的评价",
          "nextMealAdvice": "下一顿具体怎么吃",
          "snackAdvice": "零嘴或加餐建议",
          "caution": "风险、记录误差或需要补充的数据"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 1800
        )

        return try AIResponseParser.decodeJSONObject(MealAdviceResponse.self, from: content)
    }

    func generateDietCoachAdvice(snapshot: DietCoachSnapshot, settings: AISettings) async throws -> DietCoachAdvice {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文减脂饮食顾问。用户会问“现在这一餐怎么吃”一类问题。
        下面的 JSON 包含用户身体资料（含体重、体脂率和 BMI，如 Apple 健康当天有数据）、今日已吃内容、今日运动/消耗、近 7 天趋势、以及本地规则化 analysis。
        请回答用户当前这一餐该怎么吃，并考虑接下来是否还有运动、今天已经吃了什么、蛋白质是否够、热量缺口是否过大或过小。
        要具体到可执行食物组合和份量范围，例如“1 份掌心大小鸡胸/鱼/豆腐 + 1 碗米饭的 1/2-1 碗 + 2 拳蔬菜”。
        如果用户提到晚上运动，请说明中午/下午是否需要碳水和蛋白，避免空腹硬撑或暴食补偿。
        不提供医疗诊断，不建议极端节食。若数据不足，要明确说明不确定性。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "currentMealAdvice": "现在这一餐怎么吃",
          "workoutFuelAdvice": "如果接下来有运动，如何安排训练前后补给",
          "remainingDayPlan": "今天剩余饮食和活动安排",
          "caution": "需要注意的风险或数据不足"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 2000
        )

        return try AIResponseParser.decodeJSONObject(DietCoachAdvice.self, from: content)
    }

    func testConnection(settings: AISettings) async throws -> String {
        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text("You are a connectivity test endpoint. Reply with exactly OK.")),
                ChatMessage(role: "user", content: .text("Reply OK."))
            ],
            temperature: 0,
            jsonMode: false,
            maxTokens: 32,
            timeout: 30
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OK" : trimmed
    }

    /// 详细诊断：依次验证「文字模型 · DeepSeek」和「视觉模型 · MiMo」两套配置
    /// （二者 Base URL / Key / 模型各自独立），把每一步实时回调出来，不抛异常。
    @MainActor
    func diagnose(settings: AISettings, onLine: @escaping (String) -> Void) async {
        onLine("【文字模型 · DeepSeek】")
        await diagnoseEndpoint(
            baseURL: settings.baseURL,
            model: settings.modelName,
            apiKeychainKey: settings.apiKeychainKey,
            onLine: onLine
        )
        onLine("")
        onLine("【视觉模型 · MiMo】")
        await diagnoseEndpoint(
            baseURL: settings.visionBaseURL,
            model: settings.visionModelName,
            apiKeychainKey: settings.visionAPIKeychainKey,
            onLine: onLine
        )
    }

    /// 对单个 OpenAI 兼容端点做一次最小连通性请求，每一步通过 onLine 回调。
    @MainActor
    private func diagnoseEndpoint(
        baseURL: String,
        model: String,
        apiKeychainKey: String,
        onLine: @escaping (String) -> Void
    ) async {
        onLine("Base URL：\(baseURL)")
        onLine("模型：\(model)")

        let apiKey: String?
        do {
            apiKey = try keychain.read(apiKeychainKey)
        } catch {
            onLine("❌ 读取 Keychain 失败：\(error.localizedDescription)")
            return
        }
        guard let apiKey, !apiKey.isEmpty else {
            onLine("❌ Keychain（\(apiKeychainKey)）中没有 API Key。请在上方输入后先点「保存」，或重新输入再测。")
            return
        }
        onLine("API Key：\(apiKey)（长度 \(apiKey.count)）")

        guard let url = chatCompletionsURL(from: baseURL) else {
            onLine("❌ Base URL 无效，无法拼接请求地址。")
            return
        }
        onLine("请求地址：\(url.absoluteString)")

        let isMiMo = baseURL.localizedCaseInsensitiveContains("xiaomimimo")
        let disableThinking = baseURL.localizedCaseInsensitiveContains("deepseek")
        onLine("关闭思考模式：\(disableThinking ? "是" : "否")")

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: .text("You are a connectivity test endpoint. Reply with exactly OK.")),
                ChatMessage(role: "user", content: .text("Reply OK."))
            ],
            temperature: 0,
            responseFormat: nil,
            maxTokens: isMiMo ? nil : 64,
            maxCompletionTokens: isMiMo ? 64 : nil,
            thinking: disableThinking ? ThinkingConfig(type: "disabled") : nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = try JSONEncoder().encode(requestBody)
            request.httpBody = body
            onLine("请求体：\(String(data: body, encoding: .utf8) ?? "(编码失败)")")
        } catch {
            onLine("❌ 请求体编码失败：\(error.localizedDescription)")
            return
        }

        onLine("⏳ 正在发送请求（超时 30 秒）…")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            onLine("❌ 网络请求失败：\(Self.transportMessage(for: error))")
            onLine("   错误详情：domain=\(nsError.domain) code=\(nsError.code)")
            return
        }

        if let http = response as? HTTPURLResponse {
            onLine("✅ 已收到响应，HTTP 状态码：\(http.statusCode)")
        } else {
            onLine("⚠️ 收到响应，但不是标准 HTTP 响应。")
        }
        let bodyText = String(data: data, encoding: .utf8) ?? "(返回内容无法解码为 UTF-8)"
        onLine("原始返回：\(bodyText)")
    }

    private func complete(
        model: String,
        baseURL: String,
        apiKeychainKey: String,
        messages: [ChatMessage],
        temperature: Double,
        jsonMode: Bool,
        maxTokens: Int,
        timeout: TimeInterval = 120
    ) async throws -> String {
        guard let apiKey = try keychain.read(apiKeychainKey), !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        guard let url = chatCompletionsURL(from: baseURL) else {
            throw AIClientError.invalidBaseURL
        }

        // DeepSeek 的 deepseek-v4 系列默认开启 thinking(思考)模式：会先生成大段 reasoning_content
        // 再产出正文，导致响应缓慢容易超时，仅当 Base URL 指向 DeepSeek 时显式关闭。
        let disableThinking = baseURL.localizedCaseInsensitiveContains("deepseek")
        // 小米 MiMo 用 max_completion_tokens 而非 max_tokens。
        let isMiMo = baseURL.localizedCaseInsensitiveContains("xiaomimimo")
        let requestBody = ChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            responseFormat: jsonMode ? ChatResponseFormat(type: "json_object") : nil,
            maxTokens: isMiMo ? nil : maxTokens,
            maxCompletionTokens: isMiMo ? maxTokens : nil,
            thinking: disableThinking ? ThinkingConfig(type: "disabled") : nil
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        // Authorization 适配 DeepSeek/OpenAI；api-key 适配小米 MiMo。两者同时下发，互不影响。
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
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
        let message = decoded.choices.first?.message
        if let content = message?.content, !content.isEmpty {
            return content
        }
        // 正文为空但有思考内容：模型仍在思考模式且回复被 token 上限截断在推理阶段。
        if let reasoning = message?.reasoningContent, !reasoning.isEmpty {
            throw AIClientError.transport("AI 只返回了思考内容、没有正式回答，通常是模型处于思考(thinking)模式且回复被 token 上限截断，请调大 token 上限或确认模型后重试。")
        }
        throw AIClientError.emptyResponse
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
                return "TLS错误导致安全连接失败。请确认 Base URL 正确、不要带空格，并检查手机时间和网络代理。"
            case NSURLErrorCannotFindHost:
                return "无法找到 AI 服务域名。请检查 Base URL，例如 DeepSeek 用 https://api.deepseek.com、MiMo 用 https://api.xiaomimimo.com/v1。"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "无法连接 AI 服务。请检查网络、代理或稍后重试。"
            case NSURLErrorTimedOut:
                return "AI 请求超时。模型推理较慢或网络不稳定时可稍后重试，也可检查代理设置。"
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
    var maxCompletionTokens: Int?
    var thinking: ThinkingConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case thinking
    }
}

private struct ChatResponseFormat: Encodable {
    var type: String
}

// DeepSeek 思考模式开关：{"type": "disabled"} 关闭思考，{"type": "enabled"} 开启。
private struct ThinkingConfig: Encodable {
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
            var reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        var message: Message
    }

    var choices: [Choice]
}
