# 鸿蒙终端物理键盘焦点与滚动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让终端轻点后可接收物理键盘输入，同时保持手指纵向翻屏且不自动弹出软键盘。

**Architecture:** 复用隐藏 `TextInput` 和现有 `Scroll`。点击绑定到覆盖整个终端区的 `Scroll`，关闭获焦自动拉起软键盘，并移除会竞争拖动的文本复制手势。

**Tech Stack:** HarmonyOS ArkTS、ArkUI、devecocli、HDC

---

### Task 1：调整焦点与手势绑定

**Files:**
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`

- [x] **Step 1：在 Scroll 上绑定轻点聚焦**

在 `Scroll` 的属性链中加入：

```ts
.onClick(() => focusControl.requestFocus('tmHiddenInput'))
```

- [x] **Step 2：禁止普通获焦自动弹软键盘**

在隐藏 `TextInput` 上加入：

```ts
.enableKeyboardOnFocus(false)
```

- [x] **Step 3：移除文本复制手势**

删除：

```ts
.copyOption(CopyOptions.InApp)
```

- [x] **Step 4：运行 ArkTS 干净构建**

Run: `cd MobileApp/harmonyApp && devecocli build clean && devecocli build --build-mode debug`

Expected: `BUILD SUCCESSFUL`，无 ArkTS 类型错误。

- [x] **Step 5：提交代码**

```bash
git add MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets docs/requirements/harmony-terminal-focus-scroll-progress.md
git commit -m "fix: 修复终端点击焦点与触摸滚动"
```

### Task 2：模拟器验收

**Files:**
- Modify: `docs/requirements/harmony-terminal-focus-scroll-progress.md`
- Create: `docs/acceptance/evidence/harmony/2026-07-22-terminal-focus-scroll/README.md`
- Create: `docs/memory/bugfixes/2026-07-22-harmony-terminal-focus-scroll.md`

- [x] **Step 1：构建并覆盖安装签名 HAP**

Run: `cd MobileApp/harmonyApp && devecocli build --build-mode debug && hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap`

Expected: 构建和覆盖安装成功，应用数据保留。

- [x] **Step 2：现场验收**

登录后保持软键盘收起，轻点终端并用 `uinput -K` 注入物理按键；输出长内容后用触摸拖动上下翻屏；点击工具条图标确认软键盘仍能弹出。

- [x] **Step 3：记录证据和记忆**

README 记录截图与操作结果；记忆文件记录点击手势删除造成焦点回归，以及 `copyOption` 与滚动竞争的修复。

- [x] **Step 4：提交验收结果**

```bash
git add docs/requirements/harmony-terminal-focus-scroll-progress.md docs/acceptance/evidence/harmony/2026-07-22-terminal-focus-scroll docs/memory/bugfixes/2026-07-22-harmony-terminal-focus-scroll.md docs/superpowers/plans/2026-07-22-harmony-terminal-focus-scroll.md
git commit -m "docs: 记录终端焦点与滚动验收结果"
git status --short
```

Expected: 工作区干净；不执行 `git push`。
