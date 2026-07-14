# Security Policy

## Supported versions

安全修复优先应用到 `main` 和最新 GitHub Release。旧版本可能不会单独回补；报告问题时请提供受影响的提交或版本号。

## 私下报告漏洞

请不要为未修复漏洞创建公开 Issue。使用仓库的 [Private vulnerability reporting](https://github.com/xxkingstuggle/USBLinkMic/security/advisories/new) 提交报告。

报告中请尽量包含：

- 受影响的版本、平台和 Android ROM。
- 最小复现步骤与实际影响。
- 涉及的 ADB command、Intent、端口、VPN 路由或音频输入边界。
- 已脱敏的日志、PoC 或建议修复方向。

维护者会尽快确认报告并协调修复与披露时间，但当前项目不承诺固定响应 SLA。

## 安全边界

- USB 调试会授予已授权 Mac 较高的设备控制能力；只授权可信电脑。
- Android VPN 仅用于把流量送入本机 ADB relay，不代表匿名服务，也不会加密 relay 离开 Mac 后的公网流量。
- 发布页当前提供测试构建。自行构建时请保管好 Android keystore 和 Apple 签名身份，不要提交到仓库。
- 防火墙提示应用身份变化时，只应在确认二进制来自可信 Release 或由你本人构建后重新授权。
