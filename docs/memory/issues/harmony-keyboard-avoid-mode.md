# 重点问题：鸿蒙 Compose 嵌入场景下键盘避让导致状态栏跳动

## 问题描述

- 移动端终端页点击输入框弹出软键盘时，App 顶部状态栏出现跳动/闪烁。
- 同时出现过反向问题：改用 OFFSET 模式后输入框与工具栏不再跟随上滑。

## 当前状态

- 状态：已规避（OFFSET 模式 + 根组件 expandSafeArea([SafeAreaType.KEYBOARD]) + EntryAbility 窗口全屏沉浸式），待真机验证。

## 已知线索

- 鸿蒙 `KeyboardAvoidMode` 有两种：
  - `RESIZE`：窗口可用高度被压缩重排，Compose 内容区 `weight(1f)` 会自动缩小、底部输入框上移；但页面若铺满含状态栏的全屏区域，窗口高度变化会带动状态栏重排 → 状态栏跳动。
  - `OFFSET`：系统整体上移页面内容，窗口高度不变，状态栏完全不动；但 Compose 嵌入组件需通过 `expandSafeArea([SafeAreaType.KEYBOARD])` 标记才参与上移，否则输入框不上滑。
- Compose 侧 `imePadding()` 在鸿蒙 ArkUI 嵌入场景下 `WindowInsets.ime` 不被驱动，不能单独承担避让。
- `KeyboardAvoidMode` 属于 `UIContext`（`this.getUIContext().setKeyboardAvoidMode(...)`），不在 `Window` 实例上；枚举成员是 `OFFSET`/`RESIZE`（不是 `RESIZE_CONTENT`）。
- `setKeyboardAvoidMode` 从 `@kit.ArkUI` 导入 `KeyboardAvoidMode`，不能用 `window.KeyboardAvoidMode`。

## 下一步

- 真机验证 OFFSET + expandSafeArea(KEYBOARD) + 全屏沉浸式是否既消除状态栏跳动、又让输入框/工具栏跟随上滑。
- 若 OFFSET 下输入框仍不上滑，回退 RESIZE + EntryAbility `setWindowLayoutFullScreen(true)`（状态栏叠加层，RESIZE 压缩内容区时不重排状态栏）。
