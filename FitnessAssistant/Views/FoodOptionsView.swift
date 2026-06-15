import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct FoodOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]

    @State private var filter: FoodOptionFilter = .all
    @State private var showingEditor = false
    @State private var editingOption: FoodOption?

    private var filteredOptions: [FoodOption] {
        switch filter {
        case .all:
            foodOptions
        case .single:
            foodOptions.filter { $0.kind == .single }
        case .combo:
            foodOptions.filter { $0.kind == .combo }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if foodOptions.isEmpty {
                    ContentUnavailableView {
                        Label("还没有食物选项卡", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("把最近常吃的单品或固定套餐保存下来，记录饮食时可以直接套用。")
                    } actions: {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("新增选项卡", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            Picker("筛选", selection: $filter) {
                                ForEach(FoodOptionFilter.allCases) { optionFilter in
                                    Text(optionFilter.title).tag(optionFilter)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section {
                            ForEach(filteredOptions) { option in
                                Button {
                                    editingOption = option
                                } label: {
                                    FoodOptionCard(option: option)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(option)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("食物")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增食物选项卡")
                }
            }
            .sheet(isPresented: $showingEditor) {
                FoodOptionEditorView()
            }
            .sheet(item: $editingOption) { option in
                FoodOptionEditorView(option: option)
            }
        }
    }

    private func delete(_ option: FoodOption) {
        modelContext.delete(option)
        try? modelContext.save()
    }
}
private enum FoodOptionFilter: String, CaseIterable, Identifiable {
    case all
    case single
    case combo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .single: "单品"
        case .combo: "套餐"
        }
    }
}

struct FoodOptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient

    @Query private var settings: [AISettings]
    @Query private var profiles: [UserProfile]

    private let option: FoodOption?
    private let maxImageCount = 4

    @State private var name: String
    @State private var kind: FoodOptionKind
    @State private var sourceDescription: String
    @State private var portionDescription: String
    @State private var totalCalories: String
    @State private var proteinGrams: String
    @State private var carbsGrams: String
    @State private var fatGrams: String
    @State private var confidence: Double
    @State private var recommendationScore: Double
    @State private var recommendationReason: String
    @State private var aiSummary: String
    @State private var components: [FoodOptionComponent]
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @State private var showingCamera = false
    @State private var isEstimating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case name
        case description
        case portion
        case totalCalories
        case protein
        case carbs
        case fat
        case reason
        case summary
    }

    init(option: FoodOption? = nil) {
        self.option = option
        _name = State(initialValue: option?.name ?? "")
        _kind = State(initialValue: option?.kind ?? .single)
        _sourceDescription = State(initialValue: option?.sourceDescription ?? "")
        _portionDescription = State(initialValue: option?.portionDescription ?? "")
        _totalCalories = State(initialValue: Self.numberText(option?.totalCalories, decimals: 0))
        _proteinGrams = State(initialValue: Self.numberText(option?.proteinGrams, decimals: 1))
        _carbsGrams = State(initialValue: Self.numberText(option?.carbsGrams, decimals: 1))
        _fatGrams = State(initialValue: Self.numberText(option?.fatGrams, decimals: 1))
        _confidence = State(initialValue: option?.confidence ?? 0)
        _recommendationScore = State(initialValue: option?.recommendationScore ?? 70)
        _recommendationReason = State(initialValue: option?.recommendationReason ?? "")
        _aiSummary = State(initialValue: option?.aiSummary ?? "")
        _components = State(initialValue: option?.components ?? [])
    }

    private var hasPhotoEvidence: Bool {
        !imageDataList.isEmpty || option?.photoLocalPath != nil
    }

    private var canEstimate: Bool {
        hasPhotoEvidence && settings.first != nil && !isEstimating
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasPhotoEvidence
            && totalCalories.doubleValue != nil
            && proteinGrams.doubleValue != nil
            && carbsGrams.doubleValue != nil
            && fatGrams.doubleValue != nil
            && !isSaving
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

                Section("选项卡") {
                    Picker("类型", selection: $kind) {
                        ForEach(FoodOptionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("名称，例如 鸡胸饭 / 茶叶蛋", text: $name)
                        .focused($focusedField, equals: .name)

                    TextField("总份量，例如 1 份约 350g", text: $portionDescription)
                        .focused($focusedField, equals: .portion)

                    TextEditor(text: $sourceDescription)
                        .frame(minHeight: 80)
                        .focused($focusedField, equals: .description)
                        .overlay(alignment: .topLeading) {
                            if sourceDescription.isEmpty {
                                Text("补充包装规格、做法、品牌或固定搭配；照片或营养表仍是必需的。")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(1, maxImageCount - imageDataList.count),
                        matching: .images
                    ) {
                        Label("上传食物照片或营养表", systemImage: "photo.on.rectangle")
                    }
                    .disabled(imageDataList.count >= maxImageCount)

                    Button {
                        showingCamera = true
                    } label: {
                        Label("拍照上传", systemImage: "camera")
                    }
                    .disabled(imageDataList.count >= maxImageCount)

                    if !imageDataList.isEmpty {
                        FoodOptionImageStrip(imageDataList: $imageDataList)
                    } else if let photoLocalPath = option?.photoLocalPath {
                        FoodOptionExistingPhoto(path: photoLocalPath)
                    }
                } header: {
                    Text("照片或营养表")
                } footer: {
                    Text("新增选项卡必须上传食物照片或营养表照片。AI 估算后仍可手动修改。")
                }

                Section("视觉 AI 估算") {
                    Button {
                        Task { await estimate() }
                    } label: {
                        if isEstimating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("识别中…")
                            }
                        } else {
                            Label("识别照片并计算营养", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canEstimate)

                    TextField("总热量 kcal", text: $totalCalories)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .totalCalories)
                    TextField("蛋白质 g", text: $proteinGrams)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .protein)
                    TextField("碳水 g", text: $carbsGrams)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .carbs)
                    TextField("脂肪 g", text: $fatGrams)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .fat)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("AI 推荐指数")
                            Spacer()
                            Text("\(Int(recommendationScore.rounded())) / 100")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $recommendationScore, in: 0...100, step: 1)
                    }

                    TextEditor(text: $recommendationReason)
                        .frame(minHeight: 72)
                        .focused($focusedField, equals: .reason)
                        .overlay(alignment: .topLeading) {
                            if recommendationReason.isEmpty {
                                Text("推荐或不推荐的原因")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }

                    if confidence > 0 {
                        MetricProgressBar(title: "AI 置信度", current: confidence, target: 1, tint: confidence >= 0.7 ? .green : .orange)
                    }
                }

                Section {
                    MacroRatioBar(
                        proteinRatio: macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).protein,
                        carbsRatio: macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).carbs,
                        fatRatio: macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).fat
                    )
                    LabeledContent("蛋白占比", value: "\(Int((macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).protein * 100).rounded()))%")
                    LabeledContent("碳水占比", value: "\(Int((macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).carbs * 100).rounded()))%")
                    LabeledContent("脂肪占比", value: "\(Int((macroRatio(protein: proteinGrams.doubleValue ?? 0, carbs: carbsGrams.doubleValue ?? 0, fat: fatGrams.doubleValue ?? 0).fat * 100).rounded()))%")
                } header: {
                    Text("营养成分占比")
                }

                Section {
                    ForEach($components) { $component in
                        FoodOptionComponentEditor(component: $component)
                    }
                    .onDelete { offsets in
                        components.remove(atOffsets: offsets)
                    }

                    Button {
                        components.append(FoodOptionComponent(
                            name: "新食物",
                            portionDescription: "",
                            calories: 0,
                            proteinGrams: 0,
                            carbsGrams: 0,
                            fatGrams: 0
                        ))
                    } label: {
                        Label("添加组成食物", systemImage: "plus")
                    }

                    Button {
                        syncTotalsFromComponents()
                    } label: {
                        Label("用明细汇总总营养", systemImage: "sum")
                    }
                    .disabled(components.isEmpty)
                } header: {
                    Text(kind == .combo ? "套餐固定搭配" : "单品明细")
                } footer: {
                    Text("套餐建议拆成多个定量食物；单品保留一条明细即可。")
                }

                Section("AI 总结") {
                    TextEditor(text: $aiSummary)
                        .frame(minHeight: 72)
                        .focused($focusedField, equals: .summary)
                }
            }
            .navigationTitle(option == nil ? "新增食物" : "编辑食物")
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
                    .disabled(!canSave)
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

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadExistingPhotoIfNeeded() {
        guard imageDataList.isEmpty,
              let path = option?.photoLocalPath,
              let url = ImageStorage.mealPhotoURL(fileName: path),
              let data = try? Data(contentsOf: url) else { return }
        imageDataList = [data]
    }

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
                errorMessage = "读取照片失败：\(error.localizedDescription)"
            }
        }
        selectedPhotos = []
    }

    @MainActor
    private func estimate() async {
        guard let aiSettings = settings.first else {
            errorMessage = "请先在设置中保存 AI 配置"
            return
        }
        guard hasPhotoEvidence else {
            errorMessage = "请先上传食物照片或营养表照片"
            return
        }

        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }

        let bodyContext = profiles.first.map {
            "身高\(Int($0.heightCm))cm、体重\(String(format: "%.1f", $0.currentWeightKg))kg、\($0.gender.title)、\($0.age)岁、目标\($0.goal.title)"
        }

        do {
            let estimate = try await aiClient.estimateFoodOption(
                name: name,
                kind: kind,
                sourceDescription: sourceDescription,
                imageDataList: imageDataList,
                settings: aiSettings,
                bodyContext: bodyContext
            )
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = estimate.name
            }
            if let kindRaw = estimate.kind, let estimatedKind = FoodOptionKind(rawValue: kindRaw) {
                kind = estimatedKind
            }
            portionDescription = estimate.portionDescription
            totalCalories = String(format: "%.0f", estimate.totalCalories)
            proteinGrams = String(format: "%.1f", estimate.proteinGrams)
            carbsGrams = String(format: "%.1f", estimate.carbsGrams)
            fatGrams = String(format: "%.1f", estimate.fatGrams)
            confidence = min(max(estimate.confidence, 0), 1)
            recommendationScore = min(max(estimate.recommendationScore, 0), 100)
            recommendationReason = estimate.recommendationReason
            aiSummary = estimate.summary
            components = estimate.components
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard hasPhotoEvidence else {
            errorMessage = "新增选项卡必须上传食物照片或营养表照片"
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let photoFileName: String?
            if let firstImageData = imageDataList.first {
                photoFileName = try ImageStorage.saveMealPhoto(data: firstImageData)
            } else {
                photoFileName = option?.photoLocalPath
            }

            if let option {
                option.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                option.kind = kind
                option.photoLocalPath = photoFileName
                option.sourceDescription = sourceDescription
                option.portionDescription = portionDescription
                option.components = components
                option.totalCalories = totalCalories.doubleValue ?? 0
                option.proteinGrams = proteinGrams.doubleValue ?? 0
                option.carbsGrams = carbsGrams.doubleValue ?? 0
                option.fatGrams = fatGrams.doubleValue ?? 0
                option.confidence = confidence
                option.recommendationScore = min(max(recommendationScore, 0), 100)
                option.recommendationReason = recommendationReason
                option.aiSummary = aiSummary
                option.updatedAt = .now
            } else {
                modelContext.insert(FoodOption(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    photoLocalPath: photoFileName,
                    sourceDescription: sourceDescription,
                    portionDescription: portionDescription,
                    components: components,
                    totalCalories: totalCalories.doubleValue ?? 0,
                    proteinGrams: proteinGrams.doubleValue ?? 0,
                    carbsGrams: carbsGrams.doubleValue ?? 0,
                    fatGrams: fatGrams.doubleValue ?? 0,
                    confidence: confidence,
                    recommendationScore: min(max(recommendationScore, 0), 100),
                    recommendationReason: recommendationReason,
                    aiSummary: aiSummary
                ))
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "保存选项卡失败：\(error.localizedDescription)"
        }
    }

    private func syncTotalsFromComponents() {
        let calories = components.reduce(0) { $0 + $1.calories }
        let protein = components.reduce(0) { $0 + $1.proteinGrams }
        let carbs = components.reduce(0) { $0 + $1.carbsGrams }
        let fat = components.reduce(0) { $0 + $1.fatGrams }
        totalCalories = String(format: "%.0f", calories)
        proteinGrams = String(format: "%.1f", protein)
        carbsGrams = String(format: "%.1f", carbs)
        fatGrams = String(format: "%.1f", fat)
    }

    private func macroRatio(protein: Double, carbs: Double, fat: Double) -> (protein: Double, carbs: Double, fat: Double) {
        let total = protein * 4 + carbs * 4 + fat * 9
        guard total > 0 else { return (0, 0, 0) }
        return (protein * 4 / total, carbs * 4 / total, fat * 9 / total)
    }

    private static func numberText(_ value: Double?, decimals: Int) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%.\(decimals)f", value)
    }
}

