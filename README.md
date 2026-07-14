<p align="center">
  <img src="Assets/icon512.png" width="148" alt="USB LinkMic icon">
</p>

<h1 align="center">USB LinkMic</h1>

<p align="center">
  用一根 USB 线，把 Android 手机的麦克风和网络能力交给 Mac，也可以把 Mac 网络反向共享给手机。
</p>

<p align="center">
  <a href="README.zh-CN.md"><b>中文文档</b></a>
  ·
  <a href="README.en.md"><b>English</b></a>
  ·
  <a href="https://github.com/xxkingstuggle/USBLinkMic/releases/latest"><b>下载最新版</b></a>
</p>

<p align="center">
  <a href="https://github.com/xxkingstuggle/USBLinkMic/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/xxkingstuggle/USBLinkMic/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/xxkingstuggle/USBLinkMic/releases/latest"><img alt="GitHub release" src="https://img.shields.io/github/v/release/xxkingstuggle/USBLinkMic"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Android 8+" src="https://img.shields.io/badge/Android-8%2B-3DDC84?logo=android&logoColor=white">
</p>

## 一套应用，三个方向

| 能力 | 数据方向 | 适合场景 |
| --- | --- | --- |
| 手机麦克风给 Mac | Android → Mac | 会议、录音、直播，把手机当作 Mac 麦克风输入源 |
| 手机网络给 Mac | Android → Mac | 通过 USB CDC-NCM/RNDIS 使用手机网络 |
| Mac 网络给手机 | Mac → Android | 通过 ADB reverse + Android VPN 反向共享 Mac 网络 |

<p align="center">
  <img src="Assets/android-main-current.png" width="340" alt="USB LinkMic Android 主界面">
</p>

## 设计原则

- **Mac 统一控制**：ADB 模式下，启动、停止、端口映射与 VPN relay 都由 Mac 端编排。
- **本地处理**：不需要账号，不包含分析或遥测 SDK；音频和转发流量不会上传到项目服务器。
- **状态可见**：两端都显示真实连接状态和诊断信息，不用“假开关”掩盖前置条件。
- **失败可恢复**：模块停止时清理 ADB reverse、VPN、relay 和临时网络配置。

## 系统要求

- Apple Silicon Mac，macOS 26 或更高版本。
- Android 8.0（API 26）或更高版本。
- 一根支持数据传输的 USB 线，并在手机上启用 USB 调试。
- Mac 已安装 Android Platform Tools，终端中可以运行 `adb`。

> [!IMPORTANT]
> “手机网络给 Mac”依赖手机 ROM 是否允许切换 `ncm`/`rndis` USB function，不能保证所有厂商系统都支持。当前 Android 下载包为测试用 debug APK；macOS 发布包尚未进行 Developer ID 公证。

## 快速开始

1. 从 [GitHub Releases](https://github.com/xxkingstuggle/USBLinkMic/releases/latest) 下载 macOS 压缩包和 Android APK。
2. 把 `USB LinkMic.app` 放入 `/Applications`，在手机上安装 APK。
3. 打开 Android 的开发者选项与 USB 调试，并接受这台 Mac 的调试授权。
4. 先打开 Android App，再从 Mac 端选择并启动需要的功能。

完整操作说明见[中文文档](README.zh-CN.md)，故障排查见 [Troubleshooting](docs/TROUBLESHOOTING.md)。

## 架构与构建

- [架构与数据流](docs/ARCHITECTURE.md)
- [中文使用和构建说明](README.zh-CN.md)
- [English documentation](README.en.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [变更记录](CHANGELOG.md)
- [发布流程](docs/RELEASING.md)
- [第三方软件声明](THIRD_PARTY_NOTICES.md)

CI 会分别验证 Android 单元测试、Lint 与 debug 构建，macOS 无签名构建，以及内置 gnirehtet relay 的 Rust 测试。

## 开源协议

USB LinkMic 自有代码使用 [MIT License](LICENSE)。项目内置的 [gnirehtet](https://github.com/Genymobile/gnirehtet) v2.5.1 组件继续遵循 Apache-2.0；完整上游源码和许可证位于 `third_party/gnirehtet/`。
