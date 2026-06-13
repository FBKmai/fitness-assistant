import SwiftData
import SwiftUI

@main
struct FitnessAssistantApp: App {
    @StateObject private var healthKitService = HealthKitService()
    @StateObject private var aiClient = AIClient()
    @StateObject private var notificationScheduler = NotificationScheduler()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            MealEntry.self,
            ExerciseEntry.self,
            DailySummary.self,
            AISettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法初始化本地数据库：\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthKitService)
                .environmentObject(aiClient)
                .environmentObject(notificationScheduler)
        }
        .modelContainer(modelContainer)
    }
}
