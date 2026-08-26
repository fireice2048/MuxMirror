# BugFix 记忆：Android 浅色状态栏与 MUX 会话识别

## 现象

- 首页为白色背景时，系统状态栏图标也使用白色，时间、网络和电量看不见。
- MUX 同目录多会话菜单只显示窗口标题时，标题不含 session 名的 `tab-3` 看起来像是丢失了。

## 根因与修复

- 浅色主题没有声明 `windowLightStatusBar=true`；现在浅色/深色主题分别配置状态栏和导航栏图标亮度。
- MUX 菜单项现在固定先显示 `TMUX[session]` 标签，后显示窗口标题。

## 验证

- arm64-v8a Android 模拟器覆盖安装并启动后，首页白色状态栏上的黑色图标可见。
- 展开 `~/Repo/TermHook` 的 3 个会话，菜单依次显示 `TMUX[tab-2]`、`TMUX[tab-4]`、`TMUX[tab-3]`，且后面保留各自标题。
