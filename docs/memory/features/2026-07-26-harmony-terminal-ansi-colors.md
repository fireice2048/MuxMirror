# 功能记忆：鸿蒙终端 ANSI 颜色与状态栏高亮

## 背景

- 需求来源：用户现场截图显示 tmux/rmux 页脚只有普通绿字黑底，没有电脑终端中的高亮背景。
- 使用场景：HarmonyOS 原生终端查看 tmux、rmux、Codex 等使用 ANSI 显式前景色和背景色绘制的 TUI。

## 关键功能点

- 支持 SGR 30–37、40–47、90–97、100–107 标准色和亮色。
- 支持 SGR 38/48 的 256 色与 RGB 色。
- 支持 SGR 39/49 和 SGR 0 分别复位前景色、背景色与全部样式。
- 保留现有弱化和反色语义，样式区间使用 UTF-16 偏移与 ArkTS 字符串索引对齐。

## 设计与实现

- 涉及模块：`MobileApp/shared/src/terminal/mod.rs`、`MobileApp/shared/src/ffi/napi.rs`、`MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets`、`MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`。
- 核心流程：Rust 备用屏在每个 Cell 保存前景色和背景色，生成快照时合并相邻同样式区间；NAPI 上报 `foreground`/`background` 的 `#RRGGBB` 值；ArkTS `Span` 使用 `fontColor` 与 `textBackgroundStyle` 渲染显式颜色。
- 重要约束：~~默认主题仍为绿字深色背景~~（2026-08-02 起默认前景色改为浅灰 `#E0E0E0`，见 `docs/memory/features/2026-08-02-harmony-terminal-default-fg-pc-aligned.md`）；未指定背景色时 Span 保持透明，避免每个字符绘制额外背景；反色基于显式颜色与默认主题颜色互换。
- ANSI 标准绿色（索引 2，SGR 32/42）按产品视觉要求映射为 `#0DAC59`，不使用初版的 `#0DBC79`。

## 验证方式

- 命令：`cd MobileApp/shared && cargo test`
- 结果：67 个 Rust 单元测试通过，包含黑字绿底 tmux 状态栏、256 色、RGB 色与颜色复位测试。
- 命令：`cd MobileApp/harmonyApp && devecocli build --build-mode debug`
- 结果：ArkTS 编译与 HAP 打包成功，仅有项目既有弃用/权限警告。
- 命令：`./scripts/deploy-harmony-sim.sh`，随后通过 `hdc snapshot_display` 截图检查 tmux `muxapp` 会话。
- 结果：双 ABI Rust 核心构建成功，签名 HAP 在 `127.0.0.1:5555` 覆盖安装并启动成功；现场截图确认页脚为黑字绿色背景，普通终端多色文字保持正常。

## 后续注意事项

- `rustfmt` 与 `clippy` 未安装在当前默认 Rust toolchain，无法执行对应检查；提交前至少保持 `git diff --check` 和 Rust 测试通过。
- 若状态栏背景需要覆盖到行尾空白，必须让 Rust 网格保留远端实际写入的空格；当前快照仍会裁掉未写入的行尾空白。
- `Span` 不支持通用属性 `backgroundColor`，该调用虽可通过 ArkTS 编译但不会绘制文字背景；行内背景必须使用 API 11+ 的 `textBackgroundStyle({ color })`。
