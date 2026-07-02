# Changelog

## 2026-07-02

### Added

- Mac 端 Wi-Fi TCP 模式：可手动选择网络接口，显示 IP:端口 并支持复制。
- Android 端支持 ADB 和 Wi-Fi TCP 两种连接模式。
- ADB 模式下 Android 端显示「由 Mac 控制」及 Mac 实际下发的参数。

### Changed

- Wi-Fi 模式下，Mac 设置页隐藏采样率、声道、音频格式、音频源等由 Android 控制的参数。

### Fixed

- Mac 端使用默认路由接口的 IP，避免 Wi-Fi 端点 IP 错误。
- Android Wi-Fi TCP 握手读取对齐 Rust 原项目 `read_exact` 行为。
- Mac 关闭连接时 Android 不再闪退，手机麦克风开关会同步关闭。
- Android 设置页 IP 输入框焦点丢失问题。
- ADB 与 Wi-Fi 模式切换时不会沿用旧模式连接。

### Performance

- 限制波形图刷新到 25 fps，日志按 120 ms 批量刷新。
- 简化 Mac SwiftUI 材质和阴影，降低 GPU 合成压力。
- 预分配音频读取缓冲区，避免实时渲染线程堆分配。
- 音频格式转换新增直接单声道路径，减少中间数组分配。

### Removed

- 删除 Rust 原项目目录 `mac/`。
- 删除 `third_party/gnirehtet-relay-rust`（原 USB 网络中继依赖）。
- 删除 Android 设置页中的「实验性」标签和 USB 网络状态 section。
