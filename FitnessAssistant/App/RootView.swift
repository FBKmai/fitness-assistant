import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
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
        // Phase B：首次启动把旧 DailySummary+DailyCheckIn 回填进 DayLog（幂等、只跑一次）。
        .task { DayLogMigration.migrateIfNeeded(modelContext) }
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            CoachHomeView()
                .tabItem { Label("教练", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(0)

            TodayView(selection: $selection)
                .tabItem { Label("今日", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(1)

            FoodHubView()
                .tabItem { Label("食物", systemImage: "fork.knife") }
                .tag(2)

            ExerciseView()
                .tabItem { Label("运动", systemImage: "figure.run") }
                .tag(3)

            SummariesView()
                .tabItem { Label("总结", systemImage: "doc.text.magnifyingglass") }
                .tag(4)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(5)

            DebugLogView()
                .tabItem { Label("调试", systemImage: "ladybug") }
                .tag(6)
        }
    }
}
