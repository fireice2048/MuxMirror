# iOS 首页服务器列表修复进度

参考：`docs/requirements/2026-07-28-ios-server-list-fix.md`

## 任务清单

- [x] 现状分析：阅读 iOS ServerListScreen、TermirrorCore、鸿蒙 ServerListPage/Index、Rust config 模块
- [x] 输出需求与进度文档
- [x] 迁移 App 图标与首页 banner
- [x] 修复 ServerConfig 身份标识、复制冲突、编辑改名、确认弹窗等 BUG
- [x] 通过 `scripts/deploy-mobile.sh ios` 构建并运行到模拟器
- [x] 自测并修复运行中发现的问题
- [x] 更新 README / AGENTS.md（如有必要）

## 验证结果

- 构建：`bash scripts/deploy-mobile.sh ios` 成功，iPhone 17 Pro 模拟器启动 Termirror。
- UI 测试：`xcodebuild -project MobileApp/iosApp/Termirror.xcodeproj -scheme Termirror -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` 通过（2 tests, 0 failures）。
- 截图确认：
  - 桌面 App 图标已替换为 MUXMIRROR 火焰图标（`docs/assets/ios-screenshots/ios-home-icon.jpg`）。
  - 首页 banner、服务器列表、端口号 `root@10.0.0.1:22` 显示正常（`docs/assets/ios-screenshots/ios-server-list.png`）。

## 关键改动

- `MobileApp/iosApp/Termirror/UI/Pages/ServerListScreen.swift`：以 `name` 为 `ServerConfig.id` 修复 ForEach 错位；复制自动去重；编辑改名先删旧名；端口用 `String(server.port)` 显示；sheet 关闭后重载列表。
- `MobileApp/iosApp/Termirror/TermirrorApp.swift`：检测到 `--uitesting` 时使用独立临时目录，避免测试污染真实数据。
- `MobileApp/iosApp/TermirrorUITests/ServerListUITests.swift`：新增新增服务器、复制去重两个 UI 测试。
- `MobileApp/iosApp/project.yml`：新增 `TermirrorUITests` 目标。
- 资源迁移：鸿蒙 `startIcon.png` → iOS AppIcon；鸿蒙 `attach_banner.png` → iOS Banner 图片集。
