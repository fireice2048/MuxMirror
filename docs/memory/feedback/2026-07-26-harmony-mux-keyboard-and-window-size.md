# BugFix 记忆：导航终端键盘失效与 MUX 窗口被缩小

## 现象

- 触发条件：先进入普通 SSH 终端，再经“导航”进入 tmux/rmux 终端。
- 用户影响：导航后的键盘按钮无法弹出软键盘，部分工具条按键表现为失效；手机 attach 后共享 MUX 窗口会缩成手机尺寸，电脑端历史内容随重排丢失。

## 根因

- `Index.ets` 使用 Stack 保留普通终端页和 MUX 终端页，两个 `TerminalNativeView` 曾共用固定焦点 ID `tmHiddenInput`。导航后代码聚焦可能命中已隐藏页面的输入框，当前页面的 IME client 没有建立。
- 手机端 attach 使用普通客户端参与 tmux/rmux 窗口尺寸计算，手机较小的 PTY 会改写共享窗口尺寸。

## 修复方案

- 涉及模块：`TerminalNativeView.ets`、`TerminalDisplayContract.ets`、`TerminalPage.ets`。
- 隐藏输入框焦点 ID 改为 `tmHiddenInput-<sessionId>`，工具条、终端点击和发送后重新聚焦均使用当前会话 ID。
- 键盘请求前清理陈旧焦点，临时允许代码聚焦拉起键盘；请求超时后释放页面请求态，允许再次点击重试。
- tmux/rmux attach 统一使用 `attach-session -f ignore-size -t <session>`。

## 验证方式

- 模拟器按“服务器终端 → 导航 → TMUX[muxapp]”进入第二个终端，键盘按钮可反复弹出和收起，日志无 `input method client detached`。
- 导航终端中 CTRL 锁定态可切换；工具条输入 `:` 后，电脑端 `tmux capture-pane` 同步出现字符，随后已清理测试输入。
- `tmux list-clients -t muxapp` 显示手机客户端为 `43x37 ... ignore-size`，电脑客户端保持 `128x40`；共享窗口保持约 `128x39`，没有缩成手机尺寸。
- `devecocli build --build-mode debug` 构建通过。

## 预防措施

- Stack 中可能并存的可聚焦组件禁止使用固定全局 ID，应按页面实例或会话生成唯一 ID。
- 新增多客户端 MUX 接入时，必须同时检查客户端 flags、共享 window size 和电脑端历史，而不能只验证 attach 成功。
