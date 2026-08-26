# 鸿蒙原生终端显示与输入修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复鸿蒙原生终端的光标、弱化 PlaceHolder、滚动历史、屏幕行数、IME 预编辑和远端 Backspace。

**Architecture:** Rust `TerminalBuffer` 继续维护主屏和备用屏，增加最小弱化样式区间与有限滚动历史，通过现有 NAPI 事件透传给 ArkTS。ArkTS 仍用 `Text/Span` 渲染，并将隐藏 `TextInput` 改为区分预编辑与已提交文字的受控输入源。

**Tech Stack:** Rust、serde、HarmonyOS ArkTS/ArkUI、NAPI C API、Cargo、devecocli

---

## 文件结构

- `MobileApp/shared/src/terminal/mod.rs`：终端网格、光标、弱化样式和备用屏滚动历史。
- `MobileApp/shared/src/session/mod.rs`：output 事件数据契约。
- `MobileApp/shared/src/ffi/napi.rs`：将样式区间转换为 ArkTS 数组。
- `MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets`：ArkTS 事件类型和 mock 数据。
- `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`：样式渲染、滚动跟随、行数和 IME 输入。
- `docs/requirements/harmony-native-terminal-fidelity-progress.md`：里程碑进度。
- `docs/memory/bugfixes/2026-07-22-harmony-native-terminal-fidelity.md`：根因、修复和验证记忆。

### Task 1：修复光标偏移和备用屏滚动历史

**Files:**
- Modify: `MobileApp/shared/src/terminal/mod.rs`
- Test: `MobileApp/shared/src/terminal/mod.rs`

- [x] **Step 1：写入光标和历史失败测试**

```rust
#[test]
fn 备用屏emoji后光标使用utf16偏移() {
    let mut buf = TerminalBuffer::with_rows(4);
    buf.feed("\x1b[?1049h😀".as_bytes());
    assert_eq!(buf.cursor_offset(), 2);
}

#[test]
fn 备用屏保留光标所在空白位置() {
    let mut buf = TerminalBuffer::with_rows(4);
    buf.feed("\x1b[?1049h标题\x1b[3;5H".as_bytes());
    assert_eq!(buf.snapshot(), "标题\n\n    \n");
    assert_eq!(buf.cursor_offset(), "标题\n\n    ".encode_utf16().count());
}

#[test]
fn 备用屏上滚内容进入历史() {
    let mut buf = TerminalBuffer::with_rows(2);
    buf.feed("\x1b[?1049h一\r\n二\r\n三".as_bytes());
    assert!(buf.snapshot().starts_with("一\n"));
    assert!(buf.snapshot().ends_with("二\n三\n"));
}
```

- [x] **Step 2：运行定向测试并确认按预期失败**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml 备用屏`

Expected: FAIL，分别显示错误 UTF-16 偏移、空白行被裁剪、历史行缺失。

- [x] **Step 3：实现最小光标与历史模型**

```rust
use std::collections::VecDeque;

struct AltScreen {
    rows: Vec<Vec<Cell>>,
    history: VecDeque<Vec<Cell>>,
    history_bytes: usize,
    // 保留现有光标、滚动区域和保存光标字段
}

#[derive(Clone, Copy, Default)]
struct Cell {
    ch: char,
    dim: bool,
}

fn utf16_prefix_len(row: &[Cell], cells: usize) -> usize {
    row.iter().take(cells).map(|cell| cell.ch.len_utf16()).sum()
}
```

渲染当前屏时保留到 `max(last_non_empty_row, cur_r + 1)`；光标行保留到 `max(last_non_space_col, cur_c)`。只有全屏 `scroll_up` 移出的顶部行进入 `history`，按 `MAX_SNAPSHOT_BYTES` 淘汰最旧行。

- [x] **Step 4：运行定向测试和终端模块回归**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml terminal::tests`

Expected: PASS，且没有 `snapshot` 死代码警告。

- [x] **Step 5：提交里程碑**

```bash
git add MobileApp/shared/src/terminal/mod.rs docs/requirements/harmony-native-terminal-fidelity-progress.md
git commit -m "fix: 修复备用屏光标与滚动历史"
```

### Task 2：增加 PlaceHolder 弱化样式事件

**Files:**
- Modify: `MobileApp/shared/src/terminal/mod.rs`
- Modify: `MobileApp/shared/src/session/mod.rs`
- Modify: `MobileApp/shared/src/ffi/napi.rs`
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets`
- Test: `MobileApp/shared/src/terminal/mod.rs`
- Test: `MobileApp/shared/src/session/mod.rs`

- [x] **Step 1：写入 SGR 弱化和序列化失败测试**

```rust
#[test]
fn 备用屏输出弱化样式区间() {
    let mut buf = TerminalBuffer::with_rows(4);
    buf.feed("\x1b[?1049h正常\x1b[2m提示\x1b[22m正文".as_bytes());
    assert_eq!(buf.style_ranges(), &[TerminalStyleRange {
        start: 2,
        end: 4,
        style: "dim",
    }]);
}
```

在 session 测试中构造 `styles: Some(vec![...])`，断言 JSON 包含 `"start":2`、`"end":4`、`"style":"dim"`。

- [x] **Step 2：运行测试并确认缺少样式接口而失败**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml 弱化 && cargo test --manifest-path MobileApp/shared/Cargo.toml 事件序列化字段名对齐契约`

