# Mobile 终端输入换行按钮

## 背景

用户提供了手机端 tmux 客户端终端页面截图，要求在底部输入提示词时增加一个换行按钮。由于手机软键盘在终端场景中可能将回车用于发送或隐藏键盘，需要明确的 UI 控件插入字面换行。

## 关键结论

- 按钮文案确定为 `↵`，比中文 `换行` 更适合窄屏底部输入栏。
- 点击 `↵` 只在当前输入框光标处插入 `\n`，不触发发送、不执行远端命令。
- 当前仓库的 `MobileClient/` 仅有 KMP + Compose 占位文档，尚无可修改的移动端 UI 源码，因此本次先记录需求、验收标准和 README 入口。

## 影响范围

- `MobileClient/README.md` 增加终端输入栏 `↵` 能力说明。
- `docs/requirements/2026-07-08-mobile-terminal-newline-button.md` 固化产品需求。
- `docs/acceptance/mobile-terminal-newline-button.md` 固化人工验收场景。

## 验证方式

- 使用 `rg -n "↵|newline|换行" MobileClient/README.md docs/requirements docs/acceptance docs/memory/features/2026-07-08-mobile-terminal-newline-button.md` 检查文档入口和关键行为描述。
- 后续 Mobile UI 实现完成后，按 `docs/acceptance/mobile-terminal-newline-button.md` 进行人工验收。
