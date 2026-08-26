# iOS 首页服务器列表修复与鸿蒙资源迁移

## 背景
iOS 版首页服务器列表存在多处稳定性与体验问题，且缺少 App 图标与首页 banner。参考已验收的鸿蒙版实现进行修复与资源迁移。

## 目标
1. 修复 `ServerListScreen` 中导致列表项错位、编辑/删除/复制目标错误、拖拽排序异常的根因 BUG。
2. 补齐复制、重命名时的名称冲突处理，对齐鸿蒙版确认弹窗。
3. 迁移鸿蒙版 App 图标与首页 banner 到 iOS Assets。
4. 通过 `scripts/deploy-mobile.sh ios` 在 iOS 模拟器构建、安装、启动并自测。

## 已知问题清单

### 1. ServerConfig 身份标识错误（P0）
- **位置**：`MobileApp/iosApp/Termirror/UI/Pages/ServerListScreen.swift:160-162`
- **现象**：`extension ServerConfig: Identifiable { var id: UUID { UUID() } }` 每次访问都生成新 UUID。
- **后果**：
  - `ForEach($servers)` 无法稳定追踪行身份，列表刷新时丢失行状态。
  - 编辑、复制、删除的回调可能作用于错误行。
  - `.sheet(item:)` / `.alert(item:)` 依赖身份，行为异常。
- **修复**：以 `name` 作为唯一标识（与 Rust 核心按 name upsert/delete 的契约一致）。

### 2. 复制名称冲突导致覆盖（P1）
- **位置**：`ServerListScreen.swift:21-24`
- **现象**：复制直接生成 `"xxx 副本"`，多次复制会覆盖同名配置。
- **修复**：参考鸿蒙 `Index.ets:129-144`，检测到重名时追加序号（副本2、副本3…）。

### 3. 编辑后改名造成重复或覆盖（P1）
- **位置**：`ServerEditSheet` 保存回调
- **现象**：编辑时修改名称，Rust 核心按新 name upsert，旧 name 条目残留，导致列表出现两条；若新 name 已存在则覆盖。
- **修复**：编辑场景下若名称变更，先 `deleteConfig(oldName)` 再 `saveConfig(config)`。

### 4. 缺少复制确认弹窗（P2）
- **现象**：首页复制按钮一触即发，与鸿蒙版人工验收反馈不符。
- **修复**：添加“复制服务器”确认弹窗。

### 5. 资源缺失
- **App 图标**：iOS `Assets.xcassets/AppIcon.appiconset` 只有空 `Contents.json`，无图片。
- **首页 banner**：iOS 无首页 banner，鸿蒙版使用 `attach_banner.png`（MUXMIRROR）。
- **修复**：将鸿蒙 `startIcon.png` 适配为 iOS App Icon，将 `attach_banner.png` 放入 iOS Assets 并在首页展示。

## 非目标
- 不改 iOS 终端页、网络诊断页逻辑。
- 不改 Rust 核心 API 与鸿蒙版 UI。
- 不处理真实 SSH 连接功能（本次只修复列表与资源）。

## 验收标准
- [ ] `scripts/deploy-mobile.sh ios` 能成功构建、安装、启动到 iPhone 17 Pro 模拟器。
- [ ] 首页正确显示 banner、服务器列表、网络诊断入口。
- [ ] 添加、编辑、删除、复制、拖拽排序功能正常，数据持久化。
- [ ] App 图标在模拟器主屏幕与设置中正确显示。
