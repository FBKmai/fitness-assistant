import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient
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
    @State private var baseURL = "https://api.deepseek.com"
    @State private var modelName = "deepseek-v4-pro"
    @State private var apiKey = ""
    @State private var visionBaseURL = "https://api.xiaomimimo.com/v1"
    @State private var visionModelName = "mimo-v2-omni"
    @State private var visionAPIKey = ""
    @State private var exportStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var exportEnd = Date.now
    @State private var shareURLs: [URL] = []
    @State private var showingShare = false
    @State private var isTestingAI = false
    @State private var message: String?
    @State private var debugLog: String = ""

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

                Section {
                    TextField("文字 Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("文字模型", text: $modelName)
                        .textInputAutocapitalization(.never)
                    SecureField("文字 API Key（留空则不修改）", text: $apiKey)
                        .textInputAutocapitalization(.never)

                    TextField("视觉 Base URL", text: $visionBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("视觉模型", text: $visionModelName)
                        .textInputAutocapitalization(.never)
                    SecureField("视觉 API Key（留空则不修改）", text: $visionAPIKey)
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await testAIConnection() }
                    } label: {
                        Label(isTestingAI ? "测试中" : "测试 AI 模型", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(isTestingAI)
                } header: {
                    Text("AI 接口")
                } footer: {
                    Text("文字模型默认 DeepSeek（https://api.deepseek.com，deepseek-v4-pro），用于文字估算和每日建议。视觉模型默认小米 MiMo（https://api.xiaomimimo.com/v1，mimo-v2-omni），用于拍照/多图识别。两者是不同服务商，需分别填各自的 API Key。")
                }

                if !debugLog.isEmpty {
                    Section {
                        Text(debugLog)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("调试日志")
                    } footer: {
                        Text("长按可复制全部内容发给开发者排查。")
                    }
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
        visionBaseURL = aiSettings.visionBaseURL
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
        aiSettings.visionBaseURL = visionBaseURL
        aiSettings.visionModelName = visionModelName
        aiSettings.updatedAt = .now

        do {
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(apiKey, for: aiSettings.apiKeychainKey)
                apiKey = ""
            }
            if !visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(visionAPIKey, for: aiSettings.visionAPIKeychainKey)
                visionAPIKey = ""
            }
            try modelContext.save()
            message = "已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func testAIConnection() async {
        guard let aiSettings = settings.first else {
            debugLog = ""
            appendLog("❌ 未找到 AISettings（为空）。请先完成引导页配置，或点右上角「保存」后重试。")
            return
        }
        isTestingAI = true
        debugLog = ""
        defer { isTestingAI = false }

        appendLog("点击测试，开始诊断")

        aiSettings.baseURL = baseURL
        aiSettings.modelName = modelName
        aiSettings.visionBaseURL = visionBaseURL
        aiSettings.visionModelName = visionModelName
        aiSettings.updatedAt = .now

        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog("文字 Key：输入框未填，沿用 Keychain 已有")
        } else {
            do {
                try KeychainStore.shared.save(apiKey, for: aiSettings.apiKeychainKey)
                appendLog("已写入文字 API Key")
            } catch {
                appendLog("⚠️ 写入文字 Key 失败：\(error.localizedDescription)")
            }
        }
        if visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog("视觉 Key：输入框未填，沿用 Keychain 已有")
        } else {
            do {
                try KeychainStore.shared.save(visionAPIKey, for: aiSettings.visionAPIKeychainKey)
                appendLog("已写入视觉 API Key")
            } catch {
                appendLog("⚠️ 写入视觉 Key 失败：\(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            appendLog("⚠️ 保存设置失败：\(error.localizedDescription)")
        }

        await aiClient.diagnose(settings: aiSettings) { line in
            appendLog(line)
        }
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        debugLog += "[\(formatter.string(from: .now))] \(line)\n"
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
