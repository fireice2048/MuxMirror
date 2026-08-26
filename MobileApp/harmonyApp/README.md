# MuxMirror 鸿蒙工程（纯 ArkTS UI）

MuxMirror 移动端「Rust 核心 + 纯 ArkTS UI」方案的鸿蒙壳工程。UI 全部使用 ArkTS 编写，不依赖任何 KMP 产物（旧 KMP 方案 `MobileClient/` 已于 2026-07-21 删除）。

## 工程结构

```
harmonyApp/
├── AppScope/                    # 应用级配置（bundleName、应用名、图标）
├── build-profile.json5          # 工程级构建配置：产品、签名、SDK 版本
├── oh-package.json5             # 工程级依赖（hypium 等开发依赖）
├── hvigorfile.ts / hvigor/      # hvigor 构建入口与配置
└── entry/                       # 主模块（HAP）
    ├── oh-package.json5         # 模块依赖：声明 libtermirror_core.so 本地依赖
    ├── build-profile.json5      # 模块构建配置（release 混淆/符号裁剪）
    ├── libs/
    │   ├── arm64-v8a/           # 真机 Rust .so 放置处（libtermirror_core.so）
    │   └── x86_64/              # 模拟器 Rust .so 放置处
    └── src/main/
        ├── module.json5         # 模块配置：权限（INTERNET/VIBRATE）、deviceTypes、Ability
        ├── cpp/types/libtermirror_core/   # Rust NAPI 的 .d.ts 类型声明（仅声明，无 C++ 桥）
        ├── ets/
        │   ├── entryability/EntryAbility.ets          # 主入口：全屏/系统栏设置，loadContent 首页
        │   ├── entrybackupability/EntryBackupAbility.ets  # 备份恢复扩展
        │   ├── utilities/communication/EventSignal.ets # 同线程、类型安全的一对多业务事件
        │   └── pages/Index.ets                        # 首页占位：调用 Rust tm_add(1,2) 并展示结果
        └── resources/           # 图标、文案、颜色等资源
```

## 构建

```sh
cd MobileApp/harmonyApp
devecocli build --build-mode debug     # 或 release
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（签名配置见本工程 `build-profile.json5` 的 signingConfigs，材料在 `~/.ohos/config`）。

注意：蓝本复用的调试 profile（.p7b）绑定的是旧 bundleName `com.attach.mobile.harmony`，对 `com.termirror.mobile.harmony` 构建会在 `SignHap` 阶段报 `00303074 bundleName 不匹配`。首次构建前需用 DevEco Studio 打开本工程，在 Project Structure > Signing Configs 勾选自动签名（需已登录华为账号），生成绑定新 bundleName 的签名材料后，替换 `build-profile.json5` 中 signingConfigs 的材料路径与口令。骨架其余环节（编译、资源打包、PackageHap、签名动作本身）均已验证通过。

安装到模拟器/设备：

```sh
hdc -t <设备地址> install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <设备地址> shell aa start -a EntryAbility -b com.attach.mobile.harmony
```

本地单元测试使用 DevEco Studio 自带的 Hvigor 执行：

```sh
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  test --mode module -p module=entry@default -p product=default -p buildMode=debug
```

## EventSignal 通信工具

`entry/src/main/ets/utilities/communication/EventSignal.ets` 提供对象级、同一 ArkTS 线程内的类型安全事件通信。它不替代 ArkUI 状态管理，也不用于 TaskPool 或 Worker 跨线程通信。

普通一对多事件：

```typescript
import {
  EventSignal,
  EventSignalCancellableSet
} from './utilities/communication/EventSignal';

const events: EventSignal<string> = new EventSignal<string>();
const cancellables: EventSignalCancellableSet = new EventSignalCancellableSet();

events.on((value: string) => {
  // 回调在 events.send 所在线程同步执行
}).into(cancellables);

events.send('connected');
```

保存最新值的事件：

```typescript
import { CurrentValueEventSignal } from './utilities/communication/EventSignal';

const state: CurrentValueEventSignal<string> =
  new CurrentValueEventSignal<string>('idle');

state.send('connected');
// 此后新订阅者会立即收到 connected
```

使用约束：

- 必须强引用保存订阅令牌，推荐调用 `.into(cancellables)`。
- 页面销毁或业务结束时调用 `cancellables.cancelAll()`。
- 可空事件直接声明为 `EventSignal<Value | null>`。
- 跨线程事件使用 HarmonyOS `Emitter`；UI 状态使用 `@State` 或状态管理 V2。

当前真实接入点是 `TermirrorCore.tmEventSignal`：Rust/NAPI 事件统一通过它派发，
`TerminalPage` 与 `NetworkDiagPage` 使用 `EventSignalCancellableSet` 管理页面生命周期内的订阅。
旧 `addEventListener/removeEventListener` 仅作为未迁移页面的兼容入口保留。

## Rust 核心库接入

Rust 核心由 `MobileApp/shared` 的 `termirror_core` crate 构建，产出 `libtermirror_core.so`（模块名 `termirror_core`，自身导出 `napi_register_module_v1`，无需 C++ shim / CMake 桥）。

更新流程：

1. 在 `MobileApp/shared` 交叉编译出鸿蒙目标的 `libtermirror_core.so`（arm64-v8a 与 x86_64 两个 ABI）。
2. 分别拷贝到 `entry/libs/arm64-v8a/` 与 `entry/libs/x86_64/`。hvigor 默认会把 `entry/libs/<abi>/*.so` 打进 HAP，无需额外配置。
3. 若 NAPI 导出方法有增删，同步更新 `entry/src/main/cpp/types/libtermirror_core/index.d.ts`。
4. ArkTS 侧使用方式：`import termirrorCore from 'libtermirror_core.so'`，如 `termirrorCore.tm_add(1, 2)`。.so 未放入时 import 结果为 `undefined`，调用处需 try/catch 兜底（见 `pages/Index.ets`）。
5. 重新执行 `devecocli build` 并安装验证。

## 全屏 TUI 回看

- 单指纵向滑动始终用于 ArkUI 本地历史滚动。
- Codex 等远端应用通过 DEC 私有模式启用鼠标跟踪后，双指纵向滑动会转换为 xterm 滚轮事件发送到 SSH 会话，由远端应用回看其内部历史。
- 工具栏 `PGUP` / `PGDN` 在鼠标跟踪开启时发送一页量的远端滚轮；普通 Shell 中继续执行本地翻页，不发送键盘 PageUp/PageDown 转义序列。
- 若 Codex 位于 tmux/rmux 内且双指滚动无效，应先在电脑端验证同一会话的鼠标滚轮，并检查 MUX 的鼠标转发配置。

## 权限

- `ohos.permission.INTERNET`：SSH/网络通信。
- `ohos.permission.VIBRATE`：触控反馈。