private struct FoodOptionImageStrip: View {
    @Binding var imageDataList: [Data]

    var body: some View {
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
    }
}

private struct FoodOptionExistingPhoto: View {
    var path: String

    var body: some View {
        if let url = ImageStorage.mealPhotoURL(fileName: path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct FoodOptionComponentEditor: View {
    @Binding var component: FoodOptionComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("食物名称", text: $component.name)
                .font(.headline)
            TextField("大概分量，例如 100g / 1 个", text: $component.portionDescription)
            HStack {
                TextField("热量", value: $component.calories, format: .number)
                    .keyboardType(.decimalPad)
                Text("kcal")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("蛋白", value: $component.proteinGrams, format: .number)
                    .keyboardType(.decimalPad)
                TextField("碳水", value: $component.carbsGrams, format: .number)
                    .keyboardType(.decimalPad)
                TextField("脂肪", value: $component.fatGrams, format: .number)
                    .keyboardType(.decimalPad)
            }
            TextField("备注", text: $component.note)
        }
        .padding(.vertical, 4)
    }
}

struct FoodOptionCard: View {
    let option: FoodOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                FoodOptionThumbnail(path: option.photoLocalPath, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(option.kind.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(option.portionDescription.isEmpty ? "未填写份量" : option.portionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Text(option.totalCalories.kcalText)
                            .font(.subheadline.weight(.semibold))
                        Label("\(Int(option.recommendationScore.rounded()))", systemImage: "hand.thumbsup")
                            .font(.caption)
                            .foregroundStyle(scoreColor(option.recommendationScore))
                    }
                    HStack(spacing: 12) {
                        MacroLabel(name: "蛋白", grams: option.proteinGrams, color: .macroProtein)
                        MacroLabel(name: "碳水", grams: option.carbsGrams, color: .macroCarbs)
                        MacroLabel(name: "脂肪", grams: option.fatGrams, color: .macroFat)
                    }
                }
            }
            MacroRatioBar(
                proteinRatio: option.proteinEnergyRatio,
                carbsRatio: option.carbsEnergyRatio,
                fatRatio: option.fatEnergyRatio
            )
            if !option.recommendationReason.isEmpty {
                Text(option.recommendationReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
}

struct FoodOptionThumbnail: View {
    var path: String?
    var size: CGFloat = 56

    var body: some View {
        if let path,
           let url = ImageStorage.mealPhotoURL(fileName: path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "fork.knife.circle")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct MacroRatioBar: View {
    var proteinRatio: Double
    var carbsRatio: Double
    var fatRatio: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.macroProtein)
                    .frame(width: max(0, geo.size.width * proteinRatio))
                Rectangle()
                    .fill(Color.macroCarbs)
                    .frame(width: max(0, geo.size.width * carbsRatio))
                Rectangle()
                    .fill(Color.macroFat)
                    .frame(width: max(0, geo.size.width * fatRatio))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.15))
        }
    }
}

