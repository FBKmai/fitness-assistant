import SwiftData
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \DataCorrection.createdAt, order: .reverse) private var corrections: [DataCorrection]

    @State private var heightCm = 170.0
    @State private var weightText = "70.0"
    @State private var initialWeightText = ""
    @State private var targetWeightText = ""
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
    @State private var showingGeminiImporter = false
    @State private var geminiPreview: GeminiImportPreview?

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
                    LabeledTextFieldRow(title: "体重", unit: "kg", text: $weightText)
                    LabeledTextFieldRow(title: "初始体重", unit: "kg", prompt: "选填", text: $initialWeightText)
                    LabeledTextFieldRow(title: "目标体重", unit: "kg", prompt: "选填", text: $targetWeightText)
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

                Section("教练") {
                    if let aiSettings = settings.first {
                        Picker("回复详细度", selection: Binding(
                            get: { aiSettings.coachVerbosity },
                            set: { newValue in
                                aiSettings.coachVerbosity = newValue
                                aiSettings.updatedAt = .now
                                try? modelContext.save()
                            }
                        )) {
                            ForEach(CoachVerbosity.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Text("「简洁」让教练先给一句话结论，再给要点，避免长篇大论。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Section("结构化记忆") {
                    LabeledContent("身体档案", value: profiles.first == nil ? "未设置" : "以本页资料为唯一来源")
                    LabeledContent("常吃食物", value: "\(foodOptions.count) 个")
                    LabeledContent("有效更正", value: "\(corrections.filter(\.isActive).count) 条")
                    Button {
                        showingGeminiImporter = true
                    } label: {
                        Label("导入 Gemini 固定档案", systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        StructuredMemoryView()
                    } label: {
                        Label("管理食物别名与更正历史", systemImage: "externaldrive.badge.person.crop")
                    }
                }

                Section("开发与日志") {
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("调试日志", systemImage: "ladybug")
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
            .fileImporter(
                isPresented: $showingGeminiImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleGeminiImport(result)
            }
            .sheet(item: $geminiPreview) { preview in
                GeminiImportPreviewView(preview: preview) {
                    applyGeminiPreview(preview)
                    geminiPreview = nil
                }
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
        initialWeightText = profile.initialWeightKg > 0 ? String(format: "%.1f", profile.initialWeightKg) : ""
        targetWeightText = profile.targetWeightKg > 0 ? String(format: "%.1f", profile.targetWeightKg) : ""
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
        profile.initialWeightKg = initialWeightText.doubleValue.flatMap { (30...250).contains($0) ? $0 : nil } ?? 0
        profile.targetWeightKg = targetWeightText.doubleValue.flatMap { (30...250).contains($0) ? $0 : nil } ?? 0
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
            AppLog.error("保存设置失败：\(error.localizedDescription)", category: "设置")
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
            AppLog.error("请求健康权限失败：\(error.localizedDescription)", category: "设置")
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
            AppLog.error("更新提醒失败：\(error.localizedDescription)", category: "设置")
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
        let dayLogsInRange = dayLogs.filter { $0.date >= start && $0.date < end }

        do {
            shareURLs = try CSVExporter.export(meals: mealsInRange, exercises: exercisesInRange, dayLogs: dayLogsInRange)
            showingShare = true
            setMessage("已生成 CSV", isError: false)
        } catch {
            AppLog.error("导出 CSV 失败：\(error.localizedDescription)", category: "设置")
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func handleGeminiImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer {
                if granted { url.stopAccessingSecurityScopedResource() }
            }
            geminiPreview = try GeminiImportService.preview(data: Data(contentsOf: url))
        } catch {
            AppLog.error("导入 Gemini 固定档案失败：\(error.localizedDescription)", category: "导入")
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func applyGeminiPreview(_ preview: GeminiImportPreview) {
        guard let profile = profiles.first else { return }
        if let value = preview.heightCm, (120...230).contains(value) {
            heightCm = value
        }
        if let value = preview.initialWeightKg, (30...250).contains(value) {
            initialWeightText = String(format: "%.1f", value)
        }
        if let value = preview.targetWeightKg, (30...250).contains(value) {
            targetWeightText = String(format: "%.1f", value)
        }

        for name in preview.commonFoods where !foodOptions.contains(where: { $0.matches(name) }) {
            modelContext.insert(FoodOption(
                name: name,
                aliases: [name],
                sourceDescription: "由 Gemini 历史对话提取的常吃食物，营养数据待补充。",
                dataSource: "geminiImport"
            ))
        }

        profile.updatedAt = .now
        save()
        setMessage("已导入固定档案和常吃食物，请核对营养数据", isError: false)
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

private struct StructuredMemoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \DataCorrection.createdAt, order: .reverse) private var corrections: [DataCorrection]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]

    @State private var presentedAlert: MemoryManagementAlert?

    var body: some View {
        List {
            Section("食物别名") {
                if foodOptions.isEmpty {
                    Text("还没有常吃食物。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(foodOptions) { option in
                        NavigationLink {
                            FoodAliasEditorView(option: option)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name)
                                Text(option.aliases.isEmpty ? "暂无别名" : option.aliases.joined(separator: "、"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section {
                if corrections.isEmpty {
                    Text("还没有数据更正记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(corrections) { correction in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(correctionTitle(correction))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(correction.isActive ? "生效中" : "已撤销")
                                    .font(.caption)
                                    .foregroundStyle(correction.isActive ? Color.orange : Color.secondary)
                            }
                            Text("\(correction.oldValue) → \(correction.newValue)")
                                .font(.caption)
                            Text(correction.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(correction.effectiveDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if correction.isActive, canReverse(correction) {
                                Button("撤销这次体重更正", role: .destructive) {
                                    presentedAlert = MemoryManagementAlert(
                                        kind: .confirmReversal(correction.id)
                                    )
                                }
                                .font(.caption)
                            } else if correction.isActive {
                                Text("该记录缺少可完整恢复的旧字段，仅保留审计，不提供自动撤销。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("更正历史")
            } footer: {
                Text("撤销体重更正会恢复旧值，并重新计算当天趋势与本地报告；其他复合字段不会做不完整回滚。")
            }
        }
        .navigationTitle("结构化记忆")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $presentedAlert) { item in
            switch item.kind {
            case let .confirmReversal(correctionID):
                Alert(
                    title: Text("确认撤销"),
                    message: Text("将恢复更正前体重，并重新计算当天数据。"),
                    primaryButton: .destructive(Text("撤销更正")) {
                        reverseCorrection(id: correctionID)
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                Alert(
                    title: Text("操作失败"),
                    message: Text(message),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }

    private func canReverse(_ correction: DataCorrection) -> Bool {
        correction.entityType == "DayLog"
            && correction.fieldName == "weightKg"
            && Double(correction.oldValue) != nil
    }

    private func correctionTitle(_ correction: DataCorrection) -> String {
        if correction.entityType == "DayLog", correction.fieldName == "weightKg" {
            return "体重更正"
        }
        return "\(correction.entityType) · \(correction.fieldName)"
    }

    private func reverseCorrection(id: UUID) {
        guard let correction = corrections.first(where: { $0.id == id }),
              correction.isActive,
              canReverse(correction),
              let oldWeight = Double(correction.oldValue),
              let profile = profiles.first,
              let log = dayLogs.first(where: {
                  $0.date.dayKey == correction.entityID
                      || Calendar.current.isDate($0.date, inSameDayAs: correction.effectiveDate)
              }) else {
            presentedAlert = MemoryManagementAlert(kind: .error("未找到可恢复的体重记录。"))
            return
        }

        let hadSummary = log.hasSummary
        log.weightKg = oldWeight
        log.updatedAt = .now
        if Calendar.current.isDateInToday(log.date) {
            profile.currentWeightKg = oldWeight
            profile.updatedAt = .now
        }

        correction.isActive = false
        correction.reversedAt = .now

        rebuildReport(for: log, profile: profile, hadSummary: hadSummary)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentedAlert = MemoryManagementAlert(
                kind: .error("撤销更正失败：\(error.localizedDescription)")
            )
        }
    }

    private func rebuildReport(for log: DayLog, profile: UserProfile, hadSummary: Bool) {
        log.safetyWarnings = TrendSafetyAnalyzer.alerts(
            dayLogs: dayLogs,
            currentWeightKg: log.weightKg
        ).map(\.message)

        let metrics = DayMetricsCalculator.metrics(
            for: log.date,
            profile: profile,
            meals: meals,
            exercises: exercises,
            dayLogs: dayLogs,
            trainingPlans: trainingPlans
        )
        log.intakeCalories = metrics.intakeCalories
        log.activeCalories = metrics.activeCalories
        log.restingCalories = metrics.restingCalories
        log.totalBurnCalories = metrics.totalBurnCalories
        log.calorieDeficit = metrics.calorieDeficit
        log.proteinGrams = metrics.proteinGrams
        log.carbsGrams = metrics.carbsGrams
        log.fatGrams = metrics.fatGrams
        log.fiberGrams = metrics.fiberGrams
        log.vegetableGrams = metrics.vegetableGrams
        log.restingEnergySourceRaw = metrics.restingEnergySource.rawValue
        log.snapshot = metrics.dailySnapshot
        if hadSummary {
            log.adviceText = DataStore.localSummaryText(snapshot: metrics.dailySnapshot)
            log.generatedAt = .now
        }
        log.reportIsStale = false
        log.updatedAt = .now
    }
}

private struct FoodAliasEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let option: FoodOption

    @State private var aliasesText = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("食物") {
                LabeledContent("名称", value: option.name)
                if !option.brand.isEmpty {
                    LabeledContent("品牌", value: option.brand)
                }
            }

            Section {
                TextEditor(text: $aliasesText)
                    .frame(minHeight: 180)
            } header: {
                Text("别名")
            } footer: {
                Text("每行一个，也支持逗号分隔。像“之前那个鸡排”会在检索时自动归一化，无需重复保存。")
            }
        }
        .navigationTitle("编辑食物别名")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .onAppear {
            aliasesText = option.aliases.joined(separator: "\n")
        }
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        let parts = aliasesText.components(
            separatedBy: CharacterSet(charactersIn: "\n,，;；")
        )
        var seen = Set<String>()
        let reserved = Set([option.name, option.brand].map { normalized($0) })
        let aliases = parts.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(trimmed)
            guard !trimmed.isEmpty, !reserved.contains(key), seen.insert(key).inserted else {
                return nil
            }
            return trimmed
        }

        option.aliases = Array(aliases.prefix(30))
        option.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

private struct GeminiImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let preview: GeminiImportPreview
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("固定档案") {
                    if let age = preview.ageYears {
                        LabeledContent("识别年龄", value: "\(age) 岁（仅核对）")
                    }
                    if let height = preview.heightCm {
                        LabeledContent("身高", value: "\(height, specifier: "%.1f") cm")
                    }
                    if let weight = preview.initialWeightKg {
                        LabeledContent("初始体重", value: "\(weight, specifier: "%.1f") kg")
                    }
                    if let weight = preview.targetWeightKg {
                        LabeledContent("目标体重", value: "\(weight, specifier: "%.1f") kg")
                    }
                    if preview.ageYears == nil,
                       preview.heightCm == nil,
                       preview.initialWeightKg == nil,
                       preview.targetWeightKg == nil {
                        Text("没有识别到可核对的身体档案。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("常吃食物候选") {
                    if preview.commonFoods.isEmpty {
                        Text("没有达到重复出现阈值的食物。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preview.commonFoods, id: \.self) { food in
                            Label(food, systemImage: "fork.knife")
                        }
                    }
                }

                Section("导入说明") {
                    ForEach(preview.notes, id: \.self) { note in
                        Text(note)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Gemini 导入预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MemoryManagementAlert: Identifiable {
    enum Kind {
        case confirmReversal(UUID)
        case error(String)
    }

    let id = UUID()
    let kind: Kind
}
