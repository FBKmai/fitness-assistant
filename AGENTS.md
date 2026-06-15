# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## 项目概览

「健身助手」是一个面向 iOS 17+ 的 SwiftUI 应用，用来记录每日饮食和运动、同步 Apple 健康数据、调用 OpenAI 兼容接口估算热量并生成次日减脂建议。所有用户数据通过 SwiftData 保存在设备本地，API Key 存在 Keychain。

工程文件是在 **Windows 工作区**生成的，本机无法执行 `xcodebuild`。真正的编译、签名、安装必须在 macOS/Xcode 环境，或通过仓库自带的 GitHub Actions 云端打包完成。

## 构建与测试

本地（macOS / Xcode 15+）：

- 打开工程：用 Xcode 打开 `FitnessAssistant.xcodeproj`（scheme 名为 `FitnessAssistant`）。HealthKit 需要真机，模拟器无法读取健康数据。
- 命令行构建：`xcodebuild -project FitnessAssistant.xcodeproj -scheme FitnessAssistant -configuration Release -destination 'generic/platform=iOS' build`
- 运行全部单元测试：`xcodebuild test -project FitnessAssistant.xcodeproj -scheme FitnessAssistant -destination 'platform=iOS Simulator,name=iPhone 15'`
- 运行单个测试：在上面命令后追加 `-only-testing:FitnessAssistantTests/CalorieCalculatorTests/testHealthKitRestingEnergyWinsOverBMR`

测试 target 为 `FitnessAssistantTests`（已在 scheme 的 TestAction 中挂好），只覆盖纯逻辑层：`CalorieCalculator`、`AIResponseParser`、`CSVExporter`。Views / Services 中依赖系统框架（HealthKit、Keychain、URLSession）的部分没有单测，新增逻辑时优先把可测试逻辑抽到这三类纯函数/枚举里。

Windows 云端打包（无 mac 时）：推送到 GitHub 后在 Actions 里手动触发 `Build iOS IPA`，`signing_mode=unsigned` 产出未签名 IPA（artifact `fitness-assistant-ipa-unsigned`）供轻松签等工具重签；配置好证书 secrets 后用 `signed` 直接产出已签名 IPA。详见 `CLOUD_BUILD_WINDOWS.md` 与 `.github/workflows/ios-ipa.yml`。

关键工程约束：`IPHONEOS_DEPLOYMENT_TARGET = 17.0`，`SWIFT_VERSION = 5.0`，默认 Bundle ID `com.local.FitnessAssistant`，`DEVELOPMENT_TEAM` 留空（本地需自行在 Signing & Capabilities 选 Team，且必须启用 HealthKit capability）。`.gitattributes` 强制 `*.swift`/`*.pbxproj` 等用 LF 换行——在 Windows 上编辑时注意不要引入 CRLF。

## 架构

分层为 `App / Models / Services / Views`（均在 `FitnessAssistant/` 下）。

**数据层（SwiftData）**：五个 `@Model` 实体在 `FitnessAssistantApp.swift` 的 `Schema` 中注册——`UserProfile`、`MealEntry`、`ExerciseEntry`、`DailySummary`、`AISettings`。修改任何 `@Model` 的存储属性都会改变 schema，需考虑迁移影响。

注意一个贯穿全局的模式：**复杂值类型不直接存为 SwiftData 属性，而是序列化成 JSON 字符串列存储**，再用计算属性透明编解码。例如 `MealEntry.estimatedItemsJSON` ↔ `estimatedItems: [MealFoodItem]`，`DailySummary.snapshotJSON` ↔ `snapshot: DailySnapshot?`。新增结构化字段时沿用这个约定，不要直接把数组/嵌套对象塞进 `@Model`。

**导航**：`RootView` 根据「是否已有 `UserProfile` 且有 `AISettings`」决定显示 `OnboardingView` 还是 `MainTabView`（今日 / 饮食 / 运动 / 总结 / 设置 五个 Tab，分别对应 `Views/` 下同名文件）。

**`TodayView` 是核心编排器**，把各服务串起来：请求 HealthKit 授权 → `fetchSnapshot` 拉当日数据 → `upsertHealthEntries` 把健康数据按 `healthKitWorkoutID` 去重 upsert 成 `ExerciseEntry`（每日活动合计用固定 ID `daily-<dayKey>`，单次训练用 workout UUID）→ `CalorieCalculator.compute` 算热量差 → `AIClient.generateDailyAdvice` 生成建议 → upsert 成当日唯一的 `DailySummary`。读写 SwiftData 用的是 View 里的 `@Query` + `modelContext`，没有独立的 Repository 层。

**AI 调用（`Services/AIClient.swift`）**：对接任意 OpenAI 兼容的 `/chat/completions` 接口（Base URL、模型名、vision 模型名都来自 `AISettings`，可在设置页改）。两个入口：`estimateMeal`（文字或图片估算单餐，图片走 base64 data URL + vision 模型）和 `generateDailyAdvice`（基于 `DailySnapshot` 生成次日建议）。两者都强约束模型「只返回 JSON」，再交给 `AIResponseParser.decodeJSONObject` 解析——`AIResponseParser` 会容错地从可能夹带 markdown 的文本中截取第一个 `{` 到最后一个 `}`。所有 AI 错误以中文 `LocalizedError` 抛出。

**容错设计要保留**：`TodayView.buildSummary` 在 AI 调用失败时会用本地 `fallbackAdvice` 兜底而不是中断流程；`CalorieCalculator` 在缺少 HealthKit 静息能量时回退到基于 `UserProfile` 的 Mifflin-St Jeor BMR 公式。改这两处时不要去掉降级路径。

**其他服务**：`KeychainStore`（单例，service=`FitnessAssistant.AI`，存 API Key）、`HealthKitService`（`@MainActor`，只读步数/活动能量/基础能量/体重/训练，用 continuation 包装 HK 回调）、`NotificationScheduler`（每晚本地提醒）、`ImageStorage`（餐食照片落本地，`MealEntry` 只存 `photoLocalPath`）、`CSVExporter`（导出三张表，写文件时加 UTF-8 BOM `\u{FEFF}` 以便 Excel/WPS 正确识别中文）。

## 约定

- UI 文案、AI prompt、错误信息、CSV 表头全部用中文。
- 涉及金额/热量展示用 `Double` 上的 `kcalText` / `signedKcalText` 扩展（定义在 `TodayView.swift` 末尾）。
