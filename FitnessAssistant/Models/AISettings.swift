import Foundation
import SwiftData

@Model
final class AISettings {
    var id: UUID
    var baseURL: String
    var modelName: String
    var visionModelName: String
    var apiKeychainKey: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        baseURL: String = "https://api.deepseek.com",
        modelName: String = "deepseek-v4-flash",
        visionModelName: String = "deepseek-v4-flash",
        apiKeychainKey: String = "openai_compatible_api_key",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.baseURL = baseURL
        self.modelName = modelName
        self.visionModelName = visionModelName
        self.apiKeychainKey = apiKeychainKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
