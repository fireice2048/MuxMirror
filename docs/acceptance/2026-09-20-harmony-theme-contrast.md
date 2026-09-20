# 鸿蒙 App 深色系统主题下全页面对比度验收

## 验收环境

- 日期：2026-09-20
- 设备：HUAWEI Pura 70（真机）
- 系统主题：深色
- 构建：Release，`entry-default-signed.hap`
- 安装方式：`hdc install -r`，保留应用数据

## 结果

通过。固定浅色业务页面不再继承深色系统主题的白色前景；固定深色终端页面保持原有高对比配色。

## 逐屏检查

1. 首页：通过。背景、标题、服务器信息为浅色界面配色；新增、网络诊断和设置入口可辨认。证据：[01-home.jpeg](evidence/harmony/2026-09-20-theme-contrast/01-home.jpeg)。
2. 新增服务器：通过。标题、标签、占位文字、端口默认值和按钮均清晰。证据：[02-add-dialog.jpeg](evidence/harmony/2026-09-20-theme-contrast/02-add-dialog.jpeg)。
3. 设置页：通过。左上角关闭按钮、标题、选项及选中标记均清晰。证据：[03-settings.jpeg](evidence/harmony/2026-09-20-theme-contrast/03-settings.jpeg)。
4. 连接失败态：通过。错误信息和返回入口在浅色背景上清晰。证据：[04-terminal.jpeg](evidence/harmony/2026-09-20-theme-contrast/04-terminal.jpeg)。
5. SSH 终端：通过。标题栏为中性深色文字，终端画布和底部工具栏保持高对比度。证据：[05-terminal-connected.jpeg](evidence/harmony/2026-09-20-theme-contrast/05-terminal-connected.jpeg)。
6. MUX 导航：通过。关闭按钮、标题、目录和会话信息在浅色背景上清晰。证据：[06-mux-nav.jpeg](evidence/harmony/2026-09-20-theme-contrast/06-mux-nav.jpeg)。
7. 网络诊断：通过。黑底绿字、返回按钮、输入框占位提示和发送按钮均清晰。证据：[07-network-diag.jpeg](evidence/harmony/2026-09-20-theme-contrast/07-network-diag.jpeg)。
8. 编辑服务器：通过。已有输入值、密码掩码和操作按钮均清晰。证据：[08-edit-dialog.jpeg](evidence/harmony/2026-09-20-theme-contrast/08-edit-dialog.jpeg)。
9. 删除确认：通过。系统深色弹框的标题、内容、取消和危险操作均清晰。证据：[09-delete-dialog.jpeg](evidence/harmony/2026-09-20-theme-contrast/09-delete-dialog.jpeg)。
10. 复制确认：通过。系统深色弹框的说明与操作入口均清晰。证据：[10-copy-dialog.jpeg](evidence/harmony/2026-09-20-theme-contrast/10-copy-dialog.jpeg)。

## 验证命令

```sh
cd MobileApp/harmonyApp
devecocli build --build-mode release
hdc -t 3XQ0224A11020136 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 3XQ0224A11020136 shell aa start -a EntryAbility -b com.attach.mobile.harmony
```

## 已知限制

- 本次通过真机截图确认视觉可见性和明显的对比度风险，没有使用色度计或自动化工具声明完整 WCAG 合规。
- `TerminalNavPanel` 当前没有直接挂载到可达页面，仅完成代码静态检查；实际可达的 MUX 导航页已真机验收。
