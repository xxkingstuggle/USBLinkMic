# 故障排查

先确认只连接了一台 Android 设备，并执行：

```sh
adb devices
adb reverse --list
```

设备状态应为 `device`，而不是 `unauthorized`、`offline` 或空列表。

## Android 一直显示 Waiting For Debugger

清除系统的等待调试器设置并重新启动 App：

```sh
adb shell am clear-debug-app com.zjx.usblinkmic
adb shell am force-stop com.zjx.usblinkmic
adb shell monkey -p com.zjx.usblinkmic 1
```

如果仍然出现，请在 Android 开发者选项里关闭“选择调试应用”和“等待调试器”。

## Microphone recording is not permitted

1. 在 Android 系统设置中确认 USB LinkMic 的麦克风权限为“使用应用时允许”。
2. Android 13+ 同时允许通知权限，确保录音前台服务可以显示。
3. 关闭其他正在独占麦克风的通话、录音或语音助手 App。
4. 返回 USB LinkMic 后重新启动“手机麦克风”。

可用以下命令核对权限：

```sh
adb shell dumpsys package com.zjx.usblinkmic | grep -A 8 RECORD_AUDIO
```

## Mac 收到音频但波形或声音异常

- 两端采样率、声道数和 PCM 格式必须一致，建议先使用 48 kHz、Mono、i16。
- 先选择 Mac 内置扬声器验证，再切换到 BlackHole 或 USB 声卡。
- 查看 Mac 端诊断日志是否持续收到 packet，以及是否出现 buffer underrun/overrun。
- Wi-Fi 模式下确认手机与 Mac 在同一局域网，防火墙允许音频 TCP 端口。

## 手机网络给 Mac 无法启动

这个方向依赖 Android ROM 是否允许 ADB shell 切换 USB function。执行：

```sh
adb shell svc usb getFunctions
adb shell svc usb setFunctions ncm
adb shell svc usb getFunctions
```

如果设备拒绝命令、立即恢复为 `mtp,adb`，或 macOS 始终没有出现新网络服务，通常是 ROM/USB 控制器不支持，应用无法绕过厂商限制。

## Mac 网络给手机显示已连接但不能上网

1. 确认 Mac 端 relay、ADB reverse 和 Android VPN 三项都显示运行中。
2. 检查 `adb reverse --list` 是否包含：

   ```text
   localabstract:usblinkmic_net tcp:31416
   ```

3. 检查 Little Snitch、LuLu 或其他防火墙是否拦截 `gnirehtet-relay` 的 DNS/出站连接。
4. 尝试把 DNS 改为当前网络可访问的 DNS；企业网络可能屏蔽 `8.8.8.8`。
5. 停止功能后确认 VPN 图标消失，再重新启动，避免残留 VPN session。

自行重构建 Mac App 会改变二进制校验值。只有在确认 App 是你本人构建或来自可信 Release 后，才应在防火墙中接受身份变化。

## 收集可公开的诊断信息

提交 Bug 时建议包含：

- Mac 型号、macOS 版本和 Android 型号/ROM/版本。
- USB 或 Wi-Fi、功能方向和稳定复现步骤。
- Mac 与 Android App 版本。
- 相关日志片段，以及 `adb devices`、`adb reverse --list`、`svc usb getFunctions` 的输出。

请删除设备序列号、用户名、家庭/公司 IP、路径和其他个人信息。安全问题请按 [SECURITY.md](../SECURITY.md) 私下报告。
