# MUX 导航目录维度分组方案

## 背景

当前 MUX 导航页以「终端窗口」为维度组织标签页：Accessibility 检测到的每个窗口作为一行，窗口内的 tmux/rmux 标签页平铺或折叠展示。实际使用中发现：

1. 同一个 tmux session 可能因窗口标题被改写、`tmux attach` 等原因，未被 Accessibility 识别为某个窗口的标签页，导致出现独立的 `TMUX[191]`、`TMUX[192]` 条目。
2. 用户更关心「当前工作目录」而不是「终端窗口」。多个不同 session 如果都在同一个目录工作，应该在导航页里被当作同一组。
3. 以目录为维度可以减少导航页条目数，让用户更快定位到目标会话。

## 目标

为用户提供可选的 MUX 导航分组方式：

- **按窗口分组（默认）**：保持原有行为，以 Accessibility 检测到的终端窗口为维度组织标签页。
- **按目录分组**：把 MUX 导航页的组织维度改为「工作目录（cwd）」。相同 cwd 的 tmux/rmux session 聚合为一条目录记录；点击目录记录后 attach 到该目录下最合适的 session。

分组方式通过首页右下角的设置入口进入设置页面选择，并持久化到客户端本地。

## 非目标

- 不修改终端页本身的 attach 协议：仍然通过 `mux + session` attach。
- 本期不做智能排序或会话推荐，仅提供分组方式切换。

## CLI 开关

`muxmirror` 新增 `--by-directory` 布尔开关：

```bash
muxmirror -format json --mux --by-directory
```

- 默认不开启，保持原有按窗口输出。
- 开启后，`windows` 数组中的每个元素代表一个目录组，`title` 为该目录路径，`tabs` 为该目录下所有 mux 标签页。
- `detached` 列表保持独立，不参与目录分组。
- 输出结构仍为 `MuxListOutput { windows, detached }`，App 端无需适配新的顶层字段。

## 关键流程

### 按窗口分组（默认）

1. App 调用 `muxmirror -format json --mux` 获取窗口、标签页、cwd、session 信息。
2. 导航页按窗口展示标签页。
3. 一台电脑上的一个终端窗口只能生成一条导航记录；该窗口内的多个标签页必须聚合在同一记录中。
4. 主标题使用 Accessibility 返回的真实窗口标题，不得用 cwd 或 session ID 替换。

### 按目录分组

1. App 调用 `muxmirror -format json --mux --by-directory`，由 `muxmirror` 在服务端按 `cwd` 分组。
2. App 解析 `windows`，每个元素即一个目录组：
   - 标题：目录路径（缩写 `~`）。
   - 副标题：组内 session 名。
   - 选中后 attach 目标：组内 `active=true` 的 session；若无 active，取第一个 session。
   - 多 session 选择列表必须逐项显示 `MUX[session]`，不能只显示可能不含 session 名的终端标题。
   - Android 多 session 弹出菜单应尽量利用屏幕宽度，减少长标题换行；相邻会话之间显示分割线。
   - iOS 多 session 弹出菜单同样应加宽并显示会话分割线；每项固定先显示 `MUX[session]` 标签，再显示标题。
3. detached session 仍作为独立条目放在列表末尾。

### 设置入口

1. 首页右下角提供齿轮按钮，进入设置页面。
2. 设置页提供「标签页分组方式」：按窗口分组 / 按目录分组。
3. 选择后持久化到客户端本地，下次启动仍然生效。
4. 导航页每次查询前读取当前分组方式，决定调用命令是否带 `--by-directory`。

## 平台需求

| 平台 | 实现位置 | 说明 |
|------|----------|------|
| CLI | `MirrorServer/src/main.rs` | 新增 `--by-directory` 开关，服务端按 cwd 分组输出 |
| Android | `MobileApp/androidApp/app/src/main/java/com/termirror/mobile/android/ui/pages/MuxNavScreen.kt` | 根据设置拼接命令；`SettingsStore` + `SettingsScreen` 持久化分组方式；`ServerListScreen` 右下角齿轮入口 |
| iOS | `MobileApp/iosApp/Termirror/UI/Pages/MuxNavScreen.swift` | 根据 `@AppStorage` 拼接命令；`SettingsScreen` + `ServerListScreen` 齿轮入口 |
| HarmonyOS | `MobileApp/harmonyApp/entry/src/main/ets/pages/MuxNavPage.ets` | 根据 `AppStorage` 拼接命令；`SettingsPage` + `ServerListPage` 齿轮入口；`EntryAbility` 初始化偏好到 `AppStorage` |

## 待澄清问题

1. 同一目录下存在多个 session 时，是否需要在目录行右侧提供「更多」入口？还是先默认 attach 到 active session？
   - 初步方案：主点击 attach 到 active/first session；若组内 session 数 >1，右侧显示「N 个会话」按钮，点击弹出选择列表。
2. `cwd` 为空或不可靠时如何 fallback？
   - 初步方案：以窗口标题或 session 名作为分组 key，避免空目录导致全部合并。
3. 中文 cwd 在 JSON 中以 `\xe8...` 转义的问题是否一并修复？
   - 建议：在 `muxmirror` 侧统一修复 cwd 的编码输出，避免三个 App 分别处理。

## 验收标准

1. `muxmirror -format json --mux --by-directory` 可正常输出，条目按目录维度组织。
2. 默认「按窗口分组」时，三端行为与改动前一致。
   - 一个终端窗口对应一条导航记录，窗口内两个标签页显示为该记录的两个会话。
   - 主标题显示真实窗口标题，不显示目录名或 tmux/rmux session ID。
3. 切换为「按目录分组」后：
   - 导航页条目以目录为维度展示。
   - 主标题必须显示目录路径（服务端目录组的 `window.title`），不得显示 tmux/rmux session ID。
   - 同一 tmux/rmux session 即使同时存在电脑、模拟器、真机等多个 attached client，也只能在导航中出现一次。
   - previously-orphan session 与其 cwd 相同的其他 session 合并到同一目录行。
   - 点击目录行能正确 attach 到对应 session（active/first）。
4. 设置项重启 App 后仍保持。
5. 三个平台行为一致。
6. Android 展开同目录的多会话选择列表后，每个 session（包括标题中不含 session 名的条目）都能被明确识别和选择。
7. Android 多会话弹出菜单比默认宽度更宽，且每两个会话项之间都有清晰分割线。
8. iOS 多会话弹窗宽度能容纳标签和标题，会话间有分割线，每项以 `MUX[session]` 标签开头。
