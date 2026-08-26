# BugFix 记忆：ArkUI Stack 子组件 .align() 未生效导致悬浮按钮错位

## 现象

- 触发条件：`ServerListPage` 用 `Stack({ alignContent: Alignment.TopStart })` 叠加主内容 Column 和设置悬浮按钮，按钮靠子组件 `.align(Alignment.BottomEnd)` 期望悬浮在右下角。
- 用户影响：设置按钮实际出现在左上角 banner 区域（布局 dump 实测 bounds `[112,248][259,395]`），与 banner 图重叠几乎不可见，用户以为没有设置按钮。

## 根因

- 在 API 26（HarmonyOS 7.0.0 Beta1）模拟器上，Stack 子组件的 `.align()` 未覆盖 Stack 的 `alignContent`，子组件仍按 `alignContent: TopStart` 摆放。经典的「Stack + 子组件 .align 做 FAB」写法在该版本失效。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/pages/ServerListPage.ets`
- 关键改动：外层 Stack 的 `alignContent` 改为 `Alignment.BottomEnd`（主内容 Column 宽高 100% 不受影响），删除子组件上无效的 `.align(Alignment.BottomEnd)`。

## 验证方式

- 复现步骤：构建部署到 Pura 90 Pro 模拟器，首页观察设置按钮位置。
- 验证命令：`hdc shell uitest dumpLayout` 查看 ⚙ Text 的 bounds；模拟器截图确认。
- 验证结果：按钮出现在右下角，点击可正常打开设置页（截图 `Screenshot_2026-08-02T165749.png` / `165812.png`）。

## 预防措施

- ArkUI 中做悬浮按钮，优先用容器自身的 `alignContent`（或用全尺寸 Column + Blank 撑开定位），不要依赖子组件 `.align()` 覆盖 Stack 对齐；改动后用 `uitest dumpLayout` 的 bounds 或截图实测，不要只看代码意图。
