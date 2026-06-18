import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataStore.self) private var dataStore
    @EnvironmentObject private var healthKitService: HealthKitService
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]

    var body: some View {
        Group {
            if profiles.first == nil || settings.first == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .task {
            // Phase C：注入依赖给 DataStore（幂等）。
            dataStore.configure(context: modelContext, health: healthKitService)
            // Phase B：首次启动把旧 DailySummary+DailyCheckIn 回填进 DayLog（幂等、只跑一次）。
            DayLogMigration.migrateIfNeeded(modelContext)
            StructuredDataMigration.migrateIfNeeded(modelContext)
        }
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            CoachHomeView()
                .tabItem { Label("教练", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(0)

            DataHubView()
                .tabItem { Label("数据", systemImage: "chart.bar.doc.horizontal") }
                .tag(1)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
    }
}
