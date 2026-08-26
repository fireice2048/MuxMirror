# BugFix 记忆：鸿蒙原生终端显示与输入一致性

## 现象

- 触发条件：原生 ArkUI 终端显示备用屏 TUI、软键盘输入或回看长输出时。
- 用户影响：空白处光标错位，PlaceHolder 过亮；底部偶发多一行；无法稳定回看历史；英文输入被输入法重复组词；预编辑文字挤压 PlaceHolder；软键盘退格无法正确删除远端已有输入。

## 根因

- 备用屏渲染裁掉了光标定位所需的空行/空格，并以 Unicode 标量数而非 UTF-16 码元上报 ArkTS 偏移。
- ANSI 被剥离为纯文本，弱化状态没有随字符保存和透传。
- Scroll 在每次输出后无条件滚底，备用屏上滚行也没有进入历史。
- PTY 行数和 ArkUI 实际行高口径不一致，像素取整可能多报一行。
- `TextInput.onChange` 同时包含正式文字和输入法预上屏变化；差分后立即复位输入框会与系统输入法重排互相触发。
- 主屏 tokenizer 丢弃 BS 控制符，shell 回显的 `BS + 空格 + BS` 只剩空格，导致远端已删除而手机画面仍保留旧字符。

## 修复方案

- 涉及模块：Rust `terminal`/`session`/NAPI 事件桥、ArkTS `TerminalNativeView` 和事件契约。
- 关键改动：
  - 备用屏保存有限历史，按 UTF-16 计算光标和样式区间，并保留光标所在空白。
  - 最小解析 SGR `2/22/90/39/0`，用 `Span` 显示弱化灰色文字。
  - 用户离开底部后暂停自动跟随；主动回到底部才恢复。
  - 显式统一 16vp 行高，并向 PTY 少报一行作为安全余量。
  - `onChange` 只更新预编辑文字，`onDidInsert` 才发送确认文字，`onDidDelete`/硬件退格直接发送远端 Backspace。
  - 主屏保留 BS 并将标准擦除回显折叠为删除前一字符。

## 验证方式

- 复现步骤：模拟器连接保存的 SSH 服务器，依次输入英文、连续退格、输出 100 行、上滑后产生新输出、主动滑回底部，并构造备用屏弱化 PlaceHolder。
- 验证命令：
  - `cargo fmt --all --manifest-path MobileApp/shared/Cargo.toml -- --check`
  - `cargo test --manifest-path MobileApp/shared/Cargo.toml`
  - `bash MobileApp/shared/scripts/build-ohos.sh`
  - `devecocli build clean && devecocli build --build-mode debug`
- 验证结果：58 个 Rust 测试通过；OHOS arm64/x86_64 均构建成功；签名 HAP 覆盖安装成功；现场截图见 `docs/acceptance/evidence/harmony/2026-07-22-native-terminal-fidelity/`。
- 已知基线：严格 `cargo clippy -- -D warnings` 仍会被仓库既有的 FFI Safety 文档等警告阻塞；标准 clippy 退出 0，本次新增代码未引入对应警告。

## 预防措施

- 输入法确认与预编辑必须使用 ArkUI 专用回调区分，不再对 `onChange` 做“发送后立即复位”的正文差分。
- 终端控制字符修复必须同时验证远端实际执行结果和本地快照回显。
- 鸿蒙更新必须完成双 ABI 构建、签名包覆盖安装和设备侧截图，不能只以编译成功作为验收结论。
