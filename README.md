# USB LinkMic

让 Android 手机成为 Mac 的无线/有线麦克风。

> English version below.

## 功能

USB LinkMic 是一套 macOS + Android 工具，把手机变成 Mac 的麦克风输入源：

- **ADB 模式（推荐）**：手机通过 USB 数据线连接 Mac，Mac 端一键启动 Android 服务，音频通过 USB 通道传输。
- **Wi-Fi TCP 模式**：手机和 Mac 连接同一局域网，Android 端手动输入 Mac IP 和端口，即可通过 Wi-Fi 传输音频。
- **真实音频输出**：Mac 端将手机音频直接播放到指定扬声器，并显示实时波形。
- **零依赖解析**：Mac 端手写 Protobuf 解析，无需额外依赖。

## 项目结构

```
.
├── android/          # Android 应用（Jetpack Compose）
├── mac-native/       # macOS 应用（SwiftUI + AVAudioEngine）
├── Assets/           # 截图、图标等素材
└── outputs/          # 构建产物（zip / apk，不提交到 Git）
```

## 快速开始

### 1. 下载安装

- **macOS**：解压 `outputs/USBLinkMic-macOS.zip` 或 GitHub Releases 中的 zip，将 `USB LinkMic.app` 拖入 `/Applications`。
- **Android**：通过 `adb install outputs/USBLinkMic-android.apk` 或 GitHub Releases 下载 apk 安装。

### 2. ADB 模式

1. 用 USB 数据线连接手机和 Mac，并开启手机开发者选项中的 **USB 调试**。
2. 打开 Mac 应用，切换到「手机麦克风」面板。
3. 选择 **ADB** 模式，点击开关启动。
4. Mac 端会自动通过 ADB 启动 Android 服务并反向映射端口，音频开始传输。

### 3. Wi-Fi TCP 模式

1. 确保 Mac 和手机连接同一 Wi-Fi。
2. Mac 应用切换到「手机麦克风」面板，选择 **Wi-Fi TCP** 模式，点击开关启动。
3. 在 Mac 应用设置或主面板中，查看当前默认网络接口的 **IP:端口**（例如 `192.168.1.5:54345`）。
4. 打开 Android 应用，进入设置页，选择 **Wi-Fi TCP**，填入 Mac 的 IP 和端口。
5. 返回 Android 主界面，打开麦克风开关开始连接。

> **注意**：Wi-Fi 模式下，采样率、声道、音频格式、音频源由 Android 端设置控制；ADB 模式下这些参数由 Mac 端控制并同步给 Android。

## 自行构建

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

发布签名需要本地放置 `android/app/key.jks` 并设置环境变量 `KEY_ALIAS`、`KEY_PASSWORD`、`STORE_PASSWORD`。请勿提交签名密钥。

## 运行注意事项

- ADB 模式需要手机授权 USB 调试。
- Android 麦克风模式需要授予麦克风权限。
- Wi-Fi 模式要求 Mac 和手机处于同一局域网，且没有被防火墙或路由器隔离。
- 若需要让手机麦克风在会议软件中显示为输入设备，可将 Mac 输出设备设为 BlackHole 等虚拟声卡，并在会议软件中选择该虚拟声卡。

## 开源协议

本项目采用 [MIT License](LICENSE)。

项目中的 Android 部分最初参考了 [AndroidMic](https://github.com/teamclouday/AndroidMic)，并保留了相关上游协议声明。

---

# USB LinkMic (English)

Turn your Android phone into a wired/wireless microphone for your Mac.

## Features

USB LinkMic is a macOS + Android tool that lets your phone act as a microphone input for your Mac:

- **ADB mode (recommended)**: Connect your phone to your Mac via USB, then start the Android service from the Mac app with one click. Audio is transmitted over the USB channel.
- **Wi-Fi TCP mode**: Connect both devices to the same local network, enter the Mac IP and port in the Android app, and stream audio over Wi-Fi.
- **Real audio output**: The Mac app plays incoming audio through the selected speaker and displays a live waveform.
- **Zero-dependency parsing**: The Mac app uses a hand-written Protobuf parser, with no extra dependencies.

## Project Structure

```
.
├── android/          # Android app (Jetpack Compose)
├── mac-native/       # macOS app (SwiftUI + AVAudioEngine)
├── Assets/           # Screenshots and icons
└── outputs/          # Build artifacts (zip / apk, not committed to Git)
```

## Quick Start

### 1. Download and Install

- **macOS**: Extract `outputs/USBLinkMic-macOS.zip` or the zip from GitHub Releases, then drag `USB LinkMic.app` into `/Applications`.
- **Android**: Install via `adb install outputs/USBLinkMic-android.apk` or download the apk from GitHub Releases.

### 2. ADB Mode

1. Connect your phone to your Mac via USB and enable **USB debugging** in Developer options.
2. Open the Mac app and switch to the **Phone Microphone** panel.
3. Select **ADB** mode and toggle the switch.
4. The Mac app will start the Android service via ADB and reverse the port automatically; audio streaming begins.

### 3. Wi-Fi TCP Mode

1. Make sure both your Mac and phone are on the same Wi-Fi network.
2. In the Mac app, switch to the **Phone Microphone** panel, select **Wi-Fi TCP**, and toggle the switch.
3. Check the displayed **IP:port** in the Mac app settings or main panel (e.g., `192.168.1.5:54345`).
4. Open the Android app, go to settings, select **Wi-Fi TCP**, and enter the Mac IP and port.
5. Return to the Android main screen and turn on the microphone switch to connect.

> **Note**: In Wi-Fi mode, sample rate, channel count, audio format, and audio source are controlled by the Android app. In ADB mode, these parameters are controlled by the Mac app and synced to Android.

## Build from Source

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

Release builds require a local `android/app/key.jks` and the environment variables `KEY_ALIAS`, `KEY_PASSWORD`, and `STORE_PASSWORD`. Do not commit signing keys.

## Runtime Notes

- ADB mode requires USB debugging authorization on the phone.
- Android microphone mode requires microphone permission.
- Wi-Fi mode requires both devices to be on the same LAN and not blocked by firewalls or router isolation.
- To make the phone microphone appear as an input device in meeting software, route Mac output to a virtual audio device such as BlackHole and select that device in your meeting app.

## License

This project is licensed under the [MIT License](LICENSE).

The Android portion was initially derived from [AndroidMic](https://github.com/teamclouday/AndroidMic); upstream license notices are preserved.
