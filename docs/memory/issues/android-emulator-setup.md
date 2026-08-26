# 重点问题：本机搭建 Android 模拟器验证环境的坑

## 问题描述

- 移动端 Android 需在模拟器运行验证，但本机初始无 `sdkmanager`/`emulator` 二进制、无 AVD、无真机。
- `sdkmanager` 在线安装 emulator + 系统镜像时网络严重限速，且会卡死（下载到 1.56GB 停滞不增长，进程不退出），无法靠它完成。

## 当前状态

- 状态：已解决（Android 模拟器已可用并验证终端页）

## 已知线索

- `sdkmanager` 下载镜像会卡死；改用 `curl -C -`（断点续传）从 `https://dl.google.com/android/repository/sys-img/google_apis/arm64-v8a-36.1_r04.zip` 直链下载稳定（约 10MB/20s）。
- 直链下载后需人工解压到 `~/Library/Android/sdk/system-images/<android-xx.x>/<tag>/<abi>/` 并**补 `package.xml` 元数据**，否则 `avdmanager create avd` 报 “Package path is not valid”。`package.xml` 可复制同类型现有镜像的模板，改写 `localPackage path`/`api-level`/`extension-level`/`tag`/`revision`/`display-name`。
- **镜像选择坑**：`android-36.1` 的 `google_apis arm64-v8a` 镜像在 Apple Silicon + emulator 36.6.11 下启动卡死（进程在跑但 `adb` 长期 offline、不 boot）。改用 SDK 自带的 `android-36 google_apis_playstore arm64-v8a`（已有完整 package.xml）创建 AVD 可正常启动。
- 模拟器启动参数：`-gpu swiftshader -no-snapshot-load -wipe-data -no-audio -partition-size 2048`，首次 full startup 需等待数分钟。
- Android Activity 真实名由 aapt 解析为 `com.attach.mobile/.android.MainActivity`（`am start -n com.attach.mobile/.android.MainActivity`），manifest 里写 `.MainActivity`、Kotlin 包是 `com.attach.mobile.android`，启动需用 resolve-activity 给出的全名。

## 下一步

- 验证命令固化：`~/Library/Android/sdk/emulator/emulator -avd AttachTest36b ...` + `adb install` + `uiautomator dump` 取文本校验。
- 若换机器，优先直接用 SDK 自带镜像，避免直链下载大镜像。
