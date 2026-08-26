# 鸿蒙 EventSignal 通信工具

## 背景

鸿蒙 ArkTS 侧目前主要依赖组件内 `@State` 和直接回调传递状态，缺少一个用于对象级业务事件的一对多、类型安全通信工具。现有 ArkUI 状态管理、`EventHub`、`Emitter` 与 Promise 分别面向 UI 状态、Ability 通信、跨线程事件和单次异步结果，无法完整覆盖局部对象内的多订阅者事件流。

本工具参考 iOS `EventSignal.swift` 的使用语义，以及 ArkCombine 1.2.0 的 Subject、当前值和订阅持有设计，但不直接引入第三方依赖。

## 目标

1. 提供泛型 `EventSignal<T>`，支持一个发送方对应多个订阅者。
2. 提供 `CurrentValueEventSignal<T>`，始终保存最新值，新订阅者立即收到最新值。
3. 提供幂等的单订阅取消能力和可批量取消、可清空的订阅集合。
4. 订阅回调相互隔离：单个回调抛出异常时，其他订阅者仍可收到事件。
5. 明确定义重入行为，发送期间新增或取消订阅不会破坏当前遍历。
6. 使用 ArkTS 泛型保留编译期类型安全；可空事件直接使用 `T | null`，不增加单独的 Nullable 类型。
7. 补充单元测试与开发文档，覆盖核心行为和历史实现中发现的易错点。
8. 选择少量真实业务场景试点接入，验证生产者、页面生命周期订阅和兼容迁移方式。

## 平台与线程约束

- 工具运行于创建它的 ArkTS 线程，`send` 和回调均为同步执行。
- 工具不承担 TaskPool、Worker 等跨线程通信；跨线程场景使用 HarmonyOS 官方 `Emitter`。
- UI 状态仍优先使用 ArkUI `@State`、`@ObservedV2`、`@Trace`、`@Monitor`，不实现自定义 `@Published`。
- 回调需要由调用方确保不会阻塞当前线程。

## 关键 API

```text
EventSignal<T>
  on(callback) -> EventSignalCancellable
  send(value)
  subscriberCount

CurrentValueEventSignal<T>
  value
  on(callback) -> EventSignalCancellable
  send(value)
  resetCurrentValue(value)

EventSignalCancellable
  cancel()
  isCancelled
  into(cancellableSet)

EventSignalCancellableSet
  insert(cancellable)
  cancelAll()
  count
```

订阅令牌必须由调用方强引用保存，通常通过 `into(EventSignalCancellableSet)` 保存。Signal 仅弱持有订阅者，避免全局或长生命周期 Signal 永久持有页面回调。

## 关键行为

- `send` 使用订阅快照；发送期间新增的普通订阅者不接收当前事件。
- 发送期间被取消且尚未执行的订阅者不再接收当前事件。
- `CurrentValueEventSignal.send` 先更新当前值，再通知订阅者。
- `CurrentValueEventSignal.on` 同步发送当前值。
- `resetCurrentValue` 只更新当前值，不发送事件。
- `cancel` 与 `cancelAll` 可重复调用。
- `cancelAll` 必须清空集合，不保留已取消令牌。

## 代表性接入

1. 将 `TermirrorCore` 的 Rust → UI 全局事件入口改为 `EventSignal<TmEvent>`，由 Signal 负责稳定快照、订阅取消与回调异常隔离。
2. 将 `TerminalPage` 接入为高频、按 `sessionId` 过滤的会话事件订阅代表。
3. 将 `NetworkDiagPage` 接入为低频、按事件类型过滤的页面生命周期订阅代表。
4. 暂时保留 `addEventListener` / `removeEventListener` 兼容包装，未试点页面后续按需迁移，避免本次扩大改动范围。

## 非目标

- 不实现 Combine/Rx 风格的操作符链、背压、完成事件和错误通道。
- 不替代 ArkUI 状态管理。
- 不封装 `EventHub` 或 `Emitter`。
- 不提供跨线程安全保证。
- 不在本次批量迁移所有现有页面。

## 验收标准

- [ ] 鸿蒙工程通过 Debug 构建。
- [ ] 普通信号的一对多发送、取消与批量取消测试通过。
- [ ] 当前值信号的新订阅者能收到最近一次发送值，而非初始值。
- [ ] 两个 Signal 实例的数据与订阅完全隔离。
- [ ] 回调异常、发送期间新增订阅、发送期间取消订阅均有测试。
- [ ] `TermirrorCore` 通过 `EventSignal<TmEvent>` 分发事件。
- [ ] `TerminalPage` 与 `NetworkDiagPage` 使用订阅集合管理页面生命周期。
- [ ] README 和 `docs/memory/` 记录适用范围与线程约束。
