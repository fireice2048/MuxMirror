# 鸿蒙全屏 TUI 远端回看实现进度

需求文档：[2026-08-14-harmony-tui-remote-scrollback.md](2026-08-14-harmony-tui-remote-scrollback.md)

- [x] 记录需求、交互方案和验收标准
- [x] Rust 终端解析器跟踪 DEC 鼠标模式
- [x] `output` 事件经 NAPI 向 ArkTS 上报鼠标模式
- [x] ArkTS 实现滚轮事件编码与距离累计
- [x] 鸿蒙终端绑定双指纵向滑动手势
- [x] 工具栏 PGUP/PGDN 按鼠标模式切换远端/本地翻页
- [x] 补充 Rust 与 ArkTS 单元测试
- [x] 更新 README 和 BugFix/功能记忆
- [x] Rust 常规测试与格式检查通过
- [x] 双 ABI Rust 核心交叉编译并部署 `.so`
- [x] 鸿蒙签名 HAP 清理构建通过
- [x] 模拟器覆盖安装、启动并现场验收
- [x] Pura 70 真机覆盖安装、启动并截图确认

## 现场验收记录（2026-08-14）

- 设备：Pura 90 Pro 模拟器（`127.0.0.1:5555`）。
- 使用临时 Python TUI 开启 `?1000;1006h` 并显示收到的 SGR wheel 计数。
- 工具栏 `PGUP` 单击后 `WHEEL UP` 从 0 增至 8，确认按页远端滚轮路径生效。
- `uinput -T -m` 注入两指纵向向下和向上轨迹，TUI 分别收到 WHEEL UP 与 WHEEL DOWN。
- 首轮普通 `.gesture` 被 Scroll 内置 Pan 抢占；改为 `.parallelGesture` 后双指轨迹通过。
- 已启动真实 Codex v0.147.0 页面确认应用和 Rust 核心更新生效。
- 2026-08-14 通过 USB 连接 HUAWEI Pura 70（`3XQ0224A11020136`），重新执行双 ABI、clean HAP 构建并覆盖安装；应用启动成功，截图确认现有服务器配置保留且 SSH 终端正常显示。双指触控效果仍建议用户在真实 Codex 长输出场景中体验确认手感。
