# Changelog

本文件记录用户可感知的主要变化。版本发布遵循语义化版本号；尚未发布的主分支变化放在 `Unreleased`。

## Unreleased

## 3.1.0 - 2026-07-15

### Added

- 在 Mac App 内置官方 gnirehtet v2.5.1 Rust relay，支持 Mac 网络通过 ADB VPN 反向共享给 Android。
- Android 端显示由 Mac 控制的反向网络真实连接状态。
- 增加 macOS/Android 双端诊断信息、音频性能追踪和基础单元测试。

### Changed

- 统一 macOS 与 Android 应用图标。
- Android 深色模式使用黑色启动背景，避免冷启动白屏闪烁。
- 优化音频热路径、缓冲区复用和服务生命周期管理。

### Fixed

- 修复整数 PCM 未归一化导致 Mac 波形饱和成色块的问题。
- 修复 Android 麦克风权限、前台服务和等待调试器状态可能阻止录音的问题。
- 修复长时间运行后的资源泄漏、停止清理和部分断线恢复问题。

## 3.0.0 - 2026-07-03

- 首个公开版本。
- 支持 Android 麦克风通过 ADB 或局域网发送到 Mac。
- 支持手机网络通过 USB CDC-NCM/RNDIS 提供给 Mac。
- 提供 Mac 与 Android 图形界面及可下载测试构建。
