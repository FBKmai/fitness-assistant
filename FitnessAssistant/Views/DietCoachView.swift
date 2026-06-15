import SwiftData
import SwiftUI
import UIKit

/// 「问 AI 怎么吃」独立 Tab：结合今日记录、最近饮食与消耗，针对「这一餐」给建议，可多轮追问调整。
struct DietCoachView: View {
    @EnvironmentObject private var aiClient: AIClient

    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]

    @State private var history: [DietCoachTurn] = []
    @State private var input = ""
    @State private var selectedFoodOptionIDs: Set<UUID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showContext = true
    @FocusState private var inputFocused: Bool

    private let bottomID = "diet-coach-bottom"

    private var profile: UserProfile? { profiles.first }
    private var aiSettings: AISettings? { settings.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            contextHeader

                            if history.isEmpty {
                                emptyHint
                            } else {
                                ForEach(history) { turn in
                                    ChatBubble(turn: turn)
                                }
                            }

                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("AI 思考中…")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Color.clear.frame(height: 1).id(bottomID)
                        }
                        .padding()
                    }
                    .onChange(of: history.count) { _, _ in
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                    .onChange(of: isLoading) { _, _ in
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                }

                inputBar
            }
            .navigationTitle("问 AI 怎么吃")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 顶部上下文与候选

    private var contextHeader: some View {
        DisclosureGroup(isExpanded: $showContext) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("今日摄入").foregroundStyle(.secondary)
                        Text(totalIntake.kcalText)
                    }
                    GridRow {
                        Text("三大营养").foregroundStyle(.secondary)
                        Text("蛋白 \(Int(totalProtein.rounded()))g · 碳水 \(Int(totalCarbs.rounded()))g · 脂肪 \(Int(totalFat.rounded()))g")
                    }
                    if let analysis = currentAnalysis {
                        GridRow {
                            Text("减脂判断").foregroundStyle(.secondary)
                            Text(analysis.energyStatus)
                        }
                    }
                }
                .font(.callout)

                Divider()

                Text("候选食物选项卡")
                    .font(.subheadline.weight(.semibold))
                if foodOptions.isEmpty {
                    Text("先到「食物」Tab 保存常吃单品或套餐，再让 AI 从候选里判断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(foodOptions) { option in
                        FoodOptionSelectionToggle(
                            option: option,
                            isSelected: selectedFoodOptionIDs.contains(option.id)
                        ) {
                            toggleFoodOption(option)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("当前数据与候选食物", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("直接问我现在这一餐怎么吃")
                .font(.headline)
            Text("例如：现在该吃午饭了，我适合吃什么？也可以先在上面勾选候选食物，再让我判断是否合理。生成建议后还能继续追问来调整。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("现在这一餐怎么吃？也可以追问调整…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && profile != nil
            && aiSettings != nil
    }

    // MARK: - 发送

    @MainActor
    private func send() async {
        guard let profile, let settings = aiSettings else {
            errorMessage = "请先在「设置」完善资料并保存 AI 配置"
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        input = ""
        inputFocused = false
        showContext = false
        history.append(DietCoachTurn(role: .user, text: text))

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let context = buildContext(profile: profile)
        do {
            let reply = try await aiClient.generateDietCoachReply(context: context, history: history, settings: settings)
            history.append(DietCoachTurn(role: .assistant, text: reply.isEmpty ? "（AI 没有返回内容，请重试）" : reply))
        } catch {
            AppLog.error("饮食教练回复失败：\(error.localizedDescription)", category: "AI饮食教练")
            errorMessage = "AI 暂时不可用：\(error.localizedDescription)"
        }
    }

    private func toggleFoodOption(_ option: FoodOption) {
        if selectedFoodOptionIDs.contains(option.id) {
            selectedFoodOptionIDs.remove(option.id)
        } else {
            selectedFoodOptionIDs.insert(option.id)
        }
    }

    // MARK: - 数据汇总

    private var todayMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var confirmedMeals: [MealEntry] {
        todayMeals.filter(\.isConfirmed)
    }

    private var selectedFoodOptions: [FoodOption] {
        foodOptions.filter { selectedFoodOptionIDs.contains($0.id) }
    }

    private var todayExercises: [ExerciseEntry] {
        exercises.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todaySummary: DailySummary? {
        summaries.first { Calendar.current.isDateInToday($0.date) }
    }

    private var totalIntake: Double { confirmedMeals.reduce(0) { $0 + $1.totalCalories } }
    private var totalProtein: Double { confirmedMeals.reduce(0) { $0 + $1.proteinGrams } }
    private var totalCarbs: Double { confirmedMeals.reduce(0) { $0 + $1.carbsGrams } }
    private var totalFat: Double { confirmedMeals.reduce(0) { $0 + $1.fatGrams } }

    private var currentAnalysis: FatLossAnalysis? {
        guard let profile else { return nil }
        return FatLossAnalyzer.analyze(snapshot: buildDailySnapshotForCoach(profile: profile))
    }

    /// 最近 ~3 天（不含今天）已确认的饮食记录文本。
    private var recentMealTexts: [String] {
        let (start, todayStart) = recentRange()
        return meals
            .filter { $0.date >= start && $0.date < todayStart && $0.isConfirmed }
            .sorted { $0.date < $1.date }
            .suffix(12)
            .map { meal in
                "\(DateFormatter.dateHeader.string(from: meal.date)) \(meal.mealType.title) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
            }
    }

    /// 最近 ~3 天（不含今天）的训练/活动消耗文本。
    private var recentWorkoutTexts: [String] {
        let (start, todayStart) = recentRange()
        return exercises
            .filter { $0.date >= start && $0.date < todayStart }
            .sorted { $0.date < $1.date }
            .suffix(10)
            .map { exercise in
                var line = "\(DateFormatter.dateHeader.string(from: exercise.date)) \(exercise.workoutType.isEmpty ? exercise.source.title : exercise.workoutType) \(exercise.activeCalories.kcalText)"
                if exercise.steps > 0 {
                    line += " 步数\(Int(exercise.steps.rounded()))"
                }
                return line
            }
    }

    private func recentRange() -> (start: Date, todayStart: Date) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -3, to: todayStart) ?? todayStart
        return (start, todayStart)
    }

    private func buildContext(profile: UserProfile) -> DietCoachSnapshot {
        let dailySnapshot = buildDailySnapshotForCoach(profile: profile)
        let analysis = FatLossAnalyzer.analyze(snapshot: dailySnapshot)
        return DietCoachSnapshot(
            requestedAt: .now,
            goal: dailySnapshot.goal,
            targetDailyDeficitKcal: dailySnapshot.targetDailyDeficitKcal,
            heightCm: dailySnapshot.heightCm,
            weightKg: dailySnapshot.weightKg,
            bodyFatPercentage: dailySnapshot.bodyFatPercentage,
            bodyMassIndex: dailySnapshot.bodyMassIndex,
            bodyMetricsMeasuredAt: dailySnapshot.bodyMetricsMeasuredAt,
            gender: dailySnapshot.gender,
            age: dailySnapshot.age,
            bmr: dailySnapshot.bmr,
            todayIntakeCalories: dailySnapshot.intakeCalories,
            todayActiveCalories: dailySnapshot.activeCalories,
            todayRestingCalories: dailySnapshot.restingCalories,
            todayTotalBurnCalories: dailySnapshot.totalBurnCalories,
            todayCalorieDeficit: dailySnapshot.calorieDeficit,
            proteinGrams: dailySnapshot.proteinGrams,
            carbsGrams: dailySnapshot.carbsGrams,
            fatGrams: dailySnapshot.fatGrams,
            averageMealConfidence: dailySnapshot.averageMealConfidence,
            todayMeals: dailySnapshot.meals,
            todayWorkouts: dailySnapshot.workouts,
            recentMeals: recentMealTexts,
            recentWorkouts: recentWorkoutTexts,
            selectedFoodOptions: selectedFoodOptions.map(\.snapshot),
            recentDays: dailySnapshot.recentDays,
            analysis: analysis
        )
    }

    private func buildDailySnapshotForCoach(profile: UserProfile) -> DailySnapshot {
        let manualCalories = todayExercises
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.activeCalories }
        let healthAggregateCalories = todayExercises.first {
            $0.source == .healthKit && ($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
        }?.activeCalories ?? 0
        let activeCalories = todaySummary?.activeCalories ?? (healthAggregateCalories + manualCalories)
        let restingCalories = CalorieCalculator.bmr(profile: profile)
        let totalBurn = activeCalories + restingCalories
        let deficit = totalBurn - totalIntake
        let confidenceValues = confirmedMeals.map(\.confidence).filter { $0 > 0 }
        let averageMealConfidence = confidenceValues.isEmpty
            ? nil
            : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let mealTexts = confirmedMeals.map { meal in
            "\(meal.mealType.title) \(DateFormatter.shortTime.string(from: meal.date)) \(meal.textDescription) \(meal.totalCalories.kcalText) 蛋白\(Int(meal.proteinGrams))g 碳水\(Int(meal.carbsGrams))g 脂肪\(Int(meal.fatGrams))g"
        }
        let workoutTexts = todayExercises.map { exercise in
            "\(exercise.source.title) \(exercise.workoutType) \(exercise.activeCalories.kcalText)"
        }
        let todayStart = Calendar.current.startOfDay(for: .now)
        let recentDays = summaries
            .filter { $0.date < todayStart }
            .prefix(7)
            .map { day in
                DayTrend(
                    date: day.date,
                    intakeCalories: day.intakeCalories,
                    calorieDeficit: day.calorieDeficit,
                    weightKg: day.weightKg > 0 ? day.weightKg : nil
                )
            }

        var snapshot = DailySnapshot(
            date: .now,
            goal: profile.goal.title,
            targetDailyDeficitKcal: profile.targetDailyDeficitKcal,
            heightCm: profile.heightCm,
            weightKg: profile.currentWeightKg,
            bodyFatPercentage: todaySummary?.bodyFatPercentage,
            bodyMassIndex: todaySummary?.bodyMassIndex,
            bodyMetricsMeasuredAt: todaySummary?.bodyMetricsSyncedAt,
            gender: profile.gender.title,
            age: profile.age,
            bmr: CalorieCalculator.bmr(profile: profile),
            intakeCalories: totalIntake,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit,
            proteinGrams: totalProtein,
            carbsGrams: totalCarbs,
            fatGrams: totalFat,
            averageMealConfidence: averageMealConfidence,
            unconfirmedMealCount: todayMeals.filter { !$0.isConfirmed }.count,
            manualActiveCalories: manualCalories,
            meals: mealTexts,
            workouts: workoutTexts,
            recentDays: Array(recentDays),
            analysis: nil
        )
        snapshot.analysis = FatLossAnalyzer.analyze(snapshot: snapshot)
        return snapshot
    }

}

// MARK: - 对话气泡

private struct ChatBubble: View {
    let turn: DietCoachTurn

    private var isUser: Bool { turn.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - 候选食物选项卡勾选行（自 TodayView 迁移）

struct FoodOptionSelectionToggle: View {
    let option: FoodOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FoodOptionThumbnail(path: option.photoLocalPath, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(option.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(option.kind.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(option.totalCalories.kcalText) · 推荐 \(Int(option.recommendationScore.rounded()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        MacroLabel(name: "蛋白", grams: option.proteinGrams, color: .macroProtein)
                        MacroLabel(name: "碳水", grams: option.carbsGrams, color: .macroCarbs)
                        MacroLabel(name: "脂肪", grams: option.fatGrams, color: .macroFat)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .font(.title3)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
