# Changelog

本项目遵循语义化版本号。

## 1.0.2 — 2026-09-27

- 兼容 ChatGPT 26.924.22138 的新内置 Codex CLI 布局。
- 通过 ChatGPT Bundle ID 定位应用，并优先使用签名的原生 Codex CLI，避免 GUI 环境误用无法找到 Node.js 的 Homebrew 启动器。
- 按 app-server 协议在 `initialize` 成功后发送 `initialized`，再读取额度。
- app-server 提前退出时立即显示连接错误，不再等待完整超时时间。

## 1.0.1 — 2026-08-10

- 修复菜单栏第三段错误显示 Weekly 自然重置时间的问题；现在始终显示最近一笔可用额外 Reset 的到期倒计时。
- 固定菜单栏三段语义为“Weekly 剩余额度 · 可用 Reset 次数 · 最近 Reset 到期时间”。
- 调整倒计时单位边界：超过 24 小时显示天，24 小时及以内显示小时。

## 1.0.0 — 2026-08-03

- 首个公开版本。
- 显示 ChatGPT Weekly 剩余额度、自然重置倒计时和额外 Reset 数量。
- 提供 Reset 到期提醒与本机通知设置。
- 每 60 秒自动刷新，并支持手动立即刷新。
- 通过本机 ChatGPT/Codex app-server 自动复用登录状态，不保存登录令牌。
- 提供随 ChatGPT 启停的 `Token Balance Watcher`。
- 采用 macOS 原生分层菜单和系统菜单栏文字颜色。
