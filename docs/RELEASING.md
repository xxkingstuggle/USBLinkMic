# 发布流程

GitHub Release 是用户下载入口，必须与源码中的 Android `versionName`、`versionCode` 和 macOS `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 一致。

## 发布前

1. 把 `CHANGELOG.md` 的目标变化移到带日期的版本标题下。
2. 确认 `main` 的 CI 全部通过。
3. 在真机验证三条数据流，以及停止后 VPN、relay、ADB reverse 和网络服务均被清理。
4. 检查 App 图标、深色冷启动、麦克风权限和 VPN 首次授权。

## 构建 Android 测试包

```sh
cd android
./gradlew --no-daemon clean testDebugUnitTest lintDebug assembleDebug
```

当前公开 APK 是 debug 测试构建。正式发布 release APK/AAB 前，应在仓库外配置 keystore，并启用混淆、签名验证和升级安装测试。

## 构建 macOS 测试包

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath /tmp/USBLinkMicReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

正式面向普通用户发布前，应使用 Developer ID Application 签名并完成 Apple notarization。没有 Developer ID 时只能明确标注为未公证测试构建，不能暗示 Gatekeeper 会自动信任。

## 产物检查

```sh
file "USB LinkMic.app/Contents/MacOS/USB LinkMic"
codesign --verify --deep --strict "USB LinkMic.app"
aapt dump badging USBLinkMic-android-debug.apk | head
shasum -a 256 USBLinkMic-macOS.zip USBLinkMic-android-debug.apk
```

Release notes 至少包含功能变化、已知限制、系统要求、安装方式和 SHA-256。创建 tag 后再次确认 tag commit 与 `main` 预期提交一致。
