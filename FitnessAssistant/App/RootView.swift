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
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView(selection: $selection)
                .tabItem { Label("今日", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(0)

            MealsView()
                .tabItem { Label("饮食", systemImage: "fork.knife") }
                .tag(1)

            FoodOptionsView()
                .tabItem { Label("食物", systemImage: "rectangle.stack") }
                .tag(2)

            DietCoachView()
                .tabItem { Label("问AI", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(3)

            ExerciseView()
                .tabItem { Label("运动", systemImage: "figure.run") }
                .tag(4)

            SummariesView()
                .tabItem { Label("总结", systemImage: "doc.text.magnifyingglass") }
                .tag(5)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(6)
        }
    }
}
