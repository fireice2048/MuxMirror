# BugFix 记忆：同名编辑服务器后列表显示陈旧数据（ForEach key 陷阱）

## 现象

- 触发条件：在服务器列表页编辑一条已存在的配置（不改名称），保存后列表仍显示旧的用户名/地址；再次打开编辑弹窗看到的也是旧数据；点击连接用的也是旧密码，表现为"修改不了数据""改了密码还是登不上"。
- 用户影响：编辑功能看起来完全失效，且 SSH 连接持续使用旧凭据导致认证失败。

## 根因

- `ServerListPage.ets` 的 `ForEach(this.servers, builder, key)` 用 `server.name` 作 key。同名编辑后 `reloadServers()` 产生新数组新对象，但 key 不变，ArkUI ForEach 复用旧 ListItem 组件，item builder 闭包里捕获的还是旧 server 对象。
- 数据链路本身没问题：`saveConfig` → Rust `save_json` 同名覆盖并落盘均正常（hilog 有 `saveConfig OK`，`servers.yaml` 内容正确）。陈旧的是 UI 层：列表显示、回传给 `onEdit`/`onOpen` 的对象全是旧引用。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/pages/ServerListPage.ets`
- 关键改动：ForEach key 改为包含全部可变字段：`${server.name}\n${server.username}\n${server.host}\n${server.port}\n${server.password}`。任何字段变化都会生成新 key，强制重建列表项。
- 注意 password 必须包含在 key 里：密码不直接显示，但列表项闭包要把 server 对象传回 `onEdit`/`onOpen`，key 不含密码会导致改密码后拿到的仍是旧对象。

## 验证方式

- 复现步骤：编辑已有服务器（只改用户名或密码）→ 保存 → 观察列表。
- 验证命令：`hdc shell uitest dumpLayout` / 截图看列表文本；`hdc shell cat .../haps/entry/files/servers.yaml` 对磁盘数据。
- 验证结果：修复前列表显示 `test@10.0.2.2` 而 yaml 已是 `medie`；修复后编辑 medie→medie2 保存，列表立即显示 `medie2@10.0.2.2:22`，改回 medie 同样即时生效，yaml 与 UI 一致。

## 预防措施

- ArkUI ForEach 的 key 必须覆盖"会影响渲染或会被闭包回传"的全部字段，不能只拿稳定标识（如 name/id）当 key；等价于 React key 误用。
- 排查"编辑不生效"类问题先分清数据层还是 UI 层：查落盘文件 + hilog 保存日志，若磁盘已更新而界面没变，就是 UI 刷新问题。
- 同类隐患：`MuxNavPage`/`TerminalNavPanel` 的 key 为 `mux:session:index`，每次打开重新拉取，暂不受影响，改动时注意。
