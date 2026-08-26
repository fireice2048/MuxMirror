# BugFix 记忆：键盘弹出后 MUX 输入区不可见

## 现象

- 触发条件：手机进入 tmux/rmux 终端后弹出软键盘。
- 用户影响：终端区域被键盘压缩，但输入框不在可见画面内；手势滚动也无法找回输入框。

## 根因

- `ignore-size` 保护了共享 MUX window，不会让电脑端窗口缩成手机尺寸。
- 软键盘弹出时手机仍把自身 PTY 从约 37 行缩到约 19 行，tmux 只向该 client 发送大窗口的裁剪画面。
- 输入区已经不在手机收到的快照中，因此只滚动 ArkUI `Scroll` 无法恢复。
- 后续现场发现还有一个时序漏洞：ArkUI 可能先完成终端区域缩小，稍后才触发
  `keyboardHeightChange`。若 resize 门控只检查 `keyboardVisible`，这段窗口会把
  键盘前的完整行数错误覆盖成缩小后的行数，使原修复偶发失效。
- 另一个独立裁剪来自 `ignore-size` 本身：电脑端共享 window 可能有 51 行，而
  手机 PTY 全高也只有 37 行。手机客户端不再参与 window resize 后，MUX 默认给
  小客户端展示大窗口的顶部区域，底部的 Codex 输入行和 Agent 页脚仍不在快照中。

## 修复方案

- 涉及模块：`TerminalPage.ets`、`TerminalNativeView.ets`。
- MUX 终端记录键盘弹出前的完整 PTY 行数；键盘显示期间不降低该行数，让完整画面继续进入本地终端快照。
- 工具条已经发起键盘显示请求时，将 `keyboardRequestedVisible` 与
  `keyboardVisible` 一并视为键盘活动态，覆盖布局回调早于系统键盘高度回调的竞态。
- attach 前记录 SSH PTY 的 tty；手机客户端注册到 tmux/rmux 后，后台短暂重试
  `refresh-client -D ... 999`，仅将该客户端的大窗口可见区域平移到底部。
  attach 初始化还会在 client 注册后完成窗口选择并重置一次可见区域，因此不能
  第一次 refresh 成功就退出，需要在约 2 秒的初始化窗口内重复下移。
  `ignore-size` 保持不变，因此电脑端 window 不 resize、历史不重排。
- ArkUI 视口高度改变后，若此前正在跟随最新输出，则等待布局稳定再滚动到底部；用户已经上翻历史时不强制抢回。

## 验证方式

- 模拟器进入 `TMUX[muxapp]` 后弹出键盘，`tmux list-clients` 显示手机客户端仍为 `43x37 ... ignore-size`，没有缩为约 19 行。
- 输入框和光标显示在状态栏上方。
- 键盘保持显示时向下拖动画面可查看更早内容，再向上拖动可回到底部输入区。
- 重复收起、弹出键盘，确认布局先缩小时仍保留完整 PTY 行数，Codex 输入行与
  Agent 页脚（运行模式、thinking、目录、分支状态）均可见。
- 对照 `tmux list-clients`：电脑客户端与共享 window 尺寸不变；手机 client
  仍带 `ignore-size`，只改变自身可见区域的纵向偏移。
- `devecocli build --build-mode debug` 构建通过。
- 2026-07-26 模拟器现场复验：TMUX[14] 的电脑 client/window 保持 `146x52`
  （window 51 行），手机保持 `43x37 ignore-size`、纵向偏移 15；软键盘弹出后
  OpenCode 输入框、模型/任务页脚与工作目录仍完整可见。

## 预防措施

- 区分“共享 MUX window 尺寸”“手机客户端 PTY 尺寸”和“ArkUI 可视区域高度”，三者不能简单绑定。
- `ignore-size` 只阻止客户端参与共享尺寸计算，不保证小客户端默认看到大 window
  的底部；TUI 输入区位于底部时还要显式管理该客户端的可见区域。
- 验收键盘避让时必须同时确认输入区可见、历史可滚动以及电脑端窗口尺寸未变化。
