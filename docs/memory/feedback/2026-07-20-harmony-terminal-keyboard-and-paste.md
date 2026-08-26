# BugFix 记忆：鸿蒙终端键盘切换与安全粘贴

## 现象

- 触发条件：Compose Multiplatform 鸿蒙终端通过透明 `BasicTextField` 唤起系统键盘，并在 ArkTS 层叠加安全粘贴控件。
- 用户影响：早期实现存在首次点击键盘按钮无效、进入终端自动弹键盘、图标已翻转但输入法未实际收起、普通 Compose 剪贴板读取无结果等问题。

## 根因

- OHOS 当前 `WindowInsets.ime` 不能可靠反映输入法状态，只以它驱动按钮会产生错误状态。
- 预先请求透明输入框焦点会直接触发鸿蒙输入法，导致终端打开即弹键盘。
- Compose `clearFocus` 只清理 Compose 内部焦点；安全控件交互后 ArkUI 根焦点仍可能保持输入会话。
- HarmonyOS 剪贴板读取受权限与安全策略约束，普通跨平台剪贴板接口不能作为稳定实现；直接声明 `READ_PASTEBOARD` 又属于受限权限，普通调试签名无法安装。

## 修复方案

- 涉及模块：`composeUI` 公共终端 UI、OHOS actual 平台桥、Harmony NAPI 和 ArkTS 页面入口。
- 关键改动：
  - 用本地 `keyboardRequestedVisible` 与输入法可见状态共同驱动图标和点击语义。
  - 取消页面进入时预聚焦，只在用户点击键盘按钮或终端输入区时请求焦点。
  - 收起时清理 Compose 焦点，通过 NAPI 请求 ArkTS 同时清理根焦点并调用输入法隐藏接口。
  - 使用官方 `PasteButton` 获取一次性剪贴板访问能力，再经 NAPI/C 接口把文本插入 KMM 输入缓冲。
  - 键盘展开时将按钮图标沿 Y 轴从 `1` 翻转为 `-1`。

## 验证方式

- 复现步骤：覆盖安装后从首页第一项进入 SSH，确认初始键盘收起；点击键盘按钮打开，再点击同一按钮关闭；重复三轮；粘贴后再次关闭。
- 验证命令：执行 KMM 单元测试和 OHOS 编译，发布共享库，`devecocli build clean` 后 debug 构建，覆盖安装 signed HAP，并核对 HAP 内与 stripped `libkn.so` 的 SHA-256。
- 验证结果：Pura 90 Pro / HarmonyOS 7.0.0（API 26）模拟器全部通过；粘贴 `MacBook Pro` 可见；x86_64 和 arm64-v8a 的入包哈希均一致。

## 预防措施

- KMM 终端 UI 变更后始终执行 publish + clean + build，并对入包 `libkn.so` 做哈希核验和视觉确认。
- 鸿蒙输入法状态不能只依赖 Compose IME Insets；涉及跨框架焦点时同时验证 Compose 与 ArkUI 焦点生命周期。
- 读取鸿蒙剪贴板优先使用官方安全控件，不为普通应用添加受限的长期剪贴板权限。
- 键盘交互回归必须覆盖首次打开、重复开合、其他原生控件交互后收起三种路径。
