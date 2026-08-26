# 开发进度：终端窗口列表页与标签页导航

> 关联需求：docs/requirements/2026-07-09-terminal-window-list.md
> 起始：2026-07-09

## 阶段一：数据模型与协议对齐
- [x] 确认 PCServer 窗口/标签页数据表达方式（方案 A：新增 list_windows 分组接口 + list_window_tabs 单窗口接口，移除 list_tabs 扁平接口）
- [x] PCServer 协议层：新增 WindowInfo、ListWindows / Windows、ListWindowTabs / WindowTabs、capability；移除 ListTabs / Tabs
- [x] PCServer macos_terminal：TerminalApp / Iterm2 适配器实现 list_windows / list_window_tabs（按窗口分组）
- [x] PCServer service 分发 ListWindows / ListWindowTabs（mac/非 mac 双实现）
- [x] PCServer CLI 新增 `list-windows <session-id>` 与 `list-window-tabs <session-id> <window-id>` 子命令；移除 `list-tabs`
- [x] App `remote-control-shared` 定义数据模型 TerminalTab / TerminalWindow / TerminalWindowList
- [ ] **新建 App 端终端通信 client**（当前 AttachApp 无任何网络连接层，需先建 client 才能查询/数据流）
- [x] 单元测试与集成测试覆盖 list_windows / list_window_tabs 路径

## 阶段二：App 导航改造（点击列表项 → 窗口列表页）
- [x] 新增 `TerminalWindowListScreen` 页面（Mock 数据驱动）
- [x] 修改 `AttachApp` 状态机：ServerList → WindowList(加载中) → WindowList → Terminal(tab)
- [x] 点击列表项 `onOpen` → 进入窗口列表页（通过 `MockTerminalClient.listWindows`）
- [x] `TerminalScreen` 改造为接收 `server/window/tab`，头部显示窗口与标签页标题

## 阶段三：窗口列表页 UI
- [x] 每行对应一个终端窗口（WindowRow）
- [x] 行内横向滚动排列标签页按钮（TabButton，文案取标题）
- [x] 空状态 / 加载中处理
- [x] 标签页过多时的横向滚动（horizontalScroll）

## 阶段四：标签页 → 终端页真实数据流（TCP/JSON）
- [x] 确认 PCServer 传输格式：TCP 短连接，请求=AuthenticatedRequest{token,request} JSON+\n，响应=一行 JSON+\n
- [x] 手写极简 JSON 工具（kotlinx-serialization 未发布 ohos 变体，故零依赖实现，见 JsonUtil.kt）
- [x] common 定义 `TcpConnection` expect 接口 + Android(java.net)/native(POSIX) actual
- [x] 实现 `TcpTerminalClient`：Hello 探活、Register 拿 session_id、ListWindows、ReadScreen、SendInput、Resize、SwitchTab
- [x] `ServerConfig` 增加 `token` 字段承载鉴权
- [x] `AttachApp` 切换到真实 `TcpTerminalClient`；窗口列表页改为真实拉取
- [x] `TerminalScreen` 接通 read_screen 轮询(400ms) + send_input + resize
- [x] commonTest 验证 JSON 解析/请求构造正确
- [ ] 本机/真机联调：需在真实 macOS 终端运行 `attach track` 得到 tracked session；模拟器跨设备连通需端口转发/同网段（环境配置留后续）

## 阶段五：联调与验证
- [ ] 编译三端（Android / iOS / HarmonyOS）
- [ ] 真机/模拟器联调 PCServer 验证两级导航与数据流
- [ ] 更新 README / AGENTS 文档（如架构变化）
