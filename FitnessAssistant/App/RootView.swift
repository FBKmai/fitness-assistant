import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]

    var body: some View {
        if profiles.first == nil || settings.first == nil {
            OnboardingView()
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "gauge.with.dots.needle.67percent") }

            MealsView()
                .tabItem { Label("饮食", systemImage: "fork.knife") }

            ExerciseView()
                .tabItem { Label("运动", systemImage: "figure.run") }

            SummariesView()
                .tabItem { Label("总结", systemImage: "doc.text.magnifyingglass") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
