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
                    Text(DateFormatter.shortTime.string(from: meal.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(meal.totalCalories.kcalText)
                        .font(.headline)
                }
                Text(meal.textDescription.isEmpty ? "未填写描述" : meal.textDescription)
                    .font(.body)
                    .lineLimit(2)
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

    private let maxImageCount = 8
    /// 非空表示编辑既有记录，nil 表示新增。
    private let editingMeal: MealEntry?

    @State private var textDescription: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @State private var showingCamera = false
    @State private var totalCalories: String
    @State private var proteinGrams: String
    @State private var carbsGrams: String
    @State private var fatGrams: String
    @State private var confidence: Double
    @State private var items: [MealFoodItem]
    @State private var isEstimating = false
    @State private var errorMessage: String?

    init(meal: MealEntry? = nil) {
        self.editingMeal = meal
        _textDescription = State(initialValue: meal?.textDescription ?? "")
        _totalCalories = State(initialValue: Self.numberText(meal?.totalCalories, decimals: 0))
        _proteinGrams = State(initialValue: Self.numberText(meal?.proteinGrams, decimals: 1))
        _carbsGrams = State(initialValue: Self.numberText(meal?.carbsGrams, decimals: 1))
        _fatGrams = State(initialValue: Self.numberText(meal?.fatGrams, decimals: 1))
        _confidence = State(initialValue: meal?.confidence ?? 0)
        _items = State(initialValue: meal?.estimatedItems ?? [])
    }

    private var isEditing: Bool { editingMeal != nil }

    private var canEstimate: Bool {
        !textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageDataList.isEmpty
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
                    TextEditor(text: $textDescription)
                        .frame(minHeight: 96)
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

                    TextField("总热量 kcal", text: $totalCalories)
                        .keyboardType(.decimalPad)
                    TextField("蛋白质 g", text: $proteinGrams)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $carbsGrams)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 g", text: $fatGrams)
                        .keyboardType(.decimalPad)
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
            }
            .navigationTitle(isEditing ? "编辑饮食" : "新增饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(totalCalories.doubleValue == nil)
                }
            }
            .onAppear { loadExistingPhotoIfNeeded() }
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
                errorMessage = error.localizedDescription
            }
        }
        selectedPhotos = []
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
            confidence = estimate.confidence
            items = estimate.items
            if textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textDescription = estimate.summary
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let photoFileName: String?
            if let firstImageData = imageDataList.first {
                photoFileName = try ImageStorage.saveMealPhoto(data: firstImageData)
            } else {
                photoFileName = nil
            }

            if let editingMeal {
                editingMeal.textDescription = textDescription
                editingMeal.photoLocalPath = photoFileName
                editingMeal.estimatedItems = items
                editingMeal.totalCalories = totalCalories.doubleValue ?? 0
                editingMeal.proteinGrams = proteinGrams.doubleValue ?? 0
                editingMeal.carbsGrams = carbsGrams.doubleValue ?? 0
                editingMeal.fatGrams = fatGrams.doubleValue ?? 0
                editingMeal.confidence = confidence
                editingMeal.isConfirmed = true
                editingMeal.updatedAt = .now
            } else {
                modelContext.insert(MealEntry(
                    date: .now,
                    textDescription: textDescription,
                    photoLocalPath: photoFileName,
                    estimatedItems: items,
                    totalCalories: totalCalories.doubleValue ?? 0,
                    proteinGrams: proteinGrams.doubleValue ?? 0,
                    carbsGrams: carbsGrams.doubleValue ?? 0,
                    fatGrams: fatGrams.doubleValue ?? 0,
                    confidence: confidence,
                    isConfirmed: true
                ))
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 把可选的数值格式化为输入框文本：nil 或 0 时返回空串，避免新增时预填 "0"。
    private static func numberText(_ value: Double?, decimals: Int) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%.\(decimals)f", value)
    }
}
