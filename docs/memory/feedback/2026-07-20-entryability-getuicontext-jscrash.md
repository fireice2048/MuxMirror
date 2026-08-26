# BugFix 记忆：EntryAbility 在 loadContent 完成前调 getUIContext 导致 jscrash

## 现象

- 触发条件：TermMirror 鸿蒙 App（API 24 模拟器 Pura 90 Pro New）启动即闪退，`aa start` 返回成功但进程随后退出、画面停在桌面。
- 用户影响：App 完全无法使用。

## 根因

- `EntryAbility.ets` 的 `onWindowStageCreate` 中，`windowStage.loadContent()` 是异步的；在其回调完成前调用 `windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(...)`，此时窗口 UIContent 为空。
- 崩溃日志（`/data/log/faultlog/faultlogger/jscrash-*.log`）：`Error message: This window state is abnormal.[window][getUIContext]msg: Uicontent is nullptr.`，栈顶 `onWindowStageCreate (EntryAbility.ets:47)`，错误码 1300002。
- 该写法在旧 API 18 模拟器（KMP 蓝本工程）上不崩，API 24 系统严格校验后必现——同类代码升级系统镜像后才暴露。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/entryability/EntryAbility.ets`
- 关键改动：把 `getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)` 移入 `loadContent` 成功回调内，并加 try/catch 兜底。

## 验证方式

- 复现步骤：`devecocli build` → `hdc install -r` → `aa start`，观察 `pidof com.attach.mobile.harmony` 为空且桌面无窗口。
- 验证命令：同上；修复后 `pidof` 有值，服务器列表页正常渲染（截图确认），faultlogger 不再新增 jscrash。
- 验证结果：通过（2026-07-20，Pura 90 Pro New 模拟器）。

## 预防措施

- 凡是依赖窗口 UIContent/UIContext 的调用（setKeyboardAvoidMode、getUIContext().xxx），一律放在 `loadContent` 回调之后执行。
- App 起不来先查 `/data/log/faultlog/faultlogger/` 最新 jscrash，不要只看 `aa start` 的返回。
