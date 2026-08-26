# BugFix 记忆：Android JNA 事件回调被 GC 回收导致事件全丢

## 现象

- 触发条件：Android 端任意 Rust → Kotlin 事件（连接状态、终端输出、网络诊断、exec 结果）。
- 用户影响：终端页永远停在"正在连接"直到 10 秒本地超时；网络诊断发送后无结果；MUX 导航页一直转圈。Rust 日志（`files/logs/TermMirror-*.log`）显示事件已正常发出。

## 根因

- `TermirrorCore.initialize()` 中 `lib.tm_on_event(object : Lib.TmEventCallback {...})` 传入的是匿名临时对象，Java 侧没有强引用持有。
- JNA 回调对象被 GC 回收后，本地函数指针 thunk 被释放，Rust 侧调用回调静默失效，且 logcat 无任何报错。
- 这是 JNA 经典陷阱：凡注册给 native 的 Callback，必须由 Java 侧长期持有强引用。

## 修复方案

- 涉及模块：`MobileApp/androidApp/.../core/TermirrorCore.kt`
- 关键改动：将回调提升为 `TermirrorCore` 单例的 `private val eventCallback` 属性，注册时复用该实例。

## 验证方式

- 复现步骤：添加服务器（空密码）→ 点击连接 → Rust 日志 56ms 内报认证失败，但 UI 卡在"正在连接"。
- 验证命令：`bash scripts/deploy-mobile.sh android` 后连接服务器。
- 验证结果：认证失败事件立刻上屏（"认证失败：password 与 keyboard-interactive 均被拒"）。

## 预防措施

- JNA `Callback` / 监听器注册后必须在 Java 侧以字段形式持有，禁止传匿名临时对象。
- 排查"Rust 日志正常但 UI 无反应"类问题时，优先怀疑回调链路而非 UI 状态。

---

# BugFix 记忆：Android Compose 新版导致 burnoutcrew reorderable 崩溃

## 现象

- 触发条件：服务器列表存在任意条目时打开首页。
- 用户影响：App 直接闪退（`NoSuchMethodError: animateItemPlacement$default`）。

## 根因

- `org.burnoutcrew.composereorderable:reorderable:0.9.6` 已于 2023 年停更，内部调用的 `LazyItemScope.animateItemPlacement` 在新版 Compose foundation（BOM 2026.02.01）中已删除（改名为 `animateItem`）。
- 空列表时不触发渲染路径，所以首页空数据时看似正常，一旦新增服务器即崩。

## 修复方案

- 涉及模块：`MobileApp/androidApp/gradle/libs.versions.toml`、`ui/pages/ServerListScreen.kt`
- 关键改动：替换为维护中的 fork `sh.calvin.reorderable:reorderable:2.5.1`；`rememberReorderableLazyListState(listState) { from, to -> ... }` 直接挂在 `LazyListState` 上，条目用 `Modifier.longPressDraggableHandle()` 实现整卡长按拖拽。

## 验证方式

- 复现步骤：新增任意服务器 → 首页闪退。
- 验证结果：列表正常渲染，长按拖拽排序可用。

## 预防措施

- 升级 Compose BOM 后必须全量回归依赖第三方库的 API 兼容；停更库及时替换为维护 fork。

---

# BugFix 记忆：Android MUX 导航页重试后 execId 不更新导致永久加载

## 现象

- 触发条件：MUX 导航页首次 `muxmirror` exec 失败（如认证失败）。
- 用户影响：页面永远停在"正在查询终端窗口..."，不会进入错误态。

## 根因

- `scheduleRetry` 中 `runQuery(server) {}` 传入空回调，重试产生的新 execId 未写回状态；监听器以 `event.sessionId == execId` 过滤，重试结果永远匹配不上，重试链路中断，加载态无法退出。

## 修复方案

- 涉及模块：`MobileApp/androidApp/.../ui/pages/MuxNavScreen.kt`
- 关键改动：删除 `scheduleRetry`，在事件监听器内联重试逻辑并始终 `execId = it` 更新；同时补充 `execId <= 0` 时直接报错（对齐 iOS）。

## 验证方式

- 空密码服务器进入 MUX 导航页，重试 3 次后正确显示错误信息 + 重试按钮。

## 预防措施

- 异步 ID 过滤的事件监听，每次发起新请求都必须同步更新过滤 ID；重构时注意旧 iOS 实现已修过的坑。
