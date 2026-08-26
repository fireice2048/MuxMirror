# BugFix 记忆：tmux 分屏/裁剪重绘后终端残留旧字符（ECH 等 CSI 未实现）

## 现象

- 触发条件：鸿蒙模拟器 SSH 连本机，tmux 内执行 `split-window`、打开 vim 等触发"行尾裁剪重绘"的场景。
- 用户影响：画面出现旧内容拼接的"鬼影"文本，例如 `.sh` 行尾粘着 `x-------@   41 med`、`测速` 后粘 `r-xr-x     15 med`，左右窗格内容互相污染，终端不可用。

## 根因

- tmux 重绘被裁剪的行时，用 ECH（`ESC[<n>X`，Erase Character）抹掉新短行右侧的旧内容；对 `TERM=xterm-256color` 的客户端还可能使用 DCH/ICH/IL/DL。
- Rust 核心 `AltScreen::csi()`（`MobileApp/shared/src/terminal/mod.rs`）未实现 `X`/`P`/`@`/`L`/`M` 这五个终结符，序列被静默忽略，网格中旧字符保留，快照整体替换渲染后表现为行尾残留。
- 对照实验：用 pty 捕获 tmux 实际字节流，`grep` 到 `\x1b[20X`/`\x1b[17X` 等 ECH；pyte 逐行渲染的地面真值与设备截图逐行比对，确认差异就在被 ECH 擦除的区段。

## 修复方案

- 涉及模块：`MobileApp/shared/src/terminal/mod.rs`（三端共用核心，Android/iOS 同受益）。
- 关键改动：`AltScreen` 新增 `erase_chars`（ECH）、`delete_chars`（DCH）、`insert_chars`（ICH）、`insert_lines`（IL）、`delete_lines`（DL），`csi()` 补齐 `X`/`P`/`@`/`L`/`M` 分发；IL/DL 限定在滚动区域内操作。
- 新增 4 个单元测试覆盖五个序列；另加 `examples/replay.rs`（重放捕获字节流输出快照），用于和 pyte 等参照实现做整屏对比。

## 验证方式

- 复现步骤：模拟器连本机 SSH → `tmux new-session -s reg2` → `clear; ls -la` → `tmux split-window -h`。
- 验证命令：`cargo test --lib terminal`（47 项含新增 4 项全过）；`cargo run --example replay -- <捕获.raw>` 与 pyte 输出逐行 diff；设备截图比对。
- 验证结果：重编部署后分屏画面与 `tmux capture-pane` 地面真值完全一致，残留全部消失；vim（E325 swap 警告页）渲染正常。

## 预防措施

- **鸿蒙交叉编译必须走 `MobileApp/shared/scripts/build-ohos.sh`**：直接 `cargo build --target aarch64-unknown-linux-ohos` 会因 openssl-sys 找不到 OHOS OpenSSL（需脚本内 pkg-config-ohos.sh 环境）而失败；且 `cargo build 2>&1 | tail -3 && cp ...` 这类管道会以 tail 的退出码掩盖编译失败，把旧 .so 部署上机，造成"修复没生效"的假象（本次第一轮回归即踩中）。
- 新增终端控制序列支持时，先用 pty 捕获真实字节流确认目标程序（tmux/vim）实际会发哪些序列，再对照实现；ech/dch/ich/il/dl 是 xterm-256color 下 tmux 的常用擦写序列。
- 部署后不能只看"install bundle successfully"，需用地面真值（capture-pane / pyte）比对实际渲染。
