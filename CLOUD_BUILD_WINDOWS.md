# Windows 上用 GitHub Actions 打包 iOS IPA

这个项目已经带有 `.github/workflows/ios-ipa.yml`。你把代码推到 GitHub 后，可以在网页上手动触发云端 macOS runner 打包。

## 最简单路线：生成未签名 IPA，再用轻松签重签

1. 在 GitHub 新建仓库并上传本项目。
2. 打开仓库页面，进入 `Actions`。
3. 选择 `Build iOS IPA`。
4. 点击 `Run workflow`。
5. `signing_mode` 选择 `unsigned`。
6. 构建完成后，在 workflow run 页面下载 artifact：`fitness-assistant-ipa-unsigned`。
7. 解压得到 `FitnessAssistant-unsigned.ipa`。
8. 在 Windows 或 iPhone 上用轻松签/Auto install/Sideloadly 对这个 IPA 重签并安装。

如果要使用 HealthKit，你重签时使用的证书和描述文件必须包含 HealthKit 权限。

## 云端直接生成已签名 IPA

如果你有 Apple Developer 证书和描述文件，可以让 GitHub Actions 直接签名。

### GitHub Secrets

进入仓库 `Settings` -> `Secrets and variables` -> `Actions` -> `Secrets`，添加：

- `BUILD_CERTIFICATE_BASE64`: `.p12` 证书的 Base64 内容。
- `P12_PASSWORD`: 导出 `.p12` 时设置的密码。
- `BUILD_PROVISION_PROFILE_BASE64`: `.mobileprovision` 描述文件的 Base64 内容。
- `KEYCHAIN_PASSWORD`: 随便设置一个临时 keychain 密码，例如一串随机字符。
- `DEVELOPMENT_TEAM`: Apple Developer Team ID。

进入 `Variables`，添加：

- `BUNDLE_IDENTIFIER`: 你的 App Bundle ID，例如 `com.yourname.fitnessassistant`。

### 在 Windows 生成 Base64

PowerShell 示例：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\certificate.p12")) | Set-Content -NoNewline certificate.p12.base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\profile.mobileprovision")) | Set-Content -NoNewline profile.mobileprovision.base64
```

把两个 `.base64` 文件内容分别填到 GitHub Secrets。

### 触发签名构建

1. 进入 `Actions` -> `Build iOS IPA`。
2. 点击 `Run workflow`。
3. `signing_mode` 选择 `signed`。
4. `export_method`：
   - `development`: 开发证书/开发描述文件。
   - `ad-hoc`: Ad Hoc 证书/描述文件。
5. 构建完成后下载 artifact：`fitness-assistant-ipa-signed`。

## 安装到 iPhone

- 未签名 IPA：先用轻松签/Auto install 重签，再安装。
- 已签名 IPA：可以直接用 Sideloadly、爱思助手、Apple Configurator、Diawi/蒲公英内测分发等方式安装。

首次打开如果提示不信任开发者，在 iPhone 上进入 `设置` -> `通用` -> `VPN与设备管理`，信任对应开发者证书。