Expected: FAIL，缺少 `TerminalStyleRange`、`style_ranges` 或 `styles` 字段。

- [x] **Step 3：实现最小样式模型**

```rust
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalStyleRange {
    pub start: usize,
    pub end: usize,
    pub style: &'static str,
}

pub struct TerminalBuffer {
    // 现有字段
    view_styles: Vec<TerminalStyleRange>,
}
```

备用屏保存 `faint` 与 `gray` 状态：SGR `2`/`22` 控制 faint，`90`/`39` 控制 gray，`0` 全部复位；写字符时将 `faint || gray` 固化到 Cell。渲染时合并连续弱化 Cell 为 UTF-16 区间。

- [x] **Step 4：透传 output 事件与 NAPI 数组**

```rust
pub struct TmEvent {
    // 现有字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub styles: Option<Vec<TerminalStyleRange>>,
}
```

`NapiEvent` 保存样式 Vec；`event_call_js` 用 `napi_create_array_with_length` 创建数组，每项对象设置 `start`、`end`、`style`。ArkTS 契约：

```ts
export interface TerminalStyleRange {
  start: number;
  end: number;
  style: 'dim';
}

export interface TmEvent {
  // 现有字段
  styles?: TerminalStyleRange[];
}
```

- [x] **Step 5：运行 Rust 全量测试并提交**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml`

Expected: PASS，0 failed，0 warnings。

```bash
git add MobileApp/shared/src/terminal/mod.rs MobileApp/shared/src/session/mod.rs MobileApp/shared/src/ffi/napi.rs MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets docs/requirements/harmony-native-terminal-fidelity-progress.md
git commit -m "feat: 支持终端弱化文字样式"
```

### Task 3：修复 ArkTS 样式渲染、滚动跟随和屏幕行数

**Files:**
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`
- Modify: `docs/requirements/harmony-native-terminal-fidelity-progress.md`

- [x] **Step 1：定义渲染片段与共享尺寸常量**

```ts
interface TerminalSegment {
  text: string;
  dim: boolean;
}

const TERMINAL_FONT_SIZE: number = 12;
const TERMINAL_LINE_HEIGHT: number = 16;
const PTY_ROW_SAFETY: number = 1;
const TERMINAL_DIM: string = '#718078';
```

实现 `segmentsBetween(start, end)`：钳制区间、按样式边界切片、无样式时返回一个普通片段。

- [x] **Step 2：按区间渲染弱化 Span 和预编辑覆盖**

```ts
ForEach(this.segmentsBetween(0, this.terminalCursorOffset()), (part: TerminalSegment) => {
  Span(part.text).fontColor(part.dim ? TERMINAL_DIM : TERMINAL_GREEN)
})
Span(this.previewText)
Span('▌').fontColor(this.cursorVisible ? TERMINAL_GREEN : '#00B7F7C1')
ForEach(this.segmentsBetween(this.visibleAfterCursorStart(), this.output.length),
  (part: TerminalSegment) => {
    Span(part.text).fontColor(part.dim ? TERMINAL_DIM : TERMINAL_GREEN)
  })
```

当 `previewText` 非空时，`visibleAfterCursorStart()` 返回光标后首个换行位置，隐藏同一行 PlaceHolder；否则返回光标位置。

- [x] **Step 3：只在底部自动跟随**

```ts
@State private followOutput: boolean = true;

private updateFollowOutput(): void {
  this.followOutput = this.scroller.isAtEnd();
}
```

给 Scroll 增加 `.onScroll(() => this.updateFollowOutput())` 与 `.onScrollEdge(edge => ...)`；事件回调和 Text 布局后的 `scrollEdge(Edge.Bottom)` 均受 `followOutput` 门控。

- [x] **Step 4：统一行高并少报一行**

```ts
const measuredRows = Math.floor(availHeight / TERMINAL_LINE_HEIGHT);
const rows = Math.max(5, measuredRows - PTY_ROW_SAFETY);
```

Text 同时设置 `.fontSize(TERMINAL_FONT_SIZE)` 与 `.lineHeight(TERMINAL_LINE_HEIGHT)`。

- [x] **Step 5：执行鸿蒙干净构建并提交**

Run: `devecocli build clean && devecocli build --build-mode debug`

Expected: `BUILD SUCCESSFUL`，ArkTS 无类型错误。

```bash
git add MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets docs/requirements/harmony-native-terminal-fidelity-progress.md
git commit -m "fix: 修复终端样式滚动与屏幕行数"
```

### Task 4：修复 IME 预编辑、逐键发送和远端 Backspace