struct FoodOptionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let foodOptions: [FoodOption]
    @Binding var selectedIDs: Set<UUID>

    @State private var filter: FoodOptionFilter = .all

    private var filteredOptions: [FoodOption] {
        switch filter {
        case .all:
            foodOptions
        case .single:
            foodOptions.filter { $0.kind == .single }
        case .combo:
            foodOptions.filter { $0.kind == .combo }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if foodOptions.isEmpty {
                    ContentUnavailableView {
                        Label("还没有食物选项卡", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("先到「食物」Tab 新增常吃单品或套餐。")
                    }
                } else {
                    Section {
                        Picker("筛选", selection: $filter) {
                            ForEach(FoodOptionFilter.allCases) { optionFilter in
                                Text(optionFilter.title).tag(optionFilter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        ForEach(filteredOptions) { option in
                            FoodOptionSelectionRow(
                                option: option,
                                isSelected: selectedIDs.contains(option.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggle(option)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ option: FoodOption) {
        if selectedIDs.contains(option.id) {
            selectedIDs.remove(option.id)
        } else {
            selectedIDs.insert(option.id)
        }
    }
}

private struct FoodOptionSelectionRow: View {
    let option: FoodOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            FoodOptionThumbnail(path: option.photoLocalPath, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(option.name)
                        .font(.headline)
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
}
