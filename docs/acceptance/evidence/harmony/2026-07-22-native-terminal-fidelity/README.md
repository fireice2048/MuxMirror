# 鸿蒙原生终端修复验收证据

设备：HarmonyOS 模拟器 `Pura 90 Pro New`（`127.0.0.1:5555`）  
安装包：`entry-default-signed.hap`，覆盖安装并保留应用数据。

## 截图说明

- `04-typed-fixed.jpeg`：英文 `echo abc` 一次正确落入终端，输入法候选栏没有残留组词串。
- `06-backspace-screen-fixed.jpeg`：连续两次退格后，命令行和执行结果均为 `echo axy` / `axy`。
- `07-seq-bottom.jpeg`：输出 100 行后终端稳定停在底部，无多余横线行。
- `08-scrolled-up.jpeg`：手势上滑后可查看第 46 行起的历史。
- `09-no-autojump.jpeg`：停留在历史位置时发送新输出，画面仍保持第 46 行起，没有自动跳底。
- `10-return-bottom.jpeg`：主动滑回底部后显示新输出 `NEW_BOTTOM`，恢复底部跟随。
- `11-dim-placeholder.jpeg`：备用屏 `Place Holder` 使用弱化灰色，终端背景保持深色。
- `12-chinese-preview.jpeg`：中文输入法拼音 `ni'hao` 只在终端光标处预显示，候选词仍留在输入法面板。
- `13-chinese-preview-cleared.jpeg`：逐字退格取消预编辑后远端提示符保持为空，证明预编辑未提前发送。

## 非截图验证

- Rust 单元测试覆盖 emoji 的 UTF-16 光标偏移、空白行/行尾空格光标、弱化样式区间、备用屏历史和主屏退格回显。
- 输入实现以 `onChange.previewText` 仅更新本地预编辑文字，以 `onDidInsert` 转发确认文字；预编辑期间隐藏光标后同一行的 PlaceHolder。
