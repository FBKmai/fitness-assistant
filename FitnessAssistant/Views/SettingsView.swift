import SwiftData
import SwiftUI
import UserNotifications

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
    @State private var weightText = "70.0"
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
    @State private var showTextKey = false
    @State private var showVisionKey = false
    @State private var textKeyConfigured = false
    @State private var visionKeyConfigured = false
    @State private var notificationStatusText = "未知"
    @State private var exportStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var exportEnd = Date.now
    @State private var shareURLs: [URL] = []
    @State private var showingShare = false
    @State private var isTestingAI = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var debugLog: String = ""

    private var exportRangeValid: Bool { exportStart <= exportEnd }
    private var parsedWeightKg: Double? { weightText.doubleValue }
    private var weightValid: Bool {
        guard let parsedWeightKg else { return false }
        return (30...250).contains(parsedWeightKg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("身体资料") {
                    Stepper(value: $heightCm, in: 120...230, step: 1) {
                        LabeledContent("身高", value: "\(Int(heightCm)) cm")
                    }
                    HStack {
                        TextField("体重", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("kg")
                            .foregroundStyle(.secondary)
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
                    LabeledContent("称重提醒", value: "每天 08:00")
                    DatePicker("晚间提醒", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    if !weightValid {
                        Text("请输入 30-250 kg 之间的体重。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名", text: $modelName)
                        .textInputAutocapitalization(.never)
                    apiKeyField(text: $apiKey, show: $showTextKey, configured: textKeyConfigured)
                } header: {
                    Text("文字模型 · DeepSeek")
                } footer: {
                    Text("用于文字估算和每日建议。默认 https://api.deepseek.com，模型 deepseek-v4-pro。")
                }

                Section {
                    TextField("Base URL", text: $visionBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名", text: $visionModelName)
                        .textInputAutocapitalization(.never)
                    apiKeyField(text: $visionAPIKey, show: $showVisionKey, configured: visionKeyConfigured)
                } header: {
                    Text("视觉模型 · 小米 MiMo")
                } footer: {
                    Text("用于拍照/多图识别，与文字模型分属不同服务商，需独立的 Base URL 和 Key。默认 https://api.xiaomimimo.com/v1，模型 mimo-v2-omni。")
                }

                Section("连接诊断") {
                    Button {
                        Task { await testAIConnection() }
                    } label: {
                        if isTestingAI {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("测试中…")
                            }
                        } else {
                            Label("测试 AI 连接（文字 + 视觉）", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .disabled(isTestingAI)
                }

                if !debugLog.isEmpty {
                    Section {
                        ScrollView {
                            Text(debugLog)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                        Button(role: .destructive) {
                            debugLog = ""
                        } label: {
                            Label("清空日志", systemImage: "trash")
                        }
                    } header: {
                        Text("调试日志")
                    } footer: {
                        Text("长按可复制全部内容发给开发者排查。")
                    }
                }

                Section("权限") {
                    LabeledContent("HealthKit", value: healthKitService.authorizationStatusDescription)
                    Button {
                        Task { await requestHealthKit() }
                    } label: {
                        Label("请求健康权限", systemImage: "heart.text.square")
                    }
                    LabeledContent("通知", value: notificationStatusText)
                    Button {
                        Task { await scheduleReminder() }
                    } label: {
                        Label("更新每日提醒", systemImage: "bell.badge")
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
                    .disabled(!exportRangeValid)
                    if !exportRangeValid {
                        Text("开始日期不能晚于结束日期。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let message {
                    Section {
                        Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(messageIsError ? .red : .green)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!weightValid)
                }
            }
            .onAppear(perform: load)
            .task { await refreshNotificationStatus() }
            .sheet(isPresented: $showingShare) {
                ActivityView(items: shareURLs.map { $0 as Any })
            }
        }
    }

    /// API Key 输入行：明文/密文切换 + 已配置标识。
    @ViewBuilder
    private func apiKeyField(text: Binding<String>, show: Binding<Bool>, configured: Bool) -> some View {
        HStack {
            Group {
                if show.wrappedValue {
                    TextField("API Key（留空则不修改）", text: text)
                } else {
                    SecureField("API Key（留空则不修改）", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if configured {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("已配置")
            }
            Button {
                show.wrappedValue.toggle()
            } label: {
                Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let profile = profiles.first, let aiSettings = settings.first else { return }
        heightCm = profile.heightCm
        weightText = String(format: "%.1f", profile.currentWeightKg)
        gender = profile.gender
        birthday = profile.birthday
        targetDeficit = profile.targetDailyDeficitKcal
        reminderTime = Calendar.current.todayAt(hour: profile.reminderHour, minute: profile.reminderMinute)
        baseURL = aiSettings.baseURL
        modelName = aiSettings.modelName
        visionBaseURL = aiSettings.visionBaseURL
        visionModelName = aiSettings.visionModelName
        refreshKeyStatus()
    }

    private func save() {
        guard let profile = profiles.first, let aiSettings = settings.first else { return }
        guard let parsedWeightKg, weightValid else {
            setMessage("请输入有效体重", isError: true)
            return
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)

        profile.heightCm = heightCm
        profile.currentWeightKg = parsedWeightKg
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
            refreshKeyStatus()
            let reminderHour = profile.reminderHour
            let reminderMinute = profile.reminderMinute
            Task {
                try? await notificationScheduler.scheduleDailyReminders(nightlyHour: reminderHour, nightlyMinute: reminderMinute)
                await refreshNotificationStatus()
            }
            setMessage("已保存", isError: false)
        } catch {
            setMessage(error.localizedDescription, isError: true)
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
        refreshKeyStatus()

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
            setMessage("已请求健康权限", isError: false)
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    @MainActor
    private func scheduleReminder() async {
        guard let profile = profiles.first else { return }
        do {
            try await notificationScheduler.requestAuthorization()
            try await notificationScheduler.scheduleDailyReminders(profile: profile)
            await refreshNotificationStatus()
            setMessage("已更新称重和晚间提醒", isError: false)
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func exportCSV() {
        guard exportRangeValid else { return }
        let start = Calendar.current.startOfDay(for: exportStart)
        let interval = Calendar.current.dayInterval(containing: exportEnd)
        let end = interval.end
        let mealsInRange = meals.filter { $0.date >= start && $0.date < end }
        let exercisesInRange = exercises.filter { $0.date >= start && $0.date < end }
        let summariesInRange = summaries.filter { $0.date >= start && $0.date < end }

        do {
            shareURLs = try CSVExporter.export(meals: mealsInRange, exercises: exercisesInRange, summaries: summariesInRange)
            showingShare = true
            setMessage("已生成 CSV", isError: false)
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func setMessage(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }

    private func refreshKeyStatus() {
        guard let aiSettings = settings.first else { return }
        textKeyConfigured = keyConfigured(aiSettings.apiKeychainKey)
        visionKeyConfigured = keyConfigured(aiSettings.visionAPIKeychainKey)
    }

    private func keyConfigured(_ key: String) -> Bool {
        guard let value = (try? KeychainStore.shared.read(key)) ?? nil else { return false }
        return !value.isEmpty
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatusText = Self.describe(notificationSettings.authorizationStatus)
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "已授权"
        case .denied: "已拒绝"
        case .notDetermined: "未询问"
        case .provisional: "临时授权"
        case .ephemeral: "临时授权"
        @unknown default: "未知"
        }
    }
}
