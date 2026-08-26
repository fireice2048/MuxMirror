# 鸿蒙终端交互补充修复验收证据

- `01-launch.jpeg`：签名 HAP 覆盖安装后应用稳定启动，服务器配置保留。
- `02-terminal-icon.jpeg`：终端页使用指定的绿色键盘图标。
- `03-keyboard-open.jpeg`：点击工具条按钮可拉起软键盘。
- `04-keyboard-reopen.jpeg`：收起后再次点击仍可拉起软键盘。
- `05-scroll-bottom.jpeg`：输出 1～100 后位于底部。
- `06-scroll-up.jpeg`：触摸滑动后可查看历史行。
- `07-no-autojump.jpeg`：停留在历史位置时新增输出不会强制跳到底部。
- `08-full-line.jpeg`：`tput cols` 为 45，输出 45 个横线保持单行，下一行没有横线残留。

光标保存恢复由 Rust 回归测试 `备用屏_csi保存恢复光标` 覆盖：`CSI s` 后写入占位文本，再执行 `CSI u`，光标必须恢复到已有输入末尾。
