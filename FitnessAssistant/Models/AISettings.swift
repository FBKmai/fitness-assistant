import Foundation
import SwiftData

@Model
final class AISettings {
    var id: UUID
    // 文字模型（默认 DeepSeek）
    var baseURL: String
    var modelName: String
    var apiKeychainKey: String
    // 视觉模型（默认小米 MiMo，与文字模型分属不同服务商，需独立的 Base URL 和 Key）
    // 新增属性带内联默认值，便于已有用户升级时 SwiftData 轻量迁移自动填充。
    var visionBaseURL: String = "https://api.xiaomimimo.com/v1"
    var visionModelName: String
    var visionAPIKeychainKey: String = "xiaomi_mimo_api_key"
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        baseURL: String = "https://api.deepseek.com",
        modelName: String = "deepseek-v4-pro",
        apiKeychainKey: String = "openai_compatible_api_key",
        visionBaseURL: String = "https://api.xiaomimimo.com/v1",
        visionModelName: String = "mimo-v2-omni",
        visionAPIKeychainKey: String = "xiaomi_mimo_api_key",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKeychainKey = apiKeychainKey
        self.visionBaseURL = visionBaseURL
        self.visionModelName = visionModelName
        self.visionAPIKeychainKey = visionAPIKeychainKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
