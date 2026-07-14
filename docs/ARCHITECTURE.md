# 架构与数据流

USB LinkMic 由 Android 客户端、macOS 控制端和内置 gnirehtet relay 组成。Mac 端是 ADB 模式下的编排者；Android 端负责录音、前台服务和 VPN 数据面。

## 三条独立数据流

```text
手机麦克风给 Mac
Android AudioRecord
  -> PCM framing
  -> ADB reverse 或 Wi-Fi TCP
  -> Mac TCP receiver
  -> PCM decode / gain / resample
  -> Core Audio output + waveform

手机网络给 Mac
Mac UI
  -> adb shell svc usb setFunctions ncm
  -> Android USB CDC-NCM/RNDIS
  -> macOS network service
  -> phone cellular/Wi-Fi uplink

Mac 网络给手机
Android app traffic
  -> Android VpnService
  -> localabstract:usblinkmic_net
  -> adb reverse tcp:31416
  -> bundled gnirehtet Rust relay
  -> Mac network uplink
```

## 组件职责

### Android

- `ForegroundService` 管理录音与音频流生命周期。
- `TcpStreamer` 负责 PCM 网络发送和断线处理。
- `LinkNetService` / `RelayTunnel` 负责反向共享网络的 VPN 与 packet forwarding。
- `MainViewModel` 把服务真实状态映射到 Compose UI。

### macOS

- `AppModel` 编排 ADB、USB function、网络服务和三个模块的互斥/清理。
- `AudioPlayer`、`AudioFormat` 和 ring buffer 负责实时 PCM 转换与 Core Audio 输出。
- `WaveformData` 只消费归一化样本，避免整数 PCM 直接导致波形饱和。
- `GnirehtetRelay` 只启动 App bundle 内的固定 relay，并在启动失败或应用退出时终止进程。

## 关键边界

- 音频默认 TCP 端口为 `55555`；ADB 模式使用同端口 reverse。
- gnirehtet relay 默认监听 `127.0.0.1:31416`，Android 通过 `localabstract:usblinkmic_net` 连接。
- 两个网络方向互斥，防止 Mac 默认路由同时被手机上行和反向 VPN 修改。
- 停止操作需要成对清理服务、ADB reverse、relay 和临时 USB/network 设置。
- `third_party/gnirehtet/` 是固定版本的上游快照，不应与本项目业务代码混写。

## 隐私模型

项目没有账号、云端控制面或遥测服务。音频和网络流量只在 Android、USB/局域网链路和 Mac 之间传输。VPN 的目的只是接管 Android 路由并把 packet 交给 Mac relay，不提供匿名或端到端加密保证。
