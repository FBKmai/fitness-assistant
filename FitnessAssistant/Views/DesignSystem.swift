import Charts
import SwiftUI
import UIKit

// MARK: - 尺寸与间距常量

/// 全局统一的尺寸常量，替换各视图里散落的魔法数字。
enum AppMetrics {
    static let cardCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let tileSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
}

// MARK: - 语义颜色

extension Color {
    /// 卡片背景：跟随系统分组背景，自动适配深色模式。
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    /// 热量缺口已达标（绿）。
    static let deficitReached = Color.green
    /// 热量缺口未达标（橙）。
    static let deficitShort = Color.orange
    /// 蛋白质标识色。
    static let macroProtein = Color.pink
    /// 碳水标识色。
    static let macroCarbs = Color.blue
    /// 脂肪标识色。
    static let macroFat = Color.orange
}

// MARK: - 指标卡片

/// 今日页等处使用的指标卡片：图标+标题，数值与单位分离排版，可高亮核心指标。
struct MetricTile: View {
    var title: String
    /// 仅数值部分（不含单位），如 "1200"、"+480"。
    var value: String
    var unit: String = "kcal"
    var systemImage: String
    /// 是否高亮（用于突出核心指标，如热量差）。
    var highlighted: Bool = false
    /// 强调色：传入后数值与高亮边框使用该色。
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(tint ?? .primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppMetrics.cardPadding)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
        .overlay(tileBorder)
    }

    @ViewBuilder
    private var tileBackground: some View {
        if highlighted, let tint {
            tint.opacity(0.12)
        } else {
            Color.cardBackground
        }
    }

    @ViewBuilder
    private var tileBorder: some View {
        if highlighted, let tint {
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
    }
}

// MARK: - 进度条

/// 展示「当前值 / 目标值」的进度条，带标题与百分比。
struct MetricProgressBar: View {
    var title: String
    var current: Double
    var target: Double
    var tint: Color = .green

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - 营养素标签

/// 统一的营养素小标签（蛋白/碳水/脂肪），带色点与间距。
struct MacroLabel: View {
    var name: String
    var grams: Double
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .foregroundStyle(.secondary)
            Text(grams.gramsText)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

// MARK: - 圆环进度

/// 圆环进度：底环 + 进度环，中心可放任意内容（如「还可吃 XXX」）。
struct ProgressRing<Content: View>: View {
    /// 0...1，超出会夹到 1。
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = .green
    var trackColor: Color = Color.secondary.opacity(0.18)
    @ViewBuilder var content: () -> Content

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: clamped)
            content()
                .padding(lineWidth + 6)
        }
    }
}

// MARK: - 体重目标仪表

/// 270° 弧形仪表，展示「起点 → 目标」的减重进度，中心显示已减重量。
struct WeightGoalGauge: View {
    var initialKg: Double
    var currentKg: Double
    var targetKg: Double
    var lineWidth: CGFloat = 12

    /// 弧线占整圆的比例（270° / 360°）。
    private let arcFraction = 0.75
    /// 起始旋转角，让底部留出缺口。
    private let rotation = 135.0

    private var progress: Double {
        let total = initialKg - targetKg
        guard total > 0 else { return 0 }
        return min(max((initialKg - currentKg) / total, 0), 1)
    }

    private var reached: Bool { targetKg > 0 && currentKg <= targetKg }
    private var tint: Color { reached ? .deficitReached : .deficitShort }
    private var reducedKg: Double { initialKg - currentKg }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(Color.secondary.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))
            Circle()
                .trim(from: 0, to: arcFraction * progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .animation(.easeOut, value: progress)
            VStack(spacing: 2) {
                Text(String(format: "%.1f", reducedKg))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(reducedKg >= 0 ? tint : .secondary)
                Text("已减(公斤)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 营养目标进度行

/// 一行营养素：名称 + 当前/目标克 + 细进度条。
struct MacroProgressRow: View {
    var name: String
    var current: Double
    var target: Double
    var color: Color

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(current.rounded())) / \(Int(target.rounded())) 克")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(color).frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - 迷你体重折线图

/// 小尺寸体重折线图，隐藏坐标轴，用于「体重记录」卡片。
struct MiniWeightChart: View {
    /// 时间正序的 (日期, 体重kg) 点。
    var points: [WeightPoint]
    var tint: Color = .green

    /// 折线图数据点（Identifiable，便于 Charts ForEach）。
    struct WeightPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var kg: Double
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
            AreaMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint.opacity(0.12))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.kg)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = max((hi - lo) * 0.2, 0.1)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - 通用卡片样式

extension View {
    /// 统一卡片样式：内边距 + 背景 + 圆角。
    func cardStyle() -> some View {
        self
            .padding(AppMetrics.cardPadding)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }

    /// 全局键盘控制：给数字键盘等没有 Return 键的输入方式补一个「完成」按钮。
    func keyboardDismissControls() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.dismissKeyboard()
                    }
                }
            }
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - 数值格式化

extension Double {
    /// 含单位，如 "1200 kcal"。
    var kcalText: String { "\(Int(rounded())) kcal" }
    /// 带符号且含单位，如 "+480 kcal" / "-120 kcal"。
    var signedKcalText: String {
        let value = Int(rounded())
        return value >= 0 ? "+\(value) kcal" : "\(value) kcal"
    }
    /// 仅数值（不含单位），供 MetricTile 数值/单位分离展示。
    var kcalValue: String { "\(Int(rounded()))" }
    /// 带符号的纯数值，如 "+480" / "-120"。
    var signedKcalValue: String {
        let value = Int(rounded())
        return value >= 0 ? "+\(value)" : "\(value)"
    }
    /// 克，如 "12g"。
    var gramsText: String { "\(Int(rounded()))g" }
}
