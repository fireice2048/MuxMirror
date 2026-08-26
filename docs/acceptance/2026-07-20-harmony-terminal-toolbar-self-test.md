# 鸿蒙 SSH 终端工具条自测报告

## 结论

2026-07-20 在 Pura 90 Pro、HarmonyOS 7.0.0（API 26）模拟器完成最终回归。首页第一项可直连本机 SSH，工具条 20 个按钮均通过；所有按钮均在系统键盘展开后完成补充测试。键盘按钮默认负责拉起，展开后图标垂直翻转并切换为收起功能。

## 测试环境

- 模拟器：Pura 90 Pro，1256 × 2760，HDC `127.0.0.1:5555`。
- SSH：`medie@10.0.2.2:22`，连接成功后显示远端 zsh 提示符。
- 包：`MobileClient/harmonyApp/entry/build/default/outputs/default/entry-default-signed.hap`。

## 功能自测

| 分组 | 按钮 | 验证方法与结果 |
| --- | --- | --- |
| 符号 | `/ - : * \|` | 逐个点击，按当前光标位置组成输入内容，全部通过。 |
| 行内编辑 | `HOME END ← → DEL` | 对中间光标文本执行行首、行尾、左右移动及向后删除，光标和内容符合预期。 |
| 历史 | `↑ ↓` | `↑` 调出 `echo histmark`；空本地缓冲按 Enter 能执行远端历史；`↓` 返回当前空命令。 |
| 翻页 | `PGUP PGDN` | 执行 `seq 1 100` 后向上翻到 67–83，再向下回到 84–100 和提示符。 |
| 控制字符 | `ESC TAB` | 在 `cat -v` 中验证 Escape 显示为 `^[`，Tab 可随输入发送。 |
| 修饰键 | `CTRL ALT` | 锁定态有明确高亮；`CTRL+C` 中断 `cat` 并返回提示符；`ALT+x` 在 `cat -v` 中显示为 `^[x`。 |
| 粘贴 | `PAST/粘贴` | 使用鸿蒙 `PasteButton` 临时授权读取系统剪贴板，`MacBook Pro` 正确插入当前光标处。 |
| 键盘 | `⏏` | 初始不自动弹出；首次点击拉起；图标垂直翻转；再次点击实际收起；连续 3 轮开合和粘贴后收起均通过。 |

## 修复与体验优化

1. 修复工具键远端动作前未同步本地待输入文本，解决历史命令调出后按空输入 Enter 不执行的问题。
2. 补齐 ESC、TAB、方向、Home/End、Delete、PageUp/PageDown、CTRL、ALT 的终端序列与状态行为。
3. 用单一透明输入组件承接软键盘，消除首次点击不弹出及重复焦点组件的问题。
4. 不再进入终端即预聚焦，避免系统键盘自动弹出。
5. 键盘按钮采用本地请求态与鸿蒙输入法桥接；收起时同时清理 Compose 和 ArkUI 根焦点，解决安全粘贴后只翻图标但键盘不收起的问题。
6. 键盘展开时按钮图标按 `scaleY` 从 `1` 动画到 `-1`，清晰表达收起动作。
7. 鸿蒙粘贴改用系统安全控件 `PasteButton`，无需申请受限的长期剪贴板权限，并通过 NAPI 将文本送入 KMM 输入缓冲。

## 截图证据

- `evidence/harmony/2026-07-20-final-terminal-initial-closed.jpeg`：SSH 连接成功且终端初始不自动弹键盘。
- `evidence/harmony/2026-07-20-final-rebuild-keyboard-open.jpeg`：首次点击后键盘展开、工具条贴合键盘、图标垂直翻转。
- `evidence/harmony/2026-07-20-final-rebuild-keyboard-closed.jpeg`：同一按钮实际收起键盘。
- `evidence/harmony/2026-07-20-final-rebuild-paste.jpeg`：键盘展开时系统安全粘贴成功。
- `evidence/harmony/2026-07-20-final-after-paste-keyboard-closed.jpeg`：粘贴后仍可正常收起键盘。
- `evidence/harmony/2026-07-20-final-keyboard-open-symbols.jpeg`：键盘展开时符号键验证。
- `evidence/harmony/2026-07-20-final-keyboard-open-navigation-delete.jpeg`：键盘展开时行内导航与删除验证。
- `evidence/harmony/2026-07-20-final-keyboard-open-history-enter.jpeg`：历史命令回调后空输入 Enter 正确执行。
- `evidence/harmony/2026-07-20-final-keyboard-open-page-up.jpeg`、`evidence/harmony/2026-07-20-final-keyboard-open-page-down.jpeg`：终端输出上下翻页。
- `evidence/harmony/2026-07-20-final-keyboard-open-ctrl-c.jpeg`、`evidence/harmony/2026-07-20-final-keyboard-open-alt-x.jpeg`：CTRL/ALT 实际控制序列。

## 构建与共享库验证

执行：

```sh
cd MobileClient
./gradlew :composeUI:testDebugUnitTest :composeUI:compileKotlinOhosX64
./gradlew :composeUI:publishDebugBinariesToHarmonyApp
cd harmonyApp
devecocli build clean
devecocli build --build-mode debug
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
```

最终结果：Gradle 测试与 OHOS x64 编译成功，Hvigor clean debug 构建成功，signed HAP 覆盖安装成功。HAP 内 `libkn.so` 与本轮构建的 stripped 库逐架构 SHA-256 完全一致：

| 架构 | SHA-256 |
| --- | --- |
| x86_64 | `b60be78f7eafdd9da7c85a2dcb68b6fd8a9074dc62934a78952fc6167be169aa` |
| arm64-v8a | `0938a97359c489719a62364e92855a30652bfd8a269efd04e880180b3fbe7d90` |

signed HAP：`d73a0c8c6d33142da3a063ac918fdd6a77c615efde164bb8e1fd2775b4161b3f`。
