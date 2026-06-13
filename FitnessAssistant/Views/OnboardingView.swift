import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    @State private var heightCm = 170.0
    @State private var weightKg = 70.0
    @State private var gender: Gender = .unspecified
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var targetDeficit = 500.0
    @State private var reminderTime = Calendar.current.todayAt(hour: 22, minute: 30)
    @State private var baseURL = "https://api.deepseek.com"
    @State private var modelName = "deepseek-v4-flash"
    @State private var visionModelName = "deepseek-v4-flash"
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                }

                Section("减脂目标") {
                    Stepper(value: $targetDeficit, in: 100...1000, step: 50) {
                        LabeledContent("每日热量缺口", value: "\(Int(targetDeficit)) kcal")
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
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("健身助手")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "开始使用") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let profile = UserProfile(
            heightCm: heightCm,
            currentWeightKg: weightKg,
            gender: gender,
            birthday: birthday,
            goal: .fatLoss,
            targetDailyDeficitKcal: targetDeficit,
            reminderHour: components.hour ?? 22,
            reminderMinute: components.minute ?? 30
        )
        let settings = AISettings(
            baseURL: baseURL,
            modelName: modelName,
            visionModelName: visionModelName
        )

        do {
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(apiKey, for: settings.apiKeychainKey)
            }
            modelContext.insert(profile)
            modelContext.insert(settings)
            try modelContext.save()

            try? await healthKitService.requestAuthorization()
            try? await notificationScheduler.requestAuthorization()
            try? await notificationScheduler.scheduleNightlyReminder(profile: profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
