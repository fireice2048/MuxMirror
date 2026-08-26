# HarmonyOS App 显示名称统一为 MuxMirror

## 背景

电脑端窗口枚举工具和安装命令已经使用 `muxmirror`。移动端当前仍以
`TermMirror` 作为桌面图标和 EntryAbility 的显示名称，用户看到的产品名称
不一致。

## 目标

- HarmonyOS 桌面图标、最近任务及系统页面中的用户可见 App 名称统一为
  `MuxMirror`。
- 保留现有 bundle ID `com.attach.mobile.harmony`，确保覆盖安装时保留服务器
  配置、凭据和其他应用数据。
- 不在本次变更中重命名 Rust crate、NAPI 库、源码目录或内部日志 TAG。

## 验收标准

1. 清理并重新构建签名 HAP 成功。
2. 使用签名 HAP 分别覆盖安装到真机和模拟器，不卸载现有 App。
3. 真机和模拟器启动后，系统识别的应用名称均为 `MuxMirror`。
4. 原有服务器配置和应用功能不因显示名称变化而被清空。

## 非目标

- 不修改 bundle ID。
- 不迁移应用数据目录。
- 不进行全仓库内部标识符的品牌重命名。
