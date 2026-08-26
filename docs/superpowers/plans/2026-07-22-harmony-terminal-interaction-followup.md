# 鸿蒙终端交互补充修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Codex 终端的光标恢复、手势滚动、软键盘按钮、键盘图标和全宽横线折行。

**Architecture:** 在 Rust 备用屏已有 ANSI 光标状态上补齐 `CSI s/u`，ArkTS 继续使用现有 Scroll、隐藏 TextInput 和工具条。只增加两列物理度量安全余量，并直接复用用户提供的 PNG 资源。

**Tech Stack:** Rust、HarmonyOS ArkTS/ArkUI、IME Kit、Cargo、devecocli

---

## 文件结构

- `MobileApp/shared/src/terminal/mod.rs`：解释 `CSI s/u` 并测试光标恢复。
- `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`：纵向滚动、显式键盘拉起、列数安全余量。
- `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalToolbar.ets`：使用图片键盘按钮。
- `MobileApp/harmonyApp/entry/src/main/resources/base/media/keyboard_icon.png`：用户提供的绿色键盘图标。
- `docs/requirements/harmony-terminal-interaction-followup-progress.md`：实施与验收进度。
- `docs/memory/bugfixes/2026-07-22-harmony-terminal-interaction-followup.md`：现场问题根因和验证结果。

### Task 1：补齐 `CSI s/u` 光标恢复

**Files:**
- Modify: `MobileApp/shared/src/terminal/mod.rs`
- Test: `MobileApp/shared/src/terminal/mod.rs`

- [x] **Step 1：写入失败测试**

```rust
#[test]
fn 备用屏_csi保存恢复光标() {
    let mut buf = TerminalBuffer::with_rows(4);
    buf.feed("\x1b[?1049hinput\x1b[s placeholder\x1b[u".as_bytes());
    assert_eq!(buf.cursor_offset(), "input".encode_utf16().count());
}
```

- [x] **Step 2：运行测试并确认失败**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml 备用屏_csi保存恢复光标`

Expected: FAIL，当前 cursor 停在 ` placeholder` 之后。

- [x] **Step 3：使用已有 saved 字段处理 CSI**

```rust
's' => self.saved = Some((self.cur_r, self.cur_c)),
'u' => {
    if let Some((r, c)) = self.saved {
        self.cur_r = r;
        self.cur_c = c;
    }
}
```

- [x] **Step 4：运行定向和终端模块测试**

Run: `cargo test --manifest-path MobileApp/shared/Cargo.toml 备用屏_csi保存恢复光标 && cargo test --manifest-path MobileApp/shared/Cargo.toml terminal::tests`

Expected: PASS，0 failed。

- [x] **Step 5：提交里程碑**

```bash
git add MobileApp/shared/src/terminal/mod.rs docs/requirements/harmony-terminal-interaction-followup-progress.md
git commit -m "fix: 补齐终端光标保存恢复"
```

### Task 2：修复滚动、键盘、图标和列宽

**Files:**
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalToolbar.ets`
- Create: `MobileApp/harmonyApp/entry/src/main/resources/base/media/keyboard_icon.png`
- Modify: `docs/requirements/harmony-terminal-interaction-followup-progress.md`

- [x] **Step 1：加入列宽安全余量**

```ts
const PTY_COL_SAFETY: number = 2;
const cols = Math.max(20, Math.floor(availWidth / this.measureCharWidthVp()) - PTY_COL_SAFETY);
```

- [x] **Step 2：让 Scroll 独占拖动手势**

给 `Scroll` 增加：

```ts
.scrollable(ScrollDirection.Vertical)
.enableScrollInteraction(true)
```

删除终端外层 `Column` 上请求 `tmHiddenInput` 焦点的 `.onClick`。

- [x] **Step 3：显式拉起键盘**

```ts
this.controller.focus = () => {
  focusControl.requestFocus('tmHiddenInput');
  setTimeout(() => {
    inputMethod.getController().showTextInput().catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '显示软键盘失败: %{public}s', err.message);
    });
  }, 0);
};
```

- [x] **Step 4：复制并使用指定图标**

Run:

```bash
cp /Users/xpeng/Documents/Codex/2026-07-22/h-ji/outputs/keyboard-icon-64-green.png \
  MobileApp/harmonyApp/entry/src/main/resources/base/media/keyboard_icon.png
```

`TerminalToolbar` 对 `KBD` 单独渲染：

```ts
if (item.key === 'KBD') {
  Image($r('app.media.keyboard_icon')).width(20).height(20).objectFit(ImageFit.Contain)
} else {
  Text(item.label)
}
```

删除 `KBD` 的 `⏏` 标签依赖、scale 和 animation。

- [x] **Step 5：运行 ArkTS 干净构建**

Run: `cd MobileApp/harmonyApp && devecocli build clean && devecocli build --build-mode debug`

Expected: `BUILD SUCCESSFUL`，无 ArkTS 类型错误。

- [x] **Step 6：提交里程碑**

```bash
git add MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets MobileApp/harmonyApp/entry/src/main/ets/components/TerminalToolbar.ets MobileApp/harmonyApp/entry/src/main/resources/base/media/keyboard_icon.png docs/requirements/harmony-terminal-interaction-followup-progress.md
git commit -m "fix: 修复终端滚动与键盘交互"
```

### Task 3：部署和现场验收

**Files:**
- Create: `docs/memory/bugfixes/2026-07-22-harmony-terminal-interaction-followup.md`
- Modify: `docs/requirements/harmony-terminal-interaction-followup-progress.md`
- Create: `docs/acceptance/evidence/harmony/2026-07-22-terminal-interaction-followup/README.md`

- [x] **Step 1：运行最终 Rust 检查**

Run: `cargo fmt --all --manifest-path MobileApp/shared/Cargo.toml -- --check && cargo test --manifest-path MobileApp/shared/Cargo.toml`

Expected: 0 failed。

- [x] **Step 2：双 ABI 构建并复制动态库**

```bash
cd MobileApp/shared
bash scripts/build-ohos.sh
cp target/aarch64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/arm64-v8a/
cp target/x86_64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/x86_64/
```

Expected: 两个 release 目标构建成功。

- [x] **Step 3：重新构建并覆盖安装签名 HAP**

```bash
cd MobileApp/harmonyApp
devecocli build clean
devecocli build --build-mode debug
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.attach.mobile.harmony
```

Expected: 签名包覆盖安装成功且应用稳定启动。

- [x] **Step 4：现场验收并保存证据**

验证键盘图标、按钮反复显隐、手势上下滑动、离底保持、已有输入光标、横线不折行。设备截图保存到 `docs/acceptance/evidence/harmony/2026-07-22-terminal-interaction-followup/`。

- [x] **Step 5：记录记忆和完成进度**

记忆文件写明现象、根因、最小修复、验证命令和现场结果；所有进度按实际结果勾选。

- [x] **Step 6：提交验收结果并检查工作区**

```bash
git add docs/memory/bugfixes/2026-07-22-harmony-terminal-interaction-followup.md docs/requirements/harmony-terminal-interaction-followup-progress.md docs/acceptance/evidence/harmony/2026-07-22-terminal-interaction-followup
git commit -m "docs: 记录鸿蒙终端交互验收结果"
git status --short
```

Expected: 工作区干净；不执行 `git push`。
