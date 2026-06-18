import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @State private var showingNewMeal = false
    @State private var editingMeal: MealEntry?

    /// 按「自然日」分组，日期倒序；组内再按时间倒序。
    private var groupedMeals: [(day: Date, meals: [MealEntry])] {
        let groups = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, meals: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("还没有饮食记录", systemImage: "fork.knife")
                    } description: {
                        Text("点击右上角 + 记录今天吃了什么，AI 会帮你估算热量和营养。")
                    } actions: {
                        Button {
                            showingNewMeal = true
                        } label: {
                            Label("新增饮食", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(groupedMeals, id: \.day) { group in
                            Section(DateFormatter.dateHeader.string(from: group.day)) {
                                ForEach(group.meals) { meal in
                                    Button {
                                        editingMeal = meal
                                    } label: {
                                        MealRow(meal: meal)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(meal)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("饮食")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewMeal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增饮食")
                }
            }
            .sheet(isPresented: $showingNewMeal) {
                MealEditorView()
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
        }
    }

    private func delete(_ meal: MealEntry) {
        modelContext.delete(meal)
        try? modelContext.save()
    }
}

/// 饮食列表行：缩略图 + 时间/热量 + 描述 + 营养素。
private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(meal.mealType.title) · \(DateFormatter.shortTime.string(from: meal.date))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(meal.totalCalories.kcalText)
                        .font(.headline)
                }
                Text(meal.textDescription.isEmpty ? "未填写描述" : meal.textDescription)
                    .font(.body)
                    .lineLimit(2)
                if !meal.optionExtraNote.isEmpty {
                    Text("备注：\(meal.optionExtraNote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    MacroLabel(name: "蛋白", grams: meal.proteinGrams, color: .macroProtein)
                    MacroLabel(name: "碳水", grams: meal.carbsGrams, color: .macroCarbs)
                    MacroLabel(name: "脂肪", grams: meal.fatGrams, color: .macroFat)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = meal.photoLocalPath,
           let url = ImageStorage.mealPhotoURL(fileName: path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient

    @Query private var settings: [AISettings]
    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.date, order: .reverse) private var mealHistory: [MealEntry]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]

    private let maxImageCount = 8
    /// 非空表示编辑既有记录，nil 表示新增。
    private let editingMeal: MealEntry?
    /// 新增时是否自动弹出相机（供详情页「拍照」入口）。
    private let autoPresentCamera: Bool

    @State private var mealDate: Date
    @State private var mealType: MealType
    @State private var textDescription: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @State private var showingCamera = false
    @State private var totalCalories: String
    @State private var proteinGrams: String
    @State private var carbsGrams: String
    @State private var fatGrams: String
    @State private var fiberGrams: String
    @State private var vegetableGrams: String
    @State private var confidence: Double
    @State private var items: [MealFoodItem]
    @State private var selectedFoodOptionIDs: Set<UUID>
    @State private var optionExtraNote: String
    @State private var showingFoodOptionPicker = false
    @State private var saveAsFoodOption = false
    @State private var newFoodOptionKind: FoodOptionKind
    @State private var newFoodOptionName: String
    @State private var isEstimating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didAutoPresentCamera = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case description
        case totalCalories
        case proteinGrams
        case carbsGrams
        case fatGrams
        case optionExtraNote
        case newFoodOptionName
    }

    init(
        meal: MealEntry? = nil,
        initialMealType: MealType? = nil,
        initialDate: Date? = nil,
        autoPresentCamera: Bool = false
    ) {
        self.editingMeal = meal
        self.autoPresentCamera = autoPresentCamera
        _mealDate = State(initialValue: meal?.date ?? initialDate ?? .now)
        _mealType = State(initialValue: meal?.mealType ?? initialMealType ?? .other)
        _textDescription = State(initialValue: meal?.textDescription ?? "")
        _totalCalories = State(initialValue: Self.numberText(meal?.totalCalories, decimals: 0))
        _proteinGrams = State(initialValue: Self.numberText(meal?.proteinGrams, decimals: 1))
        _carbsGrams = State(initialValue: Self.numberText(meal?.carbsGrams, decimals: 1))
        _fatGrams = State(initialValue: Self.numberText(meal?.fatGrams, decimals: 1))
        _fiberGrams = State(initialValue: Self.numberText(meal?.fiberGrams, decimals: 1))
        _vegetableGrams = State(initialValue: Self.numberText(meal?.vegetableGrams, decimals: 0))
        _confidence = State(initialValue: meal?.confidence ?? 0)
        _items = State(initialValue: meal?.estimatedItems ?? [])
        _selectedFoodOptionIDs = State(initialValue: Set(meal?.foodOptionIDs ?? []))
        _optionExtraNote = State(initialValue: meal?.optionExtraNote ?? "")
        _newFoodOptionKind = State(initialValue: (meal?.estimatedItems.count ?? 0) > 1 ? .combo : .single)
        _newFoodOptionName = State(initialValue: meal?.textDescription ?? "")
    }

    private var isEditing: Bool { editingMeal != nil }

    private var canEstimate: Bool {
        !textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageDataList.isEmpty
    }

    private var selectedFoodOptions: [FoodOption] {
        foodOptions.filter { selectedFoodOptionIDs.contains($0.id) }
    }

    private var confidenceColor: Color {
        if confidence >= 0.7 { return .green }
        if confidence >= 0.4 { return .orange }
        return .red
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section("记录") {
                    Picker("餐别", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    DatePicker("吃饭时间", selection: $mealDate)
                    TextEditor(text: $textDescription)
                        .frame(minHeight: 96)
                        .focused($focusedField, equals: .description)
                        .overlay(alignment: .topLeading) {
                            if textDescription.isEmpty {
                                Text("描述这一餐，例如「两个鸡蛋 + 一碗燕麦 + 一杯豆浆」")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(1, maxImageCount - imageDataList.count),
                        matching: .images
                    ) {
                        Label("从相册选择多张", systemImage: "photo.on.rectangle")
                    }
                    .disabled(imageDataList.count >= maxImageCount)
                    Button {
                        showingCamera = true
                    } label: {
                        Label("拍照追加", systemImage: "camera")
                    }
                    .disabled(imageDataList.count >= maxImageCount)

                    if !imageDataList.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(imageDataList.enumerated()), id: \.offset) { index, imageData in
                                    if let image = UIImage(data: imageData) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 96, height: 96)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Button {
                                                imageDataList.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.55))
                                                    .font(.title3)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(4)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        Text("已选择 \(imageDataList.count) / \(maxImageCount) 张图片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showingFoodOptionPicker = true
                    } label: {
                        Label(
                            selectedFoodOptions.isEmpty ? "选择常吃食物或套餐" : "已选择 \(selectedFoodOptions.count) 个选项卡",
                            systemImage: "rectangle.stack"
                        )
                    }

                    if !selectedFoodOptions.isEmpty {
                        ForEach(selectedFoodOptions) { option in
                            HStack(spacing: 10) {
                                FoodOptionThumbnail(path: option.photoLocalPath, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(option.kind.title) · \(option.totalCalories.kcalText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedFoodOptionIDs.remove(option.id)
                                    applySelectedFoodOptions()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        TextField("这一顿的额外备注，例如 少饭 / 加蛋 / 酱料减半", text: $optionExtraNote)
                            .focused($focusedField, equals: .optionExtraNote)

                        Button {
                            applySelectedFoodOptions()
                        } label: {
                            Label("套用到本次饮食", systemImage: "arrow.down.doc")
                        }
                    }
                } header: {
                    Text("食物选项卡")
                } footer: {
                    Text("选择后会自动带入热量、营养明细和描述，额外备注只作用于这一顿。")
                }

                Section {
                    Toggle("记录并且新增为食物选项卡", isOn: $saveAsFoodOption)
                    if saveAsFoodOption {
                        Picker("选项卡类型", selection: $newFoodOptionKind) {
                            ForEach(FoodOptionKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        TextField("选项卡名称", text: $newFoodOptionName)
                            .focused($focusedField, equals: .newFoodOptionName)
                    }
                } footer: {
                    Text("开启后，本次饮食保存成功时会同步生成一个食物选项卡；必须带有照片或营养表照片。")
                }

                Section("AI 估算") {
                    Button {
                        Task { await estimate() }
                    } label: {
                        if isEstimating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("估算中…")
                            }
                        } else {
                            Label("估算热量", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canEstimate || isEstimating)

                    nutrientInputRow("总热量", text: $totalCalories, unit: "kcal", focus: .totalCalories)
                    nutrientInputRow("蛋白质", text: $proteinGrams, unit: "g", focus: .proteinGrams)
                    nutrientInputRow("碳水", text: $carbsGrams, unit: "g", focus: .carbsGrams)
                    nutrientInputRow("脂肪", text: $fatGrams, unit: "g", focus: .fatGrams)
                    LabeledTextFieldRow(title: "膳食纤维", unit: "g", prompt: "选填", text: $fiberGrams)
                    LabeledTextFieldRow(title: "蔬菜", unit: "g", prompt: "选填", text: $vegetableGrams)
                    if confidence > 0 {
                        MetricProgressBar(title: "AI 置信度", current: confidence, target: 1, tint: confidenceColor)
                            .padding(.vertical, 2)
                    }
                }

                if !items.isEmpty {
                    Section("食物明细") {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(item.calories.kcalText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 12) {
                                    MacroLabel(name: "蛋白", grams: item.proteinGrams, color: .macroProtein)
                                    MacroLabel(name: "碳水", grams: item.carbsGrams, color: .macroCarbs)
                                    MacroLabel(name: "脂肪", grams: item.fatGrams, color: .macroFat)
                                }
                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            dismissKeyboard()
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除本餐", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑饮食" : "新增饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismissKeyboard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismissKeyboard()
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(totalCalories.doubleValue == nil || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button {
                            dismissKeyboard()
                        } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .onSubmit { dismissKeyboard() }
            .alert("删除这条饮食记录？", isPresented: $showingDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteEditingMeal()
                }
            } message: {
                Text("删除后，这一餐不会再计入当天热量和营养统计。")
            }
            .onAppear {
                loadExistingPhotoIfNeeded()
                if autoPresentCamera, !isEditing, !didAutoPresentCamera {
                    didAutoPresentCamera = true
                    showingCamera = true
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                Task { await appendPhotos(newValue) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in
                    guard imageDataList.count < maxImageCount,
                          let data = ImageStorage.compressedJPEGData(from: image) else { return }
                    imageDataList.append(data)
                }
            }
            .sheet(isPresented: $showingFoodOptionPicker, onDismiss: {
                applySelectedFoodOptions()
            }) {
                FoodOptionPickerSheet(foodOptions: foodOptions, selectedIDs: $selectedFoodOptionIDs)
            }
        }
    }

    private func nutrientInputRow(_ title: String, text: Binding<String>, unit: String, focus: FocusedField) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: focus)
                .submitLabel(.done)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func deleteEditingMeal() {
        guard let editingMeal else { return }
        modelContext.delete(editingMeal)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("删除饮食记录失败：\(error.localizedDescription)", category: "饮食")
            errorMessage = error.localizedDescription
        }
    }

    /// 编辑既有记录时，把已存的首图加载进来用于预览与重存。
    private func loadExistingPhotoIfNeeded() {
        guard imageDataList.isEmpty,
              let path = editingMeal?.photoLocalPath,
              let url = ImageStorage.mealPhotoURL(fileName: path),
              let data = try? Data(contentsOf: url) else { return }
        imageDataList = [data]
    }

    /// 相册多选与拍照共用 imageDataList 作为唯一数据源：新选中的照片追加到列表，
    /// 随后清空 PhotosPicker 选择，避免相册选择覆盖拍照结果或删除时下标错位。
    @MainActor
    private func appendPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            guard imageDataList.count < maxImageCount else { break }
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let compressed = ImageStorage.compressedJPEGData(from: image) {
                    imageDataList.append(compressed)
                }
            } catch {
                AppLog.error("读取照片失败：\(error.localizedDescription)", category: "饮食")
                errorMessage = error.localizedDescription
            }
        }
        selectedPhotos = []
    }

    private func applySelectedFoodOptions() {
        let options = selectedFoodOptions
        guard !options.isEmpty else { return }

        let calories = options.reduce(0) { $0 + $1.totalCalories }
        let protein = options.reduce(0) { $0 + $1.proteinGrams }
        let carbs = options.reduce(0) { $0 + $1.carbsGrams }
        let fat = options.reduce(0) { $0 + $1.fatGrams }
        totalCalories = String(format: "%.0f", calories)
        proteinGrams = String(format: "%.1f", protein)
        carbsGrams = String(format: "%.1f", carbs)
        fatGrams = String(format: "%.1f", fat)
        confidence = averageConfidence(for: options)
        items = options.flatMap { option in
            option.mealItems(optionNote: optionExtraNote)
        }

        let optionText = options
            .map { option -> String in
                let portion = option.portionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                return portion.isEmpty ? option.name : "\(option.name)(\(portion))"
            }
            .joined(separator: " + ")
        let note = optionExtraNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = note.isEmpty ? "选项卡：\(optionText)" : "选项卡：\(optionText)。备注：\(note)"
        if textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || textDescription.hasPrefix("选项卡：") {
            textDescription = description
        }
        if newFoodOptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newFoodOptionName = options.count == 1 ? options[0].name : options.map(\.name).joined(separator: " + ")
        }
    }

    private func averageConfidence(for options: [FoodOption]) -> Double {
        let values = options.map(\.confidence).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    @MainActor
    private func estimate() async {
        guard let aiSettings = settings.first else { return }
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }

        let bodyContext = profiles.first.map {
            "身高\(Int($0.heightCm))cm、体重\(String(format: "%.1f", $0.currentWeightKg))kg、\($0.gender.title)、\($0.age)岁"
        }
        do {
            let estimate = try await aiClient.estimateMeal(
                text: textDescription,
                imageDataList: imageDataList,
                settings: aiSettings,
                bodyContext: bodyContext
            )
            totalCalories = String(format: "%.0f", estimate.totalCalories)
            proteinGrams = String(format: "%.1f", estimate.proteinGrams)
            carbsGrams = String(format: "%.1f", estimate.carbsGrams)
            fatGrams = String(format: "%.1f", estimate.fatGrams)
            fiberGrams = Self.numberText(estimate.fiberGrams, decimals: 1)
            vegetableGrams = Self.numberText(estimate.vegetableGrams, decimals: 0)
            confidence = estimate.confidence
            items = estimate.items
            if textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textDescription = estimate.summary
            }
        } catch {
            AppLog.error("识别餐食失败：\(error.localizedDescription)", category: "饮食")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        if saveAsFoodOption && imageDataList.isEmpty && editingMeal?.photoLocalPath == nil {
            errorMessage = "新增食物选项卡需要照片或营养表照片"
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let photoFileName: String?
            if let firstImageData = imageDataList.first {
                photoFileName = try ImageStorage.saveMealPhoto(data: firstImageData)
            } else {
                photoFileName = editingMeal?.photoLocalPath
            }

            let savedMeal: MealEntry
            if let editingMeal {
                editingMeal.date = mealDate
                editingMeal.mealType = mealType
                editingMeal.textDescription = textDescription
                editingMeal.photoLocalPath = photoFileName
                editingMeal.foodOptionIDs = Array(selectedFoodOptionIDs)
                editingMeal.optionExtraNote = optionExtraNote
                editingMeal.estimatedItems = items
                editingMeal.totalCalories = totalCalories.doubleValue ?? 0
                editingMeal.proteinGrams = proteinGrams.doubleValue ?? 0
                editingMeal.carbsGrams = carbsGrams.doubleValue ?? 0
                editingMeal.fatGrams = fatGrams.doubleValue ?? 0
                editingMeal.fiberGrams = fiberGrams.doubleValue ?? 0
                editingMeal.vegetableGrams = vegetableGrams.doubleValue ?? 0
                editingMeal.confidence = confidence
                editingMeal.isConfirmed = true
                editingMeal.updatedAt = .now
                savedMeal = editingMeal
            } else {
                let meal = MealEntry(
                    date: mealDate,
                    mealType: mealType,
                    textDescription: textDescription,
                    photoLocalPath: photoFileName,
                    foodOptionIDs: Array(selectedFoodOptionIDs),
                    optionExtraNote: optionExtraNote,
                    estimatedItems: items,
                    totalCalories: totalCalories.doubleValue ?? 0,
                    proteinGrams: proteinGrams.doubleValue ?? 0,
                    carbsGrams: carbsGrams.doubleValue ?? 0,
                    fatGrams: fatGrams.doubleValue ?? 0,
                    fiberGrams: fiberGrams.doubleValue ?? 0,
                    vegetableGrams: vegetableGrams.doubleValue ?? 0,
                    confidence: confidence,
                    isConfirmed: true
                )
                modelContext.insert(meal)
                savedMeal = meal
            }
            try modelContext.save()
            if saveAsFoodOption {
                try createFoodOption(from: savedMeal, photoFileName: photoFileName)
                try modelContext.save()
            }
            // 餐食点评不再在保存时自动生成；统一改由「教练」对话给出，避免重复 AI 调用与割裂体验。
            dismiss()
        } catch {
            AppLog.error("保存饮食记录失败：\(error.localizedDescription)", category: "饮食")
            errorMessage = error.localizedDescription
        }
    }

    private func createFoodOption(from meal: MealEntry, photoFileName: String?) throws {
        guard let photoFileName else {
            throw AIClientError.transport("新增食物选项卡需要照片或营养表照片")
        }
        let optionName = newFoodOptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultFoodOptionName(for: meal)
            : newFoodOptionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceItems = meal.estimatedItems.isEmpty
            ? [MealFoodItem(name: optionName, calories: meal.totalCalories, proteinGrams: meal.proteinGrams, carbsGrams: meal.carbsGrams, fatGrams: meal.fatGrams, note: optionExtraNote)]
            : meal.estimatedItems
        let components = sourceItems.map { item in
            FoodOptionComponent(
                name: item.name,
                portionDescription: item.note,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                note: item.note
            )
        }
        let score = localRecommendationScore(calories: meal.totalCalories, protein: meal.proteinGrams, fat: meal.fatGrams)
        let option = FoodOption(
            name: optionName,
            kind: newFoodOptionKind,
            photoLocalPath: photoFileName,
            sourceDescription: "由 \(meal.mealType.title) 饮食记录生成：\(meal.textDescription)",
            portionDescription: optionExtraNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "本次记录份量" : optionExtraNote,
            components: components,
            totalCalories: meal.totalCalories,
            proteinGrams: meal.proteinGrams,
            carbsGrams: meal.carbsGrams,
            fatGrams: meal.fatGrams,
            fiberGrams: meal.fiberGrams,
            sodiumMg: 0,
            dataSource: "mealRecord",
            confidence: meal.confidence,
            recommendationScore: score,
            recommendationReason: "根据本次记录自动生成，建议后续在食物页补充营养表或重新用视觉 AI 校准。",
            aiSummary: meal.textDescription
        )
        modelContext.insert(option)
    }

    private func defaultFoodOptionName(for meal: MealEntry) -> String {
        let trimmed = meal.textDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(meal.mealType.title)选项卡"
        }
        return String(trimmed.prefix(24))
    }

    private func localRecommendationScore(calories: Double, protein: Double, fat: Double) -> Double {
        guard calories > 0 else { return 50 }
        let proteinPer100Kcal = protein / calories * 100
        let fatRatio = fat * 9 / max(calories, 1)
        var score = 60.0
        score += min(proteinPer100Kcal * 4, 25)
        if calories <= 650 { score += 10 } else { score -= min((calories - 650) / 30, 20) }
        if fatRatio > 0.45 { score -= 12 }
        return min(max(score, 20), 95)
    }

    @MainActor
    private func generateAndArchiveAdvice(for meal: MealEntry) async {
        guard let profile = profiles.first else { return }
        guard let aiSettings = settings.first else {
            AppLog.error("生成餐食建议失败：尚未配置 AI（AISettings 为空）", category: "AI餐食建议")
            return
        }
        let snapshot = buildMealAdviceSnapshot(for: meal, profile: profile)
        let response: MealAdviceResponse
        do {
            response = try await aiClient.generateMealAdvice(snapshot: snapshot, settings: aiSettings)
        } catch {
            AppLog.error("生成餐食建议失败：\(error.localizedDescription)", category: "AI餐食建议")
            return
        }

        modelContext.insert(MealAdviceRecord(
            mealID: meal.id,
            mealDate: meal.date,
            mealType: meal.mealType,
            mealDescription: meal.textDescription,
            mealCalories: meal.totalCalories,
            mealReview: response.mealReview,
            nextMealAdvice: response.nextMealAdvice,
            snackAdvice: response.snackAdvice,
            caution: response.caution,
            snapshot: snapshot
        ))
        try? modelContext.save()
    }

    private func buildMealAdviceSnapshot(for meal: MealEntry, profile: UserProfile) -> MealAdviceSnapshot {
        // 通过唯一聚合源计算当天指标：活动消耗已去重（健康聚合 + 手动，不再累加单次 workout），
        // 目标缺口走统一口径（训练计划优先）。确保刚保存的这一餐计入（@Query 可能尚未刷新）。
        let allMeals = mealHistory.contains { $0.id == meal.id } ? mealHistory : mealHistory + [meal]
        let metrics = DayMetricsCalculator.metrics(
            for: meal.date,
            profile: profile,
            meals: allMeals,
            exercises: exercises,
            dayLogs: dayLogs,
            trainingPlans: trainingPlans
        )

        return MealAdviceSnapshot(
            mealID: meal.id,
            mealType: meal.mealType.title,
            mealDate: meal.date,
            mealDescription: meal.textDescription,
            mealCalories: meal.totalCalories,
            mealProteinGrams: meal.proteinGrams,
            mealCarbsGrams: meal.carbsGrams,
            mealFatGrams: meal.fatGrams,
            todayMeals: metrics.mealsText,
            todayIntakeCalories: metrics.intakeCalories,
            todayProteinGrams: metrics.proteinGrams,
            todayCarbsGrams: metrics.carbsGrams,
            todayFatGrams: metrics.fatGrams,
            todayActiveCalories: metrics.activeCalories,
            todayRestingCalories: metrics.restingCalories,
            todayCalorieDeficit: metrics.calorieDeficit,
            goal: profile.goal.title,
            targetDailyDeficitKcal: metrics.effectiveDeficitTarget,
            weightKg: metrics.weightKg ?? profile.currentWeightKg,
            analysis: metrics.analysis
        )
    }

    /// 把可选的数值格式化为输入框文本：nil 或 0 时返回空串，避免新增时预填 "0"。
    private static func numberText(_ value: Double?, decimals: Int) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%.\(decimals)f", value)
    }
}
