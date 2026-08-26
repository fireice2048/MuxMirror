# 需求：终端窗口列表页与标签页导航

## 背景
当前移动端点击服务器列表项后直接进入终端页面（`TerminalScreen`），且终端页目前仅为 UI 占位，未对接真实数据流。
真实使用场景中，电脑端（PCServer）的一个终端程序（如 Terminal.app / iTerm）通常包含多个**窗口（window）**，每个窗口又包含多个**标签页（tab）**。
为让用户在手机上远程查看并操作电脑端已有的终端，需要先把"服务器"下钻为"窗口列表"，再下钻到"标签页终端页"，形成两级导航。

## 目标
1. 点击服务器列表项后，不再直接进入终端页，而是进入**终端窗口列表页**。
2. 窗口列表页中，每一行对应电脑端的一个**终端窗口**；每行上排列若干**按钮**，每个按钮对应窗口内的一个**标签页**。
3. 窗口与标签页数据通过服务端查询接口获取（`list_windows` 返回窗口分组；`list_window_tabs` 返回指定窗口标签页列表）。
4. 点击某个标签页按钮后，进入该标签页对应的**终端页面**，并与服务端进行数据流交互（读取屏幕、发送输入、resize 等）。

## 平台需求
- 涉及端：移动端 `MobileClient`（composeUI 三端共享 UI：Android / iOS / HarmonyOS）。
- 数据来源：电脑端 `PCServer`（`PCServer/attach`），通过既有的 JSON 协议通信。
- 导航层级：`服务器列表` → `终端窗口列表页（某服务器）` → `终端页（某窗口的某标签页）`。

## 关键流程
1. 用户在服务器列表点击某一项（`ServerRow` 的 `onOpen`）。
2. App 向 PCServer 发起查询请求（对应 `list_windows` / `list_window_tabs`），获取该服务器下所有窗口及其标签页。
3. App 渲染窗口列表页：每个窗口一行，行内横向排列该窗口的标签页按钮（按钮文案取标签页标题）。
4. 用户点击某标签页按钮 → 进入 `TerminalScreen(server, windowId, tabId)`。
5. 终端页与 PCServer 建立数据流：`read_screen`、`send_input`、`resize`、`switch_tab` 等。

## 数据模型（预期）
PCServer 通过 `list_windows` 返回按窗口分组的 `Vec<WindowInfo> { window_id, title, tabs: Vec<TabInfo> }`；通过 `list_window_tabs` 可查询单个窗口的标签页列表。
层级数据至少包含：
- 窗口标识（window_id）
- 窗口内标签页列表（tab_id / terminal_id + title）

已确认方案：**新增 `list_windows` 分组查询接口与 `list_window_tabs` 单窗口标签页查询接口**。`WindowInfo { window_id, title, tabs: Vec<TabInfo> }` 直接表达窗口到标签页的层级；PCServer `MacosTerminalAdapter` 已在 Terminal.app / iTerm2 适配器实现 `list_windows()` 与 `list_window_tabs()`。

## 非目标（本期不做）
- 不在手机端**新建**电脑端终端窗口 / 标签页（即不实现远程 `new_tab` / `new_window`）。
- 不实现标签页的关闭 / 重命名 / 拖拽排序（仅查看与进入）。
- 终端页真实 SSH/Attach 连接的完整能力（鉴权、断线重连、PTY 模式处理等）不在本期范围，但需打通基础数据流链路。

## 待澄清问题
1. ~~服务端如何表达"窗口"层级？~~ 已确认：新增 `list_windows` 分组查询接口与 `list_window_tabs` 单窗口接口；`WindowInfo { window_id, title, tabs }` 表达层级，不再保留 `list_tabs` 扁平接口。
2. 终端页进入后是只读（read_screen）还是需要双向输入（send_input）？需求第 4 点写"数据流交互"，默认包含输入。
3. 标签页按钮的展示上限 / 横向滚动策略：单个窗口标签页过多时的 UI 处理。
4. 查询时机：进入窗口列表页时拉取一次，是否需要轮询刷新（标签页动态增删）？
