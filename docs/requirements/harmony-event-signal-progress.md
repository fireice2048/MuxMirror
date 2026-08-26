# 鸿蒙 EventSignal 通信工具进度

参考：`docs/requirements/2026-07-28-harmony-event-signal.md`

## 任务清单

- [x] 调研 iOS `EventSignal.swift`、ArkCombine 1.2.0 与 HarmonyOS 原生通信能力
- [x] 明确工具范围、线程模型和生命周期语义
- [x] 输出需求与进度文档
- [x] 实现 `EventSignal<T>` 与 `CurrentValueEventSignal<T>`
- [x] 实现订阅取消与订阅集合
- [x] 补充单元测试
- [x] 更新鸿蒙 README 与功能记忆
- [x] 通过单元测试和 Debug 构建
- [x] 明确真实业务试点接入范围
- [x] 将 `TermirrorCore` 事件总线切换为 `EventSignal<TmEvent>`
- [x] 将 `TerminalPage` 与 `NetworkDiagPage` 切换为订阅集合生命周期
- [x] 完成试点接入后的测试、Debug 构建与模拟器运行验收

## 设计结论

- 只覆盖对象级、同线程、类型安全的一对多事件。
- 不实现 `@Published`，UI 状态继续使用 ArkUI 原生状态管理。
- 不实现跨线程派发，TaskPool/Worker 场景继续使用官方 `Emitter`。
- Signal 弱持有订阅者，调用方必须保存订阅令牌。
- 当前值必须保存在 Subject 本身，确保后创建的订阅者收到最近值。
- 先迁移一个全局事件生产者和两个典型页面订阅者；其他调用方通过兼容包装继续工作。

## 验证结果

- `devecocli build --build-mode debug`：成功生成签名 Debug HAP。
- Hvigor 本地测试：`Tests run: 14, Failure: 0, Error: 0, Pass: 14`。
- 新增 9 项 EventSignal 行为测试，覆盖广播、取消、批量清理、当前值、实例隔离、重入和异常隔离。
- 新增 1 项 `TermirrorCore` 兼容层测试，确认旧监听 API 与 `tmEventSignal` 共用同一事件源且取消有效。
- 测试基础设施补充 `entry/src/test/List.test.ets` 入口。
- 签名 HAP 已安装到 Pura 90 Pro 模拟器；网络诊断命令 `tcp 127.0.0.1 22` 的异步结果成功经 `tmEventSignal` 回填页面。
