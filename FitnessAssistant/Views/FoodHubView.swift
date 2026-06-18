import SwiftData
import SwiftUI
import UIKit

// MARK: - 餐别快捷入口

/// 「饮食热量」卡片图标行与详情页底部共用的快捷入口（餐别 + 运动）。
enum MealQuickEntry: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack
    case exercise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        case .exercise: "运动"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sun.horizon"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        case .exercise: "figure.run"
        }
    }

    /// 餐别入口对应的 MealType；运动入口为 nil。
    var mealType: MealType? {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .snack: .snack
        case .exercise: nil
        }
    }
}

// MARK: - 新增饮食请求（用于 sheet(item:)）

/// 详情页底部入口触发的新增饮食请求，携带预设餐别与是否自动拍照。
struct NewMealRequest: Identifiable {
    let id = UUID()
    var mealType: MealType?
    var autoCamera: Bool
    var date: Date

    init(mealType: MealType?, autoCamera: Bool, date: Date = .now) {
        self.mealType = mealType
        self.autoCamera = autoCamera
        self.date = date
    }
}

// MARK: - 食物 Tab：仪表盘

struct FoodHubView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]

    @State private var showingWeightSheet = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppMetrics.sectionSpacing) {
                    weightPlanCard
                    calorieBudgetCard
                    weightRecordCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("食物")
            .sheet(isPresented: $showingWeightSheet) {
                WeightInputSheet { saveWeight($0) }
            }
        }
    }

    // MARK: 卡片① 体重管理方案

    private var weightPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("体重管理方案", systemImage: "target")
                .font(.headline)

            if let profile {
                HStack(alignment: .center) {
                    statColumn(title: "初始", value: String(format: "%.2f", profile.resolvedInitialWeightKg))
                    Spacer(minLength: 8)
                    WeightGoalGauge(
                        initialKg: profile.resolvedInitialWeightKg,
                        currentKg: profile.currentWeightKg,
                        targetKg: profile.targetWeightKg > 0 ? profile.targetWeightKg : profile.resolvedInitialWeightKg
                    )
                    .frame(width: 116, height: 116)
                    Spacer(minLength: 8)
                    statColumn(title: "目标", value: profile.targetWeightKg > 0 ? String(format: "%.2f", profile.targetWeightKg) : "—")
                }
                if profile.targetWeightKg <= 0 {
                    Text("未设置目标体重，去「设置 → 身体资料」填写后显示减重进度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("还没有用户资料，请先完成引导设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 卡片② 饮食热量

    private var calorieBudgetCard: some View {
        let budget = dietBudget(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, plans: trainingPlans, on: .now)
        return NavigationLink {
            DietCalorieDetailView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("饮食热量", systemImage: "flame.fill")
                        .font(.headline)
                    Spacer()
                    if let goal = profile?.goal.title {
                        Text(goal)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(budget.remaining.kcalValue)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(budget.remaining >= 0 ? .primary : Color.deficitShort)
                    Text("千卡 · 还可吃")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: AppMetrics.tileSpacing) {
                    innerTile(title: "饮食", value: budget.intake.kcalValue, color: .macroCarbs)
                    innerTile(title: "运动×0.9", value: (budget.exerciseBurn * DietBudgetCalculator.exerciseFactor).kcalValue, color: .macroFat)
                }

                mealIconRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var mealIconRow: some View {
        HStack {
            ForEach(MealQuickEntry.allCases) { entry in
                VStack(spacing: 4) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 17))
                        .frame(width: 38, height: 38)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                        .foregroundStyle(.green)
                    Text(entry.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 卡片③ 体重记录

    private var weightRecordCard: some View {
        let points = weightPoints()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("体重记录", systemImage: "scalemass")
                    .font(.headline)
                Spacer()
                Button {
                    showingWeightSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            if let profile {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", profile.currentWeightKg))
                        .font(.title.weight(.semibold))
                    Text("公斤")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(lastWeightUpdateText(points))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if points.count >= 2 {
                MiniWeightChart(points: points)
                    .frame(height: 64)
            } else {
                Text("记录两次以上体重后显示趋势曲线。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 小组件

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func innerTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(color)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 数据

    /// 时间正序的体重数据点（来自每日单源 DayLog），最多最近 30 天。
    private func weightPoints() -> [MiniWeightChart.WeightPoint] {
        // DayLog 已是每日单源，直接取有体重的日子。
        dayLogs
            .filter { $0.weightKg > 0 }
            .map { MiniWeightChart.WeightPoint(date: Calendar.current.startOfDay(for: $0.date), kg: $0.weightKg) }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }

    private func lastWeightUpdateText(_ points: [MiniWeightChart.WeightPoint]) -> String {
        guard let last = points.last else { return "尚未记录体重" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: last.date),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        return days <= 0 ? "今天已更新" : "\(days) 天前更新"
    }

    /// 写入体重：统一走 WeightWriter，一致写入 UserProfile + 当天 DayLog。
    private func saveWeight(_ kg: Double) {
        guard let profile, (30...250).contains(kg) else { return }
        WeightWriter.record(kg, profile: profile, context: modelContext, dayLogs: dayLogs)

        do {
            try modelContext.save()
        } catch {
            AppLog.error("保存体重失败：\(error.localizedDescription)", category: "食物")
        }
    }
}

// MARK: - 饮食热量详情页（对应参考图二）

struct DietCalorieDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var presentingNewMeal: NewMealRequest?
    @State private var editingMeal: MealEntry?
    @State private var mealToDelete: MealEntry?
    @State private var presentingExercise = false
    @State private var showingMeals = false
    @State private var showingFoodOptions = false
    @State private var showingTrends = false
    @State private var showingTrainingPlan = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: AppMetrics.sectionSpacing) {
                weightTrendCard
                weekStrip
                ringCard
                macroCard
                habitsCard
                if dayConfirmedMeals.isEmpty {
                    emptyMealsState
                } else {
                    mealsList
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingTrends = true } label: {
                        Label("体重与趋势分析", systemImage: "chart.xyaxis.line")
                    }
                    Button { showingTrainingPlan = true } label: {
                        Label("训练计划", systemImage: "figure.strengthtraining.traditional")
                    }
                    Divider()
                    Button { showingMeals = true } label: {
                        Label("饮食记录", systemImage: "list.bullet")
                    }
                    Button { showingFoodOptions = true } label: {
                        Label("常吃食物选项", systemImage: "rectangle.stack")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingMeals) { MealsView() }
        .navigationDestination(isPresented: $showingFoodOptions) { FoodOptionsView() }
        .navigationDestination(isPresented: $showingTrends) { SummariesView() }
        .navigationDestination(isPresented: $showingTrainingPlan) { TrainingPlanListView() }
        .sheet(item: $presentingNewMeal) { request in
            MealEditorView(initialMealType: request.mealType, initialDate: request.date, autoPresentCamera: request.autoCamera)
        }
        .sheet(item: $editingMeal) { meal in
            MealEditorView(meal: meal)
        }
        .sheet(isPresented: $presentingExercise) {
            ManualExerciseEditorView(initialDate: selectedDate)
        }
        .alert("删除这条饮食记录？", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) {
                mealToDelete = nil
            }
            Button("删除", role: .destructive) {
                deletePendingMeal()
            }
        } message: {
            Text("删除后，这一餐不会再计入当天热量和营养统计。")
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    // MARK: 体重趋势卡（以周趋势为主，淡化单日噪声）

    private var weightTrendCard: some View {
        let trend = TrendSafetyAnalyzer.weightTrend(
            dayLogs: dayLogs,
            targetWeightKg: profile?.targetWeightKg ?? 0,
            currentWeightKg: profile?.currentWeightKg ?? 0
        )
        let points = trendWeightPoints()
        let goalText: String? = {
            guard let p = profile, p.targetWeightKg > 0 else { return nil }
            var parts = ["目标 \(String(format: "%.1f", p.targetWeightKg)) kg"]
            if p.weeklyRateKgGoal > 0 { parts.append("每周 \(String(format: "%.2f", p.weeklyRateKgGoal)) kg") }
            if let d = p.targetDate { parts.append("目标日 \(DateFormatter.csvDate.string(from: d))") }
            return parts.joined(separator: " · ")
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("体重趋势", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                if trend.isPlateau {
                    Text("平台期")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trend.sevenDayAverage.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .bold))
                Text("kg · 7日均值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                trendStat("14日速度", trend.fourteenDayRateKgPerWeek.map { String(format: "%+.2f kg/周", $0) } ?? "数据不足")
                trendStat("预测置信", trend.confidence)
            }
            if let range = trend.predictedTargetDateRange {
                Text("预计达标：\(DateFormatter.csvDate.string(from: range.lowerBound)) ~ \(DateFormatter.csvDate.string(from: range.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let goalText {
                Text(goalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if points.count >= 2 {
                MiniWeightChart(points: points)
                    .frame(height: 60)
            } else {
                Text("多记几次体重后显示曲线；单日波动以水分为主，看 7 日均值更准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func trendStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func trendWeightPoints() -> [MiniWeightChart.WeightPoint] {
        dayLogs
            .filter { $0.weightKg > 0 }
            .map { MiniWeightChart.WeightPoint(date: Calendar.current.startOfDay(for: $0.date), kg: $0.weightKg) }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }

    // MARK: 今日打卡卡（喝水/睡眠等闭环维度）

    private var habitsCard: some View {
        let log = dayLogs.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        let water = log?.waterMl ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Label("今日打卡", systemImage: "drop.fill")
                .font(.headline)
            HStack(spacing: 18) {
                trendStat("喝水", "\(Int(water.rounded())) ml")
                trendStat("睡眠", log?.sleepHours.map { String(format: "%.1f h", $0) } ?? "—")
            }
            HStack(spacing: 8) {
                waterButton("+250ml", 250)
                waterButton("+500ml", 500)
                if water > 0 {
                    Button(role: .destructive) { setWater(0) } label: {
                        Label("清零", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func waterButton(_ title: String, _ ml: Double) -> some View {
        Button {
            addWater(ml)
        } label: {
            Text(title).font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.blue)
    }

    private func todayOrSelectedLog() -> DayLog {
        let day = Calendar.current.startOfDay(for: selectedDate)
        if let existing = dayLogs.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            return existing
        }
        let log = DayLog(date: day)
        modelContext.insert(log)
        return log
    }

    private func addWater(_ ml: Double) {
        let log = todayOrSelectedLog()
        log.waterMl = (log.waterMl ?? 0) + ml
        log.updatedAt = .now
        try? modelContext.save()
    }

    private func setWater(_ ml: Double) {
        let log = todayOrSelectedLog()
        log.waterMl = ml
        log.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: 顶部周日期条

    private var weekStrip: some View {
        HStack {
            ForEach(weekDates, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: .now)
                Button {
                    selectedDate = Calendar.current.startOfDay(for: day)
                } label: {
                    VStack(spacing: 6) {
                        Text(weekdaySymbol(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .frame(width: 30, height: 30)
                            .background(isSelected ? Color.green : Color.clear, in: Circle())
                            .foregroundStyle(isSelected ? .white : (isFuture ? Color.secondary.opacity(0.4) : .primary))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
    }

    // MARK: 圆环

    private var ringCard: some View {
        let budget = currentBudget
        return HStack {
            sideStat(title: "饮食摄入", value: budget.intake.kcalValue)
            Spacer(minLength: 8)
            ProgressRing(
                progress: budget.recommendedBudget > 0 ? budget.intake / budget.recommendedBudget : 0,
                lineWidth: 12,
                tint: budget.remaining >= 0 ? .green : .deficitShort
            ) {
                VStack(spacing: 2) {
                    Text(budget.remaining.kcalValue)
                        .font(.system(size: 30, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("还可吃(千卡)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("推荐预算 \(Int(budget.recommendedBudget.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            Spacer(minLength: 8)
            sideStat(title: "运动消耗", value: budget.exerciseBurn.kcalValue)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func sideStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 64)
    }

    // MARK: 三大营养

    private var macroCard: some View {
        let budget = currentBudget
        let macros = dayMacros
        return VStack(spacing: 14) {
            MacroProgressRow(name: "碳水化合物", current: macros.carbs, target: budget.carbsTarget, color: .macroCarbs)
            MacroProgressRow(name: "蛋白质", current: macros.protein, target: budget.proteinTarget, color: .macroProtein)
            MacroProgressRow(name: "脂肪", current: macros.fat, target: budget.fatTarget, color: .macroFat)
        }
        .cardStyle()
    }

    // MARK: 餐食列表 / 空态

    private var emptyMealsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(Calendar.current.isDateInToday(selectedDate) ? "还没有记录今日饮食" : "这一天还没有饮食记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("用下方「AI 算热量 / 文字 / 拍照」或餐别按钮记录，自动统计热量与营养。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardStyle()
    }

    private var mealsList: some View {
        VStack(spacing: 0) {
            ForEach(dayConfirmedMeals) { meal in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        editingMeal = meal
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(meal.mealType.title) · \(DateFormatter.shortTime.string(from: meal.date))")
                                    .font(.subheadline.weight(.medium))
                                Text(meal.textDescription.isEmpty ? "—" : meal.textDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(meal.totalCalories.kcalText)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        mealToDelete = meal
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                if meal.id != dayConfirmedMeals.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    // MARK: 底部操作栏

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionChip(title: "AI 算热量", icon: "sparkles") {
                    presentingNewMeal = NewMealRequest(mealType: nil, autoCamera: false, date: defaultMealDate())
                }
                actionChip(title: "文字", icon: "pencil") {
                    presentingNewMeal = NewMealRequest(mealType: nil, autoCamera: false, date: defaultMealDate())
                }
                actionChip(title: "拍照", icon: "camera") {
                    presentingNewMeal = NewMealRequest(mealType: nil, autoCamera: true, date: defaultMealDate())
                }
            }
            HStack {
                ForEach(MealQuickEntry.allCases) { entry in
                    Button {
                        if let mealType = entry.mealType {
                            presentingNewMeal = NewMealRequest(mealType: mealType, autoCamera: false, date: defaultMealDate())
                        } else {
                            presentingExercise = true
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 16))
                            Text("+\(entry.title)")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func actionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
    }

    // MARK: 数据

    private var currentBudget: DietBudget {
        dietBudget(profile: profile, meals: meals, exercises: exercises, dayLogs: dayLogs, plans: trainingPlans, on: selectedDate)
    }

    private var dayConfirmedMeals: [MealEntry] {
        meals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }

    private var dayMacros: (protein: Double, carbs: Double, fat: Double) {
        let entries = dayConfirmedMeals
        return (
            entries.reduce(0) { $0 + $1.proteinGrams },
            entries.reduce(0) { $0 + $1.carbsGrams },
            entries.reduce(0) { $0 + $1.fatGrams }
        )
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: selectedDate)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: base) else { return [base] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func weekdaySymbol(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private var navTitle: String {
        Calendar.current.isDateInToday(selectedDate) ? "今天" : DateFormatter.dateHeader.string(from: selectedDate)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { mealToDelete != nil },
            set: { if !$0 { mealToDelete = nil } }
        )
    }

    private func defaultMealDate() -> Date {
        if Calendar.current.isDateInToday(selectedDate) {
            return .now
        }
        let nowComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
        var selectedComponents = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        selectedComponents.hour = nowComponents.hour
        selectedComponents.minute = nowComponents.minute
        selectedComponents.second = nowComponents.second
        return Calendar.current.date(from: selectedComponents) ?? selectedDate
    }

    private func deletePendingMeal() {
        guard let meal = mealToDelete else { return }
        modelContext.delete(meal)
        mealToDelete = nil
        do {
            try modelContext.save()
        } catch {
            AppLog.error("删除饮食记录失败：\(error.localizedDescription)", category: "食物")
        }
    }
}

// MARK: - 共享：每日预算与运动消耗（食物 Tab 与详情页共用）

/// 计算指定日期的饮食预算与营养目标。预算/营养优先取最新训练计划，否则回退到 BMR 估算。
private func dietBudget(
    profile: UserProfile?,
    meals: [MealEntry],
    exercises: [ExerciseEntry],
    dayLogs: [DayLog],
    plans: [TrainingPlan],
    on date: Date
) -> DietBudget {
    guard let profile else {
        return DietBudget(recommendedBudget: 0, intake: 0, exerciseBurn: 0, remaining: 0, proteinTarget: 0, carbsTarget: 0, fatTarget: 0)
    }
    // 摄入与运动消耗统一走唯一聚合源（活动消耗已去重：健康聚合 + 手动）。
    let metrics = DayMetricsCalculator.metrics(
        for: date,
        profile: profile,
        meals: meals,
        exercises: exercises,
        dayLogs: dayLogs,
        trainingPlans: plans
    )
    let plan = plans.first
    return DietBudgetCalculator.compute(
        profile: profile,
        intakeCalories: metrics.intakeCalories,
        exerciseBurnCalories: metrics.activeCalories,
        planDailyCalories: plan?.dailyCalories,
        planProteinGrams: plan?.proteinGrams,
        planCarbsGrams: plan?.carbsGrams,
        planFatGrams: plan?.fatGrams
    )
}

// MARK: - 体重输入弹窗

private struct WeightInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Double) -> Void

    @State private var text = ""

    private var value: Double? { text.doubleValue }
    private var valid: Bool { value.map { (30...250).contains($0) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextFieldRow(title: "体重", unit: "kg", text: $text)
                } footer: {
                    Text("保存后会同步到「今日」页与体重趋势。")
                }
            }
            .navigationTitle("记录今日体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let value {
                            onSave(value)
                            dismiss()
                        }
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
