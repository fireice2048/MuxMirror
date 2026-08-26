# Harmony Server List Persistence Fix

## 背景

用户反馈新增或复制的服务器列表项重启后丢失，同时列表项操作图标仍然偏小且删除图标不够直观。

## 关键结论

- HarmonyOS 侧原先使用固定路径 `/data/storage/el2/base/files/attach_server_configs.txt`，在 Compose/Kotlin Native 运行上下文中无法可靠确认真实应用沙箱路径。
- ArkTS `UIAbilityContext.filesDir` 是当前应用真实可写文件目录，需在创建 Compose `ArkUIViewController` 前传给 Kotlin Native。
- 操作图标不能依赖 emoji 或字体字形，否则大小和视觉风格会受系统字体影响；改用 Compose `Canvas` 绘制铅笔、复制、垃圾桶线框图标。

## 影响范围

- 仅影响 HarmonyOS 存储路径初始化、首页列表项操作图标绘制。
- Android/iOS 现有存储实现不变。

## 验证方式

- `./gradlew :composeUI:compileDebugKotlinAndroid :composeUI:publishDebugBinariesToHarmonyApp` 通过。
- `devecocli run --device 'HUAWEI Pura 70' --uninstall` 通过，真机安装并启动成功。
- `devecocli log --device 'HUAWEI Pura 70' --crash --bundle-name com.attach.mobile.harmony --from 1m --tail 80` 无新崩溃输出。
