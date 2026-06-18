import SwiftData
import SwiftUI

@main
struct FitnessAssistantApp: App {
    @StateObject private var healthKitService = HealthKitService()
    @StateObject private var aiClient = AIClient()
    @StateObject private var notificationScheduler = NotificationScheduler()
    @State private var dataStore = DataStore()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            MealEntry.self,
            MealAdviceRecord.self,
            FoodOption.self,
            ExerciseEntry.self,
            DailySummary.self,
            AISettings.self,
            TrainingPlan.self,
            DailyCheckIn.self,
            DayLog.self,
            CoachChatSession.self,
            CoachChatMessage.self,
            CoachMemory.self,
            DataCorrection.self,
            TrainingSession.self
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
                .keyboardDismissControls()
                .environmentObject(healthKitService)
                .environmentObject(aiClient)
                .environmentObject(notificationScheduler)
                .environment(dataStore)
        }
        .modelContainer(modelContainer)
    }
}
