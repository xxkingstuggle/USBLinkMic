# USB LinkMic

<p align="center">
  <a href="README.zh-CN.md"><b>中文</b></a>
  &nbsp;|&nbsp;
  <a href="README.en.md"><b>English</b></a>
</p>

USB LinkMic 是一个 macOS + Android 工具，用一根 USB 线或局域网把 Android 手机和 Mac 连接起来。它不是单纯的麦克风工具，而是包含三块能力：

- **手机麦克风给 Mac**：把 Android 手机麦克风音频传到 Mac，并从指定 Mac 输出设备播放。
- **手机网络给 Mac**：通过 USB CDC-NCM/RNDIS，把手机网络共享给 Mac。
- **Mac 网络给手机**：通过 ADB reverse + Android VPN，把 Mac 网络反向共享给手机。

## 功能

### 手机麦克风给 Mac

- ADB 模式：Mac 自动配置 `adb reverse` 并启动 Android 端麦克风服务。
- Wi-Fi TCP 模式：手机和 Mac 在同一局域网，Android 手动连接 Mac 的 IP 和端口。
- 支持采样率、声道、音频格式、音频源、静音和增益设置。
- Mac 端支持选择输出设备，例如系统默认输出、内置扬声器、TYPE-C/USB 声卡、BlackHole 等虚拟声卡。
- Mac 端显示实时波形和诊断日志。

### 手机网络给 Mac

- Mac 端通过 ADB 请求 Android 切换 USB function 到 `ncm`。
- 自动启用 Mac 侧手机网络服务，并检测 IP、网关、默认路由和 USB function 状态。
- 停止时会禁用 Mac 侧手机网络服务，并尽量恢复 Android 原来的 USB function。

这个功能依赖手机 ROM 是否允许 `svc usb setFunctions ncm`，不同 Android 设备兼容性会不同。

### Mac 网络给手机

- Mac 端建立 `adb reverse localabstract:usblinkmic_net tcp:31416`。
- Android 端启动 VPN Service，把指定路由和 DNS 走到 Mac relay。
- 默认 DNS 为 `8.8.8.8`，默认路由为 `0.0.0.0/0`，可在 Mac 设置里调整。

首次启动需要 Android 端授权 VPN。

## 下载

见 GitHub Releases：

- `USBLinkMic-macOS.zip`：macOS 应用，解压后把 `USB LinkMic.app` 放入 `/Applications`。
- `USBLinkMic-android-debug.apk`：Android 测试 APK，可用 `adb install USBLinkMic-android-debug.apk` 安装。

Android 包目前发布 debug 构建，正式签名包请使用自己的 keystore 本地构建。

## 使用

### 准备

1. Android 手机打开开发者选项和 USB 调试。
2. Mac 安装 Android platform-tools，并确保 `adb` 可用。
3. 首次连接手机时，在手机上允许 USB 调试授权。

### 手机麦克风给 Mac

ADB 模式：

1. USB 连接手机和 Mac。
2. 打开 Mac 端 USB LinkMic。
3. 在「手机麦克风」中选择 ADB 模式。
4. 选择需要的音频输出设备。
5. 打开开关。

Wi-Fi TCP 模式：

1. 手机和 Mac 连接同一局域网。
2. Mac 端启动 Wi-Fi TCP 接收。
3. 复制 Mac 端显示的 `IP:端口`。
4. Android 端设置为 Wi-Fi TCP，填入该地址并启动。

### 手机网络给 Mac

1. USB 连接手机和 Mac。
2. 保持手机解锁，避免系统阻止 USB function 切换。
3. 在 Mac 端打开「手机网络给 Mac」。
4. 等待 Mac 检测到 CDC-NCM/RNDIS 网络服务、IP 和网关。

### Mac 网络给手机

1. USB 连接手机和 Mac。
2. 在 Mac 端打开「Mac 网络给手机」。
3. Android 端弹出 VPN 授权时允许。
4. 需要时在 Mac 设置里调整 DNS 和路由。

## 构建

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
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME="$HOME/Library/Android/sdk" \
./gradlew :app:assembleDebug
```

## 目录

```text
.
├── android/          Android 客户端
├── mac-native/       macOS 客户端
├── Assets/           图标和素材
└── outputs/          本地构建产物，不提交
```

## 协议

[MIT License](LICENSE)
