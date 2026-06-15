import SwiftUI

struct FoodHubView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MealsView()
                    } label: {
                        Label("饮食记录", systemImage: "fork.knife")
                    }
                    NavigationLink {
                        FoodOptionsView()
                    } label: {
                        Label("常吃食物选项", systemImage: "rectangle.stack")
                    }
                } footer: {
                    Text("饮食记录用于每日摄入统计；常吃食物选项会进入 AI 教练上下文，方便饭前点单和份量判断。")
                }
            }
            .navigationTitle("食物")
        }
    }
}
