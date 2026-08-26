# BugFix 记忆：鸿蒙终端物理键盘焦点与触摸滚动

## 现象

- 触发条件：刚进入终端，软键盘尚未弹出时点击终端并使用电脑物理键盘；或在历史输出上用手指拖动。
- 用户影响：物理键盘没有输入，必须先弹出一次软键盘；手指无法稳定上下翻屏。

## 根因

- 修复滚动时删除了终端容器的点击聚焦，隐藏 `TextInput` 初始没有焦点。
- 首次修复把点击绑定到内部 `Text`，但短内容时文本只占顶部几行，点击黑色空白区仍不会触发。
- 文本的 `copyOption(CopyOptions.InApp)` 启用了选择交互，会与终端纵向拖动竞争。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`。
- 关键改动：在覆盖整个终端区的既有 `Scroll` 上轻点聚焦隐藏输入框；设置 `enableKeyboardOnFocus(false)`；移除终端文本框选复制，保留工具条粘贴。

## 2026-07-22 软键盘拉起补充

- 现象：先点终端区让隐藏输入框获得焦点，再点工具条键盘按钮时，需要点多次才弹出软键盘。
- 根因：工具条点击逻辑如果直接把 `showTextInput()` 接在 `requestFocus()` 后面，隐藏输入框还没真正拿到焦点时就会先尝试弹键盘，第一次点击容易落空；而单纯依赖 `onFocus` 又会在“已经聚焦”时吃掉后续点击。
- 修复：在组件内显式维护隐藏输入框焦点状态；按钮点击时若已经聚焦，直接 `showTextInput(RequestKeyboardReason.TOUCH)`，未聚焦时只请求焦点，等 `onFocus` 真正到来再弹。

## 验证方式

- 复现步骤：进入 ProbeServer，点击终端空白区，用 `uinput -K` 输入 `echo PHYSICAL_OK`；执行 `seq 1 100` 后在内容区拖动；点击工具条键盘图标。
- 验证命令：`devecocli build clean`、`devecocli build --build-mode debug`、`hdc -t 127.0.0.1:5555 install -r entry-default-signed.hap`。
- 验证结果：隐藏输入框获焦且软键盘可显式弹出；物理键盘命令成功执行；触摸拖动成功翻到更早行；工具条在“已聚焦”和“未聚焦”两种状态下都能一次点按拉起软键盘。

## 预防措施

- 终端点击聚焦必须覆盖整个可视区，不能绑定到高度随内容变化的文本节点。
- 滚动容器内新增点击或选择交互后，必须同时用短内容空白区和长内容拖动做现场验收。
