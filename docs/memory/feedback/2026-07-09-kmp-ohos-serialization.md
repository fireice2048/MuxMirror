# 反馈记忆：KMP common 依赖不能引用未发布 ohos 变体的库

## 坑点描述

- 在 `MobileClient/remote-control-shared`（KMP 公共模块）中引入 `kotlinx-serialization-json` 做协议编解码，Android / iOS 编译均通过，但 **HarmonyOS（ohosArm64 / ohosX64）编译失败**。
- 报错：`No matching variant of org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1 ... native target ohos_arm64`。

## 触发条件

- 在 `commonMain` 依赖项里使用 `kotlinx.serialization`（或任何未发布 `ohos_*` native 变体的第三方 KMP 库）。
- 鸿蒙端目标是 Kotlin/Native 的 `ohosArm64` / `ohosX64`，而多数 KMP 库目前只发布 ios/android/macos/watchos/tvos/jvm/js 等变体，**不含 harmony/ohos**。

## 正确做法

- 协议编解码等跨平台逻辑，若需在 commonMain 使用且要覆盖鸿蒙，应**避免依赖未发布 ohos 变体的库**。
- 本项目改用零依赖的极简手写 JSON 工具（`remote-control-shared/.../JsonUtil.kt`），仅覆盖固定协议字段，三端一致可编译。
- 引入任何新 KMP 依赖前，先确认其是否发布 ohos 变体；否则把该能力下沉到平台 actual，或仅在非鸿蒙源集使用。

## 验证方式

- 命令：`./gradlew :remote-control-shared:compileKotlinOhosArm64 --no-configuration-cache`
- 结果：移除序列化依赖、改用手写 JSON 后 BUILD SUCCESSFUL。
