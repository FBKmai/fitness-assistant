import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitService: HealthKitService
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    @State private var heightCm = 170.0
    @State private var weightText = "70.0"
    @State private var targetWeightText = ""
    @State private var gender: Gender = .unspecified
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var targetDeficit = 500.0
    @State private var reminderTime = Calendar.current.todayAt(hour: 22, minute: 30)
    @State private var baseURL = "https://api.deepseek.com"
    @State private var modelName = "deepseek-v4-pro"
    @State private var apiKey = ""
    @State private var visionBaseURL = "https://api.xiaomimimo.com/v1"
    @State private var visionModelName = "mimo-v2-omni"
    @State private var visionAPIKey = ""
    @State private var showTextKey = false
    @State private var showVisionKey = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var genderUnspecified: Bool { gender == .unspecified }
    private var apiKeyMissing: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var parsedWeightKg: Double? { weightText.doubleValue }
    private var weightValid: Bool {
        guard let parsedWeightKg else { return false }
        return (30...250).contains(parsedWeightKg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text("欢迎使用健身助手")
                            .font(.title3.weight(.semibold))
                        Text("记录每日饮食和运动，自动同步 Apple 健康，AI 帮你分析热量缺口并生成减脂建议。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Stepper(value: $heightCm, in: 120...230, step: 1) {
                        LabeledContent("身高", value: "\(Int(heightCm)) cm")
                    }
                    LabeledTextFieldRow(title: "体重", unit: "kg", text: $weightText)
                    Picker("性别", selection: $gender) {
                        ForEach(Gender.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    DatePicker("生日", selection: $birthday, displayedComponents: .date)
                } header: {
                    Text("身体资料")
                } footer: {
                    if !weightValid {
                        Text("请输入 30-250 kg 之间的体重。")
                            .foregroundStyle(.orange)
                    } else if genderUnspecified {
                        Text("建议选择性别，否则基础代谢（BMR）估算会不准确。")
                            .foregroundStyle(.orange)
                    } else {
                        Text("用于计算基础代谢率，估算每日热量消耗。")
                    }
                }

                Section {
                    LabeledTextFieldRow(title: "目标体重", unit: "kg", prompt: "选填", text: $targetWeightText)
                    Stepper(value: $targetDeficit, in: 100...1000, step: 50) {
                        LabeledContent("每日热量缺口", value: "\(Int(targetDeficit)) kcal")
                    }
                    DatePicker("晚间提醒", selection: $reminderTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("减脂目标")
                } footer: {
                    Text("当前体重会作为减脂起点；填了目标体重后，「食物 → 体重管理方案」会显示进度。热量缺口越大减脂越快，但过大不易坚持，推荐 300–500 kcal。每天 08:00 提醒称体重，每晚此时提醒你记录当天数据。")
                }

                Section {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名", text: $modelName)
                        .textInputAutocapitalization(.never)
                    apiKeyField(text: $apiKey, show: $showTextKey)
                } header: {
                    Text("文字模型 · DeepSeek")
                } footer: {
                    Text("用于文字估算和每日建议。默认已填好 DeepSeek，有自己的 OpenAI 兼容服务可改。")
                }

                Section {
                    TextField("Base URL", text: $visionBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名", text: $visionModelName)
                        .textInputAutocapitalization(.never)
                    apiKeyField(text: $visionAPIKey, show: $showVisionKey)
                } header: {
                    Text("视觉模型 · 小米 MiMo")
                } footer: {
                    if apiKeyMissing {
                        Text("用于拍照/多图识别。两套模型可填同一个 Key 也可不同；留空仍可使用，但 AI 估算和建议功能需要对应的 API Key。")
                            .foregroundStyle(.orange)
                    } else {
                        Text("用于拍照/多图识别，与文字模型分属不同服务商，各填各自的 Key。")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("健身助手")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("开始使用")
                        }
                    }
                    .disabled(isSaving || !weightValid)
                }
            }
        }
    }

    /// API Key 输入行：明文/密文切换。
    @ViewBuilder
    private func apiKeyField(text: Binding<String>, show: Binding<Bool>) -> some View {
        HStack {
            Group {
                if show.wrappedValue {
                    TextField("API Key", text: text)
                } else {
                    SecureField("API Key", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                show.wrappedValue.toggle()
            } label: {
                Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        guard let parsedWeightKg, weightValid else {
            errorMessage = "请输入有效体重"
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let targetWeightKg = targetWeightText.doubleValue.flatMap { (30...250).contains($0) ? $0 : nil } ?? 0
        let profile = UserProfile(
            heightCm: heightCm,
            currentWeightKg: parsedWeightKg,
            initialWeightKg: parsedWeightKg,
            targetWeightKg: targetWeightKg,
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
            visionBaseURL: visionBaseURL,
            visionModelName: visionModelName
        )

        do {
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(apiKey, for: settings.apiKeychainKey)
            }
            if !visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.shared.save(visionAPIKey, for: settings.visionAPIKeychainKey)
            }
            modelContext.insert(profile)
            modelContext.insert(settings)
            try modelContext.save()

            try? await healthKitService.requestAuthorization()
            try? await notificationScheduler.requestAuthorization()
            try? await notificationScheduler.scheduleDailyReminders(profile: profile)
        } catch {
            AppLog.error("引导页保存资料失败：\(error.localizedDescription)", category: "引导")
            errorMessage = error.localizedDescription
        }
    }
}
