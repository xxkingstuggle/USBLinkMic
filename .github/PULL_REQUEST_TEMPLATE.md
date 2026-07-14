## 变更摘要

<!-- 说明改了什么。 -->

## 用户问题与根因

<!-- 为什么需要改；如果是 Bug，请说明根因。 -->

## 验证

- [ ] Android：`testDebugUnitTest lintDebug assembleDebug`
- [ ] macOS：无签名 `xcodebuild` 构建
- [ ] gnirehtet relay：`cargo test --locked`（如涉及）
- [ ] 真机验证了受影响的数据流
- [ ] 停止、断线、失败和应用退出后没有残留服务/端口/VPN

## 风险与回退

<!-- 说明权限、网络路由、实时音频、兼容性和回退方式。 -->

## 截图或日志

<!-- UI 变化请附浅色/深色截图；日志必须脱敏。 -->

## 文档

- [ ] 已更新相关 README、Troubleshooting、Architecture 或 Changelog
- [ ] 不需要更新文档
