import SwiftUI
import UIKit

/// 「更多 → 调试日志」：集中查看 App 运行时收集的报错，便于排查问题。
struct DebugLogView: View {
    @ObservedObject private var store = AppLogStore.shared
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(store.entries.reversed()) { entry in
                                row(entry)
                            }
                        } header: {
                            Text("共 \(store.entries.count) 条 · 最新在最上面")
                        } footer: {
                            Text("这里汇总 App 运行时的报错（AI 调用、网络、数据保存等）。长按某条可单独复制，右上角可复制全部或清空。")
                        }
                    }
                }
            }
            .navigationTitle("调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = store.exportText
                            copied = true
                        } label: {
                            Label("复制全部", systemImage: "doc.on.doc")
                        }
                        .disabled(store.entries.isEmpty)

                        Button(role: .destructive) {
                            store.clear()
                        } label: {
                            Label("清空日志", systemImage: "trash")
                        }
                        .disabled(store.entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if copied {
                    Text("已复制全部日志")
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "ladybug")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无报错记录")
                .font(.headline)
            Text("App 运行时若出现报错（例如 AI 返回异常、网络失败、保存出错），会自动记录到这里。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func row(_ entry: AppLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.level.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color(for: entry.level))
                    .clipShape(Capsule())
                Text(entry.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppLogStore.timeFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.message)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.message
            } label: {
                Label("复制这条", systemImage: "doc.on.doc")
            }
        }
    }

    private func color(for level: AppLogLevel) -> Color {
        switch level {
        case .error: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}
