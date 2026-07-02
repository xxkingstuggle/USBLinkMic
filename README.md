# USB LinkMic

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)](#)
[![Version](https://img.shields.io/badge/version-3.0.0-orange)](CHANGELOG.md)

USB LinkMic turns an Android phone into a wired or wireless microphone source for a Mac.

中文说明见下方。

## Highlights

- **USB / ADB mode**: connect the phone with a USB cable, let the Mac app start the Android microphone service, and stream audio through `adb reverse`.
- **Wi-Fi TCP mode**: connect both devices to the same LAN and stream audio by entering the Mac endpoint in the Android app.
- **Selectable Mac output**: route the phone microphone to the system default output, speakers, USB/Type-C devices, or virtual audio devices such as BlackHole.
- **Live waveform**: preview incoming audio activity in the Mac app.
- **Native clients**: SwiftUI on macOS and Jetpack Compose on Android.

## Downloads

Prebuilt packages are published from GitHub Releases:

- `USBLinkMic-macOS.zip`: macOS app bundle. Unzip it and move `USB LinkMic.app` to `/Applications`.
- `USBLinkMic-android-debug.apk`: Android debug APK for testing. Install with `adb install USBLinkMic-android-debug.apk`.

The Android debug APK is intended for testing. If you need a production-signed APK, build locally with your own signing key.

## Quick Start

### ADB Mode

1. Enable USB debugging on the Android phone.
2. Connect the phone to the Mac with a USB cable and approve the ADB prompt.
3. Open `USB LinkMic.app` on the Mac.
4. Choose **ADB** mode and start the phone microphone.
5. Select the desired Mac audio output device in settings.

### Wi-Fi TCP Mode

1. Put the Mac and the phone on the same Wi-Fi/LAN.
2. Start the phone microphone receiver in the Mac app using **Wi-Fi TCP** mode.
3. Copy the displayed Mac endpoint, for example `192.168.1.8:54345`.
4. Enter the endpoint in the Android app and start streaming.

## Build from Source

### macOS

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build/DerivedData \
  clean build
```

The app bundle is generated at:

```text
mac-native/build/DerivedData/Build/Products/Release/USB LinkMic.app
```

### Android

```sh
cd android
./gradlew :app:assembleDebug
```

The debug APK is generated at:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

Release signing is intentionally local-only. Put your keystore at `android/app/key.jks` and provide `KEY_ALIAS`, `KEY_PASSWORD`, and `STORE_PASSWORD` when building a release APK.

## Repository Layout

```text
.
├── android/          Android app, Jetpack Compose, microphone capture service
├── mac-native/       macOS app, SwiftUI, CoreAudio playback
├── Assets/           Icons and project assets
├── .github/          Issue templates and CI
└── outputs/          Local build artifacts, ignored by Git
```

## Notes

- ADB mode requires Android USB debugging authorization.
- Android requires microphone permission.
- Wi-Fi mode requires both devices to be reachable on the same network.
- To use the phone audio as a meeting-app microphone, route USB LinkMic to a virtual device such as BlackHole, then select that virtual device as the input in the meeting app.

## Upstream Credit

The Android side was originally derived from [AndroidMic](https://github.com/teamclouday/AndroidMic). Related upstream license notices are preserved where applicable.

## License

USB LinkMic is released under the [MIT License](LICENSE).

---

# USB LinkMic 中文说明

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Android-blue)](#)
[![Version](https://img.shields.io/badge/version-3.0.0-orange)](CHANGELOG.md)

USB LinkMic 可以把 Android 手机变成 Mac 的有线或无线麦克风音源。

## 功能亮点

- **USB / ADB 模式**：手机通过 USB 数据线连接 Mac，Mac 端自动启动 Android 麦克风服务，并通过 `adb reverse` 传输音频。
- **Wi-Fi TCP 模式**：手机和 Mac 在同一局域网内，通过 Mac 端点地址传输音频。
- **可选择 Mac 输出设备**：支持系统默认输出、内置扬声器、USB/Type-C 设备，以及 BlackHole 等虚拟声卡。
- **实时波形**：Mac 端显示手机麦克风输入活动。
- **原生客户端**：macOS 使用 SwiftUI，Android 使用 Jetpack Compose。

## 下载

预编译包会发布在 GitHub Releases：

- `USBLinkMic-macOS.zip`：macOS 应用。解压后将 `USB LinkMic.app` 移动到 `/Applications`。
- `USBLinkMic-android-debug.apk`：Android 测试 APK。可使用 `adb install USBLinkMic-android-debug.apk` 安装。

Android debug APK 主要用于测试。如果需要生产签名版本，请使用自己的签名密钥本地构建。

## 快速开始

### ADB 模式

1. 在 Android 手机上开启 USB 调试。
2. 用 USB 数据线连接手机和 Mac，并允许 ADB 授权。
3. 打开 Mac 端 `USB LinkMic.app`。
4. 选择 **ADB** 模式并启动手机麦克风。
5. 在设置里选择需要的 Mac 音频输出设备。

### Wi-Fi TCP 模式

1. 确保 Mac 和手机处于同一 Wi-Fi/局域网。
2. 在 Mac 端选择 **Wi-Fi TCP** 模式并启动接收端。
3. 复制 Mac 端显示的端点，例如 `192.168.1.8:54345`。
4. 在 Android 端输入该端点并开始推流。

## 从源码构建

### macOS

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Release \
  -derivedDataPath mac-native/build/DerivedData \
  clean build
```

构建产物位于：

```text
mac-native/build/DerivedData/Build/Products/Release/USB LinkMic.app
```

### Android

```sh
cd android
./gradlew :app:assembleDebug
```

debug APK 位于：

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

Release 签名只在本地进行。请将 keystore 放到 `android/app/key.jks`，并设置 `KEY_ALIAS`、`KEY_PASSWORD`、`STORE_PASSWORD` 后再构建 release APK。

## 项目结构

```text
.
├── android/          Android 应用，Jetpack Compose，麦克风采集服务
├── mac-native/       macOS 应用，SwiftUI，CoreAudio 播放
├── Assets/           图标和项目素材
├── .github/          Issue 模板和 CI
└── outputs/          本地构建产物，不提交到 Git
```

## 使用注意

- ADB 模式需要 Android USB 调试授权。
- Android 端需要麦克风权限。
- Wi-Fi 模式要求手机和 Mac 在同一可互通网络内。
- 如果要让会议软件把手机音频当作麦克风输入，可以将 USB LinkMic 输出到 BlackHole 等虚拟声卡，再在会议软件中选择该虚拟声卡作为输入。

## 上游致谢

Android 部分最初基于 [AndroidMic](https://github.com/teamclouday/AndroidMic) 改造，相关上游协议声明会按需保留。

## 开源协议

USB LinkMic 使用 [MIT License](LICENSE) 开源。
