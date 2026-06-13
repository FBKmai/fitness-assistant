# 健身助手

一个面向个人自签安装的 iOS 17+ SwiftUI 应用，用来记录每日饮食和运动、同步 Apple 健康数据、调用 OpenAI 兼容接口估算热量并生成次日建议。

## 功能

- SwiftUI + SwiftData 本地存储，数据保存在手机本地。
- HealthKit 读取步数、活动能量、基础能量、训练记录和体重。
- 饮食支持文字、拍照、相册图片，AI 估算后可编辑确认再入库。
- 每晚本地通知提醒；打开 App 后可同步健康数据并生成当日总结。
- CSV 导出 `meals.csv`、`exercise.csv`、`daily_summaries.csv`，使用 UTF-8 BOM 方便 Excel/WPS 打开中文。
- API Key 通过 Keychain 存储，默认接入 DeepSeek（`https://api.deepseek.com`，模型 `deepseek-v4-flash`），设置页也支持任意 OpenAI 兼容 Base URL 和模型名。
- DeepSeek 官方接口目前仅支持文字输入；拍照或多图识别需把设置页的「视觉模型」指向支持图片的 OpenAI 兼容服务。

## 打开方式

1. 在 macOS 上用 Xcode 15 或更新版本打开 `FitnessAssistant.xcodeproj`。
2. 在 Signing & Capabilities 中选择你的个人 Apple Developer Team。
3. 确认 HealthKit capability 已启用。
4. 连接 iPhone，选择真机运行。
5. 通过设置页填写 API Key、Base URL 和模型名（默认 DeepSeek），可用「测试 AI 模型」按钮验证连通性。

本仓库当前是在 Windows 工作区生成的工程文件，无法在这里执行 `xcodebuild`。实际编译、签名、安装需要在 macOS/Xcode 环境中完成。

## Windows 云端打包

Windows 用户可以把项目推到 GitHub，然后使用 GitHub Actions 的 macOS runner 打包 IPA。详细步骤见 `CLOUD_BUILD_WINDOWS.md`。
