# 功能记忆：鸿蒙 EventSignal 通信工具

## 背景

- 需求来源：为鸿蒙 ArkTS App 补充与 iOS `EventSignal.swift` 类似的对象级一对多通信能力。
- 使用场景：同一 ArkTS 线程内，业务对象需要向多个订阅者发送类型安全事件，或者保存并回放最新状态值。

## 关键功能点

- `EventSignal<T>`：不保存历史的一对多泛型事件。
- `CurrentValueEventSignal<T>`：保存最新值，新订阅者同步收到最新值。
- `EventSignalCancellable`：幂等取消单个订阅。
- `EventSignalCancellableSet`：强引用保存、批量取消并清空订阅。
- Signal 弱持有订阅者，避免长生命周期 Signal 永久持有页面回调。
- 发送使用稳定快照，支持回调中新增或取消订阅。
- 单个回调抛出异常时记录错误，不中断其他订阅者。

## 设计与实现

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/utilities/communication/EventSignal.ets`。
- 当前值保存在 `CurrentValueEventSignal` 本身，`send` 先更新值再广播，避免新订阅者收到过期初始值。
- 每个 Signal 拥有独立注册表，避免不同属性或不同实例共享同一个 Subject。
- 可空事件使用 `EventSignal<T | null>`，不保留为 Objective-C 兼容而设计的 Nullable 子类。
- 不实现自定义 `@Published`；UI 状态使用 ArkUI 原生装饰器。
- `TermirrorCore.tmEventSignal` 作为 Rust/NAPI 事件的统一生产者；原有 `addEventListener/removeEventListener` 暂由兼容包装转接到同一 Signal。
- `TerminalPage` 和 `NetworkDiagPage` 直接订阅 `tmEventSignal`，在页面出现时保存到 `EventSignalCancellableSet`，离开时统一取消。

## 重要约束

- `send` 与回调在调用线程同步执行，不自动切换 UI 线程。
- 不支持 TaskPool/Worker 跨线程传递；跨线程必须使用 HarmonyOS `Emitter`。
- 调用方必须强引用订阅令牌，推荐使用 `.into(EventSignalCancellableSet)`。
- ArkTS GC 没有 Swift `deinit` 的确定性语义，页面或业务结束时应主动调用 `cancelAll()`。

## 验证方式

- 命令：

  ```sh
  cd MobileApp/harmonyApp
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
    test --mode module -p module=entry@default -p product=default -p buildMode=debug
  devecocli build --build-mode debug
  ```

- 结果：Hypium 共运行 14 项测试，14 项通过；Debug HAP 构建成功。
- EventSignal 测试覆盖一对多、幂等取消、批量取消、最新值回放、静默重置、实例隔离、重入新增、重入取消和异常隔离。
- 兼容层测试覆盖旧监听 API 的订阅、派发和移除。
- Pura 90 Pro 模拟器安装签名 HAP 后，网络诊断页执行 `tcp 127.0.0.1 22`，异步失败结果经 `tmEventSignal` 正常显示，完成真实事件链路验收。

## 后续注意事项

- 只有出现明确的对象级多订阅者需求时才接入，不应替代简单直接回调。
- 如果未来需要操作符链、完成事件、错误通道或背压，应重新评估独立响应式库，不在本工具上无边界扩展。
- 若线程模型发生变化，应优先在调用边界切换到 UI 线程，不要默默改变 `EventSignal.send` 的同步契约。
