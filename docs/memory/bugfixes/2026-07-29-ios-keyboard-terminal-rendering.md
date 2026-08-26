# BugFix 记忆：iOS 软键盘与终端彩色排版

## 现象

- 触发条件：iPhone 17 Pro 模拟器进入服务器新增/编辑页或已连接终端页。
- 用户影响：普通输入框和终端无法稳定弹出系统软键盘；终端输出始终是默认绿色，ANSI 原生颜色丢失；输出更新时偶发滚动位置和行列排版混乱。

## 根因

- iOS 的 Rust 事件解析虽然声明了 `styles`，但 `parseEvent` 将其固定赋值为空数组，丢弃了 Rust 上报的 ANSI 前景色、背景色、反色和弱化区间。
- iOS 恢复 ANSI 默认前景色时仍固定使用品牌浅绿 `#B7F7C1`，Rust 的 ANSI
  16 色也使用通用调色板；电脑端实际使用 macOS Terminal `Clear Dark`，
  默认文字为 `#E5E5E5`、背景为 `#212733`，所以 `tab-8` 即使已经出现多种
  颜色，整体仍明显偏绿。
- 终端控制器在 `viewDidAppear` 中占用第一响应者接收硬件键盘，切换隐藏 `UITextField` 时没有先释放响应者，也没有处理视图尚未进入窗口的情况。
- 终端正文使用不可滚动 `UITextView` 嵌套 `UIScrollView`，更新后却修改内层文本视图的滚动偏移；尺寸计算还额外扣除了两列，造成 PTY 尺寸、排版宽度和实际滚动容器不一致。
- 更关键的是 Rust `AltScreen` 只保存 PTY 行数、没有保存列数。远端 tmux 按 PTY 列宽自动换行并移动光标，本地网格却允许行无限向右增长，最后由 iOS TextKit 二次软换行，导致命令重绘残留、状态栏折行和光标错位。固定样本较短，最初的夹具验收没有覆盖这个真实链路问题。
- 普通 SwiftUI 输入页没有显式焦点状态，sheet 展示和字段点击后的焦点恢复不够确定。

## 修复方案

- 涉及模块：`TermirrorCore.swift`、`TerminalTextView.swift`、`TerminalScreen.swift`、`ServerListScreen.swift`、iOS UI 测试。
- 关键改动：
  - 完整解析 Rust 事件中的 UTF-16 `styles` 区间和 ANSI 颜色字段。
  - iOS 显示层采用电脑端 `Clear Dark` 的默认前景/背景色，并把 Rust 通用
    ANSI 16 色映射为该 profile 的实际色值；应用直接发送的 24 位真彩色不做
    映射，保持原始 RGB。
  - 终端软键盘聚焦时先释放控制器第一响应者，再在主线程下一轮让隐藏输入框成为第一响应者；支持点击终端正文唤起、工具条关闭和再次唤起。
  - 改为单一可滚动 `UITextView`，只在接近底部时跟随最新输出，并以真实内容区域计算 PTY 行列。
  - Rust 备用屏同步保存 PTY `cols/rows`，在最右列实现延迟自动换行；resize 时同步裁剪越界单元格，光标移动和中文宽字符均受真实列宽约束。
  - 服务器编辑页增加 `FocusState`，新增页默认聚焦名称字段。
  - 增加不依赖 SSH 登录的终端 UI 验收入口，固定覆盖中英文、前景色、背景色、反色、弱化和软键盘切换。

## 验证方式

- 复现步骤：
  1. 在 iPhone 17 Pro 模拟器打开新增服务器页，点击名称输入框。
  2. 打开终端验收入口，点击终端正文，再使用底部键盘按钮关闭和重新打开软键盘。
  3. 检查红、绿、蓝、反色、弱化样本，以及中英文行列是否稳定。
- 验证命令：
  - `xcodebuild -project Termirror.xcodeproj -scheme Termirror -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - `xcodebuild -project Termirror.xcodeproj -scheme Termirror -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- 验证结果：
  - Rust 终端模块 38 项测试通过，其中新增 PTY 列宽自动换行和缩列裁剪回归。
  - 7 个 iOS UI 测试全部通过。
  - 使用模拟器已有 `M5 Pro` 配置进入真实 SSH/tmux，会话内执行 ANSI 红/绿/蓝和中文样本：软键盘可由工具栏唤起，颜色保留；修复前命令回显重复且 tmux 状态栏折为两行，修复后命令仅保留一份且状态栏保持单行。
  - 再次进入真实 `tab-8` 截图验证：普通正文恢复为 `#E5E5E5`，背景为
    `#212733`，tmux 状态栏 ANSI green 映射为 `#6CAA70`，Codex 输出的蓝、
    红、紫、绿等 24 位颜色与原始 ANSI 一致。
  - 首次执行 `build-ios.sh` 时三个架构静态库和 XCFramework 已生成，但脚本随后在 cbindgen 阶段因稳定版 Rust 不支持 `-Zunpretty=expanded` 返回失败；已参照 OHOS 构建流程用 `RUSTC_BOOTSTRAP=1` 运行 cbindgen，并将备用头文件失败降级为非阻断警告。

## 预防措施

- 新增 Rust 事件字段时，各平台桥接层不得使用静态默认值吞掉字段，应补解析和平台 UI 回归样本。
- 终端的 PTY 尺寸、文本布局和滚动必须由同一个真实显示容器计算，避免嵌套滚动视图分别维护状态。
- 软键盘测试不能只断言系统 `Keyboard` 元素存在；键盘收起后该元素仍可能存在，
  但 `frame.minY` 等于屏幕高度。必须同时断言键盘高度大于 100 点，且
  `frame.minY < app.frame.maxY - 100`，并保留屏幕截图。
- Simulator 的 `ConnectHardwareKeyboard=false` 写入偏好后，已运行的 Simulator
  进程可能仍沿用旧状态，表现为原生 SwiftUI `TextField` 和终端输入框的键盘都
  停在屏幕下方。需要完整退出并重新启动 Simulator（无需清设备数据），再用
  原生输入框做对照；不要把模拟器状态误判为业务控件问题。
- 终端验收不能只使用短文本固定夹具；必须至少进入一次真实 tmux/rmux，会话状态栏应填满接近整行，以覆盖 PTY 自动换行和光标重绘。
