import SwiftUI

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

// MARK: - 通用卡片样式

extension View {
    /// 统一卡片样式：内边距 + 背景 + 圆角。
    func cardStyle() -> some View {
        self
            .padding(AppMetrics.cardPadding)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
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
