import SwiftData
import SwiftUI

/// 数据 Tab：以「当日饮食 / 每餐宏量」为主屏（复用 `DietCalorieDetailView`，硬性保留每日/每餐
/// 碳水·蛋白·脂肪展示），顶部工具栏可进入体重趋势分析与训练计划。整个 Tab 共用一个 NavigationStack。
///
/// 取代旧的 今日 / 食物 / 运动 / 趋势 四个独立 Tab：聊天负责录入，这里只做只读呈现 + 少量手动兜底。
struct DataHubView: View {
    var body: some View {
        NavigationStack {
            DietCalorieDetailView()
        }
    }
}
