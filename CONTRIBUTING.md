# Contributing to USB LinkMic

感谢你对 USB LinkMic 的兴趣！

## 如何贡献

1. Fork 本仓库。
2. 基于 `main` 分支创建你的功能分支：`git checkout -b feature/your-feature`。
3. 提交改动：`git commit -m "feat: describe your change"`。
4. 推送到你的 Fork：`git push origin feature/your-feature`。
5. 提交 Pull Request。

## 提交信息规范

- `feat:` 新功能
- `fix:` 修复 bug
- `perf:` 性能优化
- `refactor:` 重构
- `docs:` 文档
- `cleanup:` 清理或删除

## 构建与测试

### macOS

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### Android

```sh
cd android
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
./gradlew :app:assembleDebug
```

## 行为准则

保持友善、尊重他人，专注于改进项目本身。

---

# Contributing to USB LinkMic

Thank you for your interest in USB LinkMic!

## How to Contribute

1. Fork this repository.
2. Create a feature branch from `main`: `git checkout -b feature/your-feature`.
3. Commit your changes: `git commit -m "feat: describe your change"`.
4. Push to your fork: `git push origin feature/your-feature`.
5. Open a Pull Request.

## Commit Message Convention

- `feat:` new feature
- `fix:` bug fix
- `perf:` performance improvement
- `refactor:` code refactoring
- `docs:` documentation
- `cleanup:` removal or cleanup

## Build and Test

### macOS

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### Android

```sh
cd android
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
./gradlew :app:assembleDebug
```

## Code of Conduct

Be friendly, respectful, and focus on improving the project.
