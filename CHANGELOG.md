# Changelog

## 3.0.0 - 2026-07-03

### Added

- Bilingual English/Chinese project documentation.
- macOS native app with selectable output device routing.
- Android app with ADB and Wi-Fi TCP streaming modes.
- Live waveform preview in the Mac app.
- GitHub issue templates and open-source project metadata.

### Changed

- Reworked the Mac audio output pipeline around CoreAudio for lower overhead.
- Reduced UI refresh pressure by batching logs and throttling waveform updates.
- Simplified the Android/Mac connection model around ADB reverse and TCP streaming.

### Fixed

- Fixed Android service startup behavior for recent Android versions.
- Fixed Wi-Fi endpoint detection on macOS by preferring the default route interface.
- Fixed audio output device selection by using HALOutput for explicitly selected devices while preserving the working element layout.

---

# 更新日志

## 3.0.0 - 2026-07-03

### 新增

- 中英双语项目文档。
- macOS 原生应用，支持选择音频输出设备。
- Android 应用，支持 ADB 和 Wi-Fi TCP 两种推流模式。
- Mac 端实时波形预览。
- GitHub Issue 模板和开源项目元信息。

### 变更

- Mac 音频输出链路改为围绕 CoreAudio 实现，降低运行开销。
- 日志批量刷新、波形限频刷新，减少 UI 压力。
- 围绕 ADB reverse 和 TCP 推流简化 Android/Mac 连接模型。

### 修复

- 修复新版 Android 上服务启动行为。
- 修复 macOS Wi-Fi 端点优先选择默认路由接口的问题。
- 修复显式选择输出设备时的路由问题：选择具体设备时使用 HALOutput，同时保留已验证可启动的 element 布局。
