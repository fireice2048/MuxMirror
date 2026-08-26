# 反馈记忆：鸿蒙模拟器 API 18 上 Compose 白屏的坑

## 坑点描述

Compose Multiplatform 鸿蒙版（`1.9.2-0.3.0`）构建的 HAP 在 **HarmonyOS 5.1.0 (API 18)** 模拟器上全屏白屏，但 App 进程存活、无 crash、Kotlin/Native 与 Compose 初始化日志全部正常，极易误判为"代码改动坏了 UI"。

## 现象与证据

- 截图纯白（仅剩系统导航条），`aa force-stop` 重启无效。
- `devecocli log --crash --bundle-name com.attach.mobile.harmony` 无任何崩溃记录。
- hilog 关键证据：
  - `OHRender-API Missing ... No OH_Drawing_CanvasDrawRecordCmdNesting support`
  - `No OH_ImageSourceNative_CreateFromDataWithUserBuffer(API20) support`
  - `No OH_Drawing_CanvasDrawPixelMapRectConstraint(API20) support`
  - `WindowStageManager: rotationChange not available (API 19+)`（侧面证实系统只有 API 18）
- Compose 渲染（FusionRenderer/OH_Drawing 路径）依赖 **API 20+** 的绘图接口，在低版本系统上 missing 且无降级出图，于是 UI 逻辑在跑但屏幕上没有任何像素。

## 根因

- 工程 `targetSdkVersion` 为 26.0.0，历史验收全部在 Pura 90 Pro 模拟器（HarmonyOS 7.0.0(26.0.0) Beta1）上进行，从未在低版本系统验证过。
- 7.0.0(26) Beta1 镜像被删除后，本机只剩 HarmonyOS 5.1.0(18) 镜像（Huawei_Phone_5_1），环境问题暴露为"白屏"。

## 触发条件

- 把 Compose Multiplatform 鸿蒙版构建的 HAP 安装到 **低于 API 20** 的模拟器/真机。
- 判断方法：进程存活 + 无 crash + 白屏时，抓 hilog 找 `OHRender-API Missing` 关键字即可确认，不必怀疑业务代码。

## 正确做法

- 模拟器镜像必须选 **≥ API 20**：公开下载列表中的 6.0.2(22) / 6.1.0(23) / 6.1.1(24) Release 均可，例如：
  ```sh
  devecocli emulator image download --device-type phone --os-version "HarmonyOS 6.1.1(24)"
  devecocli emulator create "Phone_6_1_1" --device-type phone --os-version "HarmonyOS 6.1.1(24)"
  ```
- 7.0.0(26.0.0) Beta1 **不在公开下载列表**，只能经 DevEco Studio → Device Manager 的 Beta 通道恢复。
- 验收环境变更后，先在目标镜像上做一次"能否出图"的冒烟验证，再开始功能验收。

## 验证方式

- 2026-07-17：API 18 模拟器复现白屏并完成日志取证；待 6.1.1(24) 镜像就绪后创建新实例复测，确认 UI 正常渲染后继续 SSH 密码认证验收。
