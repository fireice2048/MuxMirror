# BugFix 记忆：MUX 多 client 导致导航重复和目录标题退化

## 现象

- 触发条件：电脑、鸿蒙模拟器和鸿蒙真机同时 attach 到同一个 tmux session（例如 `tab-14`），真机重新进入导航页。
- 用户影响：同一个 session 在按窗口和按目录模式下重复出现；按目录模式的主标题可能显示 `tab-14`，而不是工作目录。

## 根因

- `muxmirror` 通过 `tmux list-clients` 收集数据，但每个 client 都生成一个 `MuxSession`，没有按 `mux + session` 去重。
- 手机 client 的 TTY 无法通过 macOS 本机进程表获得 CWD，导致重复记录的 `cwd` 为空；目录分组逻辑随后用 session ID 作为 fallback key 和标题。
- 鸿蒙客户端即使收到服务端 `--by-directory` 结果，仍重新按 `tab.cwd` 分组，没有优先采用目录组的 `window.title`。
- Terminal.app 标签标题中的 attach 命令使用 `-t =tab-14`，但 `detect_mux` 只解析创建会话的 `-s` 参数，导致两个真实标签页无法匹配 session。后续 orphan 补偿把它们各自生成独立伪窗口，窗口标题也退化成 cwd。
- 鸿蒙 `MuxNavPage` 通过 `Visibility.Hidden` 保留在 Stack 中；同一服务器再次进入导航时不会触发 `aboutToAppear` 或 server Watch，导致继续显示分组切换前或窗口变化前的缓存结果。

## 修复方案

- 涉及模块：`MirrorServer/src/main.rs`、`MobileApp/harmonyApp/entry/src/main/ets/pages/MuxNavPage.ets`。
- 关键改动：
  - `muxmirror` 按 session 去重 attached clients，并优先读取 tmux/rmux 的 `pane_current_path` 作为 CWD。
  - `detect_mux` 同时解析 `-s` / `-t`，并标准化 tmux 精确目标的前导 `=`，保留 AX 原始窗口及其标签页分组。
  - 鸿蒙导航解析增加 `mux + session` 去重，兼容尚未升级或异常的电脑端输出。
  - 目录模式优先使用服务端目录组的 `window.title`，确保主标题显示目录。
  - `Index` 每次进入/返回导航时递增刷新令牌，保留的 `MuxNavPage` 收到后重新读取分组设置并查询 `muxmirror`。

## 验证方式

- 复现步骤：保持电脑、模拟器、真机同时 attach `tab-14`，真机分别选择按窗口、按目录并重新进入导航。
- 验证命令：`cargo test -p muxmirror`；重装本机 `muxmirror`；重新构建并覆盖安装鸿蒙 signed HAP；通过真机 UI layout 和截图确认。
- 验证结果：
  - `cargo test -p muxmirror` 7 项通过，`cargo clippy -p muxmirror --all-targets --all-features` 无新增错误（保留 2 项既有结构警告）。
  - 新版 `muxmirror` 安装到 SSH 实际命中的 `~/.local/bin` 后，三个 `tab-14` client 在 JSON 中收敛为一个 session；`--by-directory` 只输出一个 `~/Repo/TermHook` 目录组，组内为 `tab-13`、`tab-14`。
  - 鸿蒙 clean build、signed HAP 覆盖安装成功。Pura 70 真机按目录导航只显示一条 `~/Repo/TermHook` 主标题；展开“2 个会话”菜单后恰好显示 `TMUX[tab-13]` 与 `TMUX[tab-14]`，`tab-14` 仅出现一次。
  - 按窗口模式下，Terminal.app 的一个窗口聚合两个标签页，只生成一条导航记录；主标题使用真实窗口标题，不再退化为目录名。

## 预防措施

- MUX 导航的数据实体是 session，不是 client；任何从 `list-clients` 构造的列表都必须按 `mux + session` 唯一化。
- 服务端目录组的标题是目录事实来源，客户端不得用 session ID 覆盖非空的目录标题。
