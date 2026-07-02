# Contributing to USB LinkMic

Thank you for helping improve USB LinkMic.

## Workflow

1. Fork the repository.
2. Create a branch from `main`.
3. Keep changes focused and include a short explanation in the commit message.
4. Build the affected app before opening a pull request.
5. Open a pull request with screenshots or logs when UI/audio behavior changes.

## Commit Style

- `feat:` new user-facing behavior
- `fix:` bug fix
- `perf:` performance improvement
- `refactor:` internal code change
- `docs:` documentation-only change
- `chore:` maintenance

## Local Checks

macOS:

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build/DerivedData \
  clean build
```

Android:

```sh
cd android
./gradlew :app:assembleDebug
```

## Code of Conduct

Be kind, practical, and specific. Audio and device-routing bugs are often hardware-dependent, so include device names, OS versions, connection mode, and logs whenever possible.

---

# 贡献指南

感谢你帮助改进 USB LinkMic。

## 工作流程

1. Fork 本仓库。
2. 从 `main` 创建分支。
3. 保持改动聚焦，并在提交信息中简要说明。
4. 提交 PR 前构建受影响的应用。
5. 如果改动涉及 UI 或音频行为，请在 PR 中附上截图或日志。

## 提交信息

- `feat:` 新功能
- `fix:` bug 修复
- `perf:` 性能优化
- `refactor:` 内部重构
- `docs:` 文档改动
- `chore:` 维护事项

## 本地检查

macOS：

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build/DerivedData \
  clean build
```

Android：

```sh
cd android
./gradlew :app:assembleDebug
```

## 行为准则

保持友善、务实、具体。音频和设备路由问题常常和硬件环境有关，反馈时请尽量附上设备名、系统版本、连接模式和日志。
