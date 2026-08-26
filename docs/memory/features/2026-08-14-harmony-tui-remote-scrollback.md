# 功能记忆：鸿蒙全屏 TUI 远端回看

## 背景

- 需求来源：用户反馈 Codex 输出超过多屏后，电脑终端滚动条无法回看，但鼠标滚轮可以；鸿蒙手机和模拟器此前只能滚动本地快照。
- 使用场景：通过 SSH 或 tmux/rmux 在鸿蒙端操作 Codex 等全屏 TUI，并回看由应用自身管理的历史内容。

## 关键功能点

- 单指继续滚动 ArkUI 本地历史，双指纵向滑动专用于远端 TUI 滚轮。
- 工具栏 `PGUP` / `PGDN` 根据远端鼠标模式自动切换：TUI 中发送远端滚轮，普通 Shell 中本地翻页。
- 支持传统 X10 与 SGR 鼠标编码；坐标按手势位置换算并钳制到 PTY 行列范围。
- 双指每累计 28vp 发送一个滚轮刻度，每次手势更新最多发送 4 个，工具栏按页发送 8 个，避免输入洪峰。

## 设计与实现

- 涉及模块：`MobileApp/shared/src/terminal/mod.rs`、`session/mod.rs`、`ffi/napi.rs`，以及鸿蒙 `TerminalDisplayContract.ets`、`TerminalNativeView.ets`。
- 核心流程：Rust 解析远端 `DECSET/DECRST ?1000/?1002/?1003/?1006`，在 `output` 事件上报 `mouseProtocol`；ArkTS 根据该状态将双指手势或工具栏翻页编码为 xterm wheel input，经现有 `writeSession` 写入 SSH 通道。
- 重要约束：鼠标跟踪关闭时绝不能向普通 Shell 写鼠标转义序列；不直接发送键盘 PageUp/PageDown，避免 Shell 回显 `~`；X10 坐标钳到单字节 ASCII 可安全承载的 95 列/行以内。

## 验证方式

- 命令：`cargo test`、`cargo clippy --all-targets --all-features`、Hvigor `test --mode module`、`devecocli build --build-mode debug`。
- 结果：Rust 81 项测试通过；Clippy 仅保留仓库既有警告；ArkTS 单元测试通过；双 ABI 交叉编译、clean build、签名 HAP 覆盖安装通过。模拟器现场用临时 SGR 鼠标测试 TUI 验证：工具栏 `PGUP` 一次收到 8 个 WHEEL UP；`uinput` 注入双指向下/向上轨迹后分别收到 WHEEL UP / WHEEL DOWN。HUAWEI Pura 70 真机随后完成覆盖安装和启动，截图确认 SSH 终端正常显示且应用数据保留。

## 后续注意事项

- tmux/rmux 是否把鼠标模式和滚轮传给 pane 内应用受远端配置影响；排查时先比较电脑端同一会话滚轮是否有效。
- 新增其他终端显示后端时，应复用相同的 `mouseProtocol` 状态和滚轮编码测试，不得回退为无条件发送转义序列。
- ArkUI `Scroll` 的内置 Pan 会抢占普通 `.gesture(PanGesture)`；双指远端滚轮必须使用 `.parallelGesture` 绑定。现场测试首版普通绑定未触发，切换并行手势后双向事件均通过。
