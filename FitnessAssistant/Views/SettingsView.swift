import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]

    @State private var heightCm = 170.0
    @State private var weightKg = 70.0
    @State private var gender: Gender = .unspecified
    @State private var birthday = Date.now
    @State private var targetDeficit = 500.0
    @State private var reminderTime = Date.now
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var modelName = "gpt-4o-mini"
    @State private var visionModelName = "gpt-4o-mini"
    @State private var apiKey = ""
    @State private var exportStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var exportEnd = Date.now
    @State private var shareURLs: [URL] = []
    @State private var showingShare = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("身体资料") {
                    Stepper(value: $heightCm, in: 120...230, step: 1) {
                        LabeledContent("身高", value: "\(Int(heightCm)) cm")
                    }
                    Stepper(value: $weightKg, in: 30...200, step: 0.5) {
                        LabeledContent("体重", value: String(format: "%.1f kg", weightKg))
                    }
                    Picker("性别", selection: $gender) {
                        ForEach(Gender.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    DatePicker("生日", selection: $birthday, displayedComponents: .date)
                    Stepper(value: $targetDeficit, in: 100...1000, step: 50) {
                        LabeledContent("热量缺口目标", value: "\(Int(targetDeficit)) kcal")
                    }
                    DatePicker("晚间提醒", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }

                Section("AI 接口") {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("文字模型", text: $modelName)
                        .textInputAutocapitalization(.never)
                    TextField("视觉模型", text: $visionModelName)
                        .textInputAutocapitalization(.never)
                    SecureField("API Key（留空则不修改）", text: $apiKey)
                        .textInputAutocapitalization(.never)
                }

                Section("权限") {
                    Button {
                        Task { await requestHealthKit() }
                    } label: {
                        Label("请求健康权限", systemImage: "heart.text.square")
                    }

                    Button {
                        Task { await scheduleReminder() }
                    } label: {
                        Label("更新晚间提醒", systemImage: "bell.badge")
                    }
                }

                Section("导出 CSV") {
                    DatePicker("开始", selection: $exportStart, displayedComponents: .date)
                    DatePicker("结束", selection: $exportEnd, displayedComponents: .date)
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出表格", systemImage: "square.and.arrow.up")
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingShare) {
                ActivityView(items: shareURLs.map { $0 as Any })
            }
        }
    }

    private func load() {
        guard let profile = profiles.first, let aiSettings = settings.first else { return }
        heightCm = profile.heightCm
        weightKg = profile.currentWeightKg
        gender = profile.gender
        birthday = profile.birthday
        targetDeficit = profile.targetDailyDeficitKcal
        reminderTime = Calendar.current.todayAt(hour: profile.reminderHour, minute: profile.reminderMinute)
        baseURL = aiSettings.baseURL
        modelName = aiSettings.modelName
        visionModelName = aiSettings.visionModelName
    }

    private func save() {
        guard let profile = profiles.first, let aiSettings = settings.first else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)

        profile.heightCm = heightCm
        profile.currentWeightKg = weightKg
        profile.gender = gender
        profile.birthday = birthday
        profile.targetDailyDeficitKcal = targetDeficit
        profile.reminderHour = components.hour ?? 22
        profile.reminderMinute = components.minute ?? 30
        profile.updatedAt = .now

        aiSettings.baseURL = baseURL
        aiSettings.modelName = modelName
        aiSettings.visionModelName = visionModelName
        aiSettings.updatedAt = .now

        do {
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(apiKey, for: aiSettings.apiKeychainKey)
                apiKey = ""
            }
            try modelContext.save()
            message = "已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func requestHealthKit() async {
        do {
            try await healthKitService.requestAuthorization()
            message = "已请求健康权限"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleReminder() async {
        guard let profile = profiles.first else { return }
        do {
            try await notificationScheduler.requestAuthorization()
            try await notificationScheduler.scheduleNightlyReminder(profile: profile)
            message = "已更新晚间提醒"
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportCSV() {
        let start = Calendar.current.startOfDay(for: exportStart)
        let interval = Calendar.current.dayInterval(containing: exportEnd)
        let end = interval.end
        let mealsInRange = meals.filter { $0.date >= start && $0.date < end }
        let exercisesInRange = exercises.filter { $0.date >= start && $0.date < end }
        let summariesInRange = summaries.filter { $0.date >= start && $0.date < end }

        do {
            shareURLs = try CSVExporter.export(meals: mealsInRange, exercises: exercisesInRange, summaries: summariesInRange)
            showingShare = true
            message = "已生成 CSV"
        } catch {
            message = error.localizedDescription
        }
    }
}
