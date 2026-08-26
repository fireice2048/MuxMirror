# 鸿蒙终端物理键盘焦点与滚动验收证据

- `01-launch.jpeg`：签名 HAP 覆盖安装后应用稳定启动，原服务器配置保留。
- `02-terminal.jpeg`：进入 ProbeServer 后软键盘保持收起。
- `03-physical-keyboard.jpeg`：点击终端空白区后，物理键盘成功执行 `echo PHYSICAL_OK`，软键盘未弹出；布局树同时确认 `tmHiddenInput` 为 `focused=true`。
- `04-scroll-bottom.jpeg`：执行 `seq 1 100` 后位于输出底部。
- `05-scroll-up.jpeg`：在终端内容区向下拖动后，从 63～92 翻到 42～71。
- `06-soft-keyboard.jpeg`：点击工具条键盘图标后软键盘正常弹出，当前历史位置仍保留。

验收设备：HarmonyOS 模拟器 `Pura 90 Pro New`，序列号 `127.0.0.1:5555`。
