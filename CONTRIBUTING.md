# 贡献指南 / Contributing

感谢你改进 USB LinkMic。这个项目同时涉及 Android 前台服务、录音、VPN、ADB、macOS 网络配置和实时音频，因此“小改动”也可能影响另一端。提交前请尽量说明数据流和失败恢复行为。

## 开始之前

1. Bug 请先搜索现有 Issue；安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。
2. 较大的功能或协议变化建议先创建 Feature Request，明确用户问题、兼容范围和回退方案。
3. 不要提交 keystore、证书、Provisioning Profile、设备序列号、IP 地址或包含个人信息的日志。

## 本地环境

- macOS 26+ 与 Xcode（macOS 客户端）。
- JDK 21、Android SDK 36 与 Android Platform Tools（Android 客户端）。
- Rust stable（仅修改 `third_party/gnirehtet/relay-rust` 或 relay 构建流程时需要）。

## 验证命令

Android：

```sh
cd android
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug
```

macOS：

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Debug \
  -derivedDataPath /tmp/USBLinkMicDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

gnirehtet relay：

```sh
cargo test \
  --manifest-path third_party/gnirehtet/relay-rust/Cargo.toml \
  --locked
```

## Pull Request 要求

- 一个 PR 聚焦一个明确问题，避免混入无关格式化或本地文件。
- 用户可见变化同步更新 README、Troubleshooting 或 Changelog。
- 涉及 UI 时附浅色/深色截图；涉及网络或音频时说明真机型号、系统版本和验证路径。
- 新的后台任务必须定义停止、断线、应用退出和异常失败时的清理行为。
- 保持 Android 与 Mac 端协议、端口、Intent action 和状态命名一致。

## English summary

Keep each pull request focused, document user-visible behavior, and run the Android, macOS, and relay checks relevant to your change. Never commit signing material or unsanitized device logs. For cross-device changes, describe both the happy path and cleanup behavior after failures or disconnects.