**Files:**
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`
- Modify: `docs/requirements/harmony-native-terminal-fidelity-progress.md`

- [x] **Step 1：替换整行本地缓冲为受控 IME 状态**

```ts
const IME_SENTINEL: string = '\u200B';

@State imeText: string = IME_SENTINEL;
@State previewText: string = '';
private committedText: string = IME_SENTINEL;
```

`TextInput` 绑定 `text: this.imeText`，回调改为 `(value: string, preview?: PreviewText) => this.onInputChange(value, preview)`。

- [x] **Step 2：只发送输入法确认文字**

```ts
private onInputChange(value: string, preview?: PreviewText): void {
  this.imeText = value;
  this.previewText = preview?.value ?? '';
}

private onImeInsert(info: InsertValue): void {
  this.onInput(encodeKey(info.insertValue, this.controlLocked, this.altLocked));
  this.resetImeInput();
}

private onImeDelete(_info: DeleteValue): void {
  this.onInput(encodeKey('BACKSPACE', this.controlLocked, this.altLocked));
  this.resetImeInput();
}
```

`onChange` 不发送正文，避免英文联想或中文组词的中间变化重复上屏；`onDidInsert` 只转发系统输入法最终确认文字。删除哨兵时由 `onDidDelete` 发送一次远端 Backspace，随后恢复哨兵和 caret。

- [x] **Step 3：简化回车和工具栏按键**

`sendInput()` 只发送 `\r`；方向键、Home、End、Delete、Tab、Esc 直接走 `onInput(encodeKey(...))`。删除 `inputText`、`caret`、`insertAtCaret`、`removeBeforeCaret`、`writeRemoteAction` 的整行缓存分支。

- [x] **Step 4：构建并提交**

Run: `devecocli build clean && devecocli build --build-mode debug`

Expected: `BUILD SUCCESSFUL`。

```bash
git add MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets docs/requirements/harmony-native-terminal-fidelity-progress.md
git commit -m "fix: 修复终端输入法与远端退格"
```

### Task 5：双 ABI 构建、部署和现场验收

**Files:**
- Create: `docs/memory/bugfixes/2026-07-22-harmony-native-terminal-fidelity.md`
- Modify: `docs/requirements/harmony-native-terminal-fidelity-progress.md`
- Modify: `README.md`

- [ ] **Step 1：运行 Rust 格式、测试和 lint**（fmt、58 个测试、标准 clippy 已通过；严格 `-D warnings` 被 12 个存量警告阻塞）

Run: `cargo fmt --all --manifest-path MobileApp/shared/Cargo.toml -- --check`

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml`

Run: `cargo clippy --manifest-path MobileApp/shared/Cargo.toml --all-targets --all-features -- -D warnings`

Expected: 三条命令均退出 0。

- [x] **Step 2：构建 OHOS 双 ABI 并复制动态库**

```bash
cd MobileApp/shared
cargo build --release --target aarch64-unknown-linux-ohos
cargo build --release --target x86_64-unknown-linux-ohos
cp target/aarch64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/arm64-v8a/
cp target/x86_64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/x86_64/
```

Expected: 两个目标构建成功，目标 `.so` 时间戳更新。

- [x] **Step 3：干净构建签名 HAP**

Run: `cd MobileApp/harmonyApp && devecocli build clean && devecocli build --build-mode debug`

Expected: `entry-default-signed.hap` 生成且 `BUILD SUCCESSFUL`。

- [x] **Step 4：安装并启动模拟器**

当前模拟器为 `Pura 90 Pro New`，串口为 `127.0.0.1:5555`。先用 `devecocli device list` 再次确认设备仍在线，然后执行：

```bash
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.attach.mobile.harmony
```

Expected: 保留应用数据完成覆盖安装，应用稳定启动。

- [x] **Step 5：现场验收并截图**

依次验证：PlaceHolder 灰色、英文/中文预编辑不挤压、电脑收到提交字符、远端 Backspace、生效的历史滚动与底部跟随、无多余底行、emoji/空白光标。截图存入 `docs/acceptance/evidence/harmony/2026-07-22-native-terminal-fidelity/`。

- [x] **Step 6：记录记忆、更新 README 和进度**

记忆文件必须包含现象、根因、修复方案、影响范围和验证方式；README 更新鸿蒙终端当前能力。将进度清单全部按实际结果勾选，未验证项保持未完成。

- [x] **Step 7：最终提交**

```bash
git add README.md docs/memory/bugfixes/2026-07-22-harmony-native-terminal-fidelity.md docs/requirements/harmony-native-terminal-fidelity-progress.md docs/acceptance/evidence/harmony/2026-07-22-native-terminal-fidelity
git commit -m "docs: 记录鸿蒙终端修复验收结果"
```

- [x] **Step 8：检查最终工作区**

Run: `git status --short && git log -6 --oneline`

Expected: 本任务文件均已提交；不提交 `target/`，不执行 `git push`。
