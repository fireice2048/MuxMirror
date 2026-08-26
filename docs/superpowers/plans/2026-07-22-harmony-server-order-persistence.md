# 鸿蒙服务器顺序持久化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使 ArkUI 原生拖动排序后的服务器顺序立即写入 `servers.yaml`，App 重启后保持。

**Architecture:** `ServerListPage` 只上报起止索引，`Index` 更新页面状态并调用 ArkTS 薄封装。Rust 配置存储校验索引、移动数组元素并落盘；NAPI/C ABI 只新增透传接口。

**Tech Stack:** Rust、serde_yaml、手写 HarmonyOS NAPI、ArkTS/ArkUI `ForEach.onMove`。

---

### Task 1: Rust 配置顺序移动

**Files:**
- Modify: `MobileApp/shared/src/config/mod.rs`

- [x] **Step 1: 先写失败测试**

在现有配置测试模块新增用例，保存“甲/乙/丙”后调用期望接口：

```rust
move_item(0, 2).unwrap();
assert_eq!(names(), vec!["乙", "丙", "甲"]);
init(&dir).unwrap();
assert_eq!(names(), vec!["乙", "丙", "甲"]);
assert!(move_item(3, 0).is_err());
```

- [x] **Step 2: 确认测试因接口缺失而失败**

Run: `cd MobileApp/shared && cargo test config::tests::移动配置后持久化顺序 -- --exact`

Expected: FAIL，提示找不到 `move_item`。

- [x] **Step 3: 实现最小移动逻辑**

```rust
pub fn move_item(from: usize, to: usize) -> Result<(), String> {
    let mut guard = store()?;
    if from >= guard.servers.len() || to >= guard.servers.len() {
        return Err(format!("配置排序索引越界：from={from}, to={to}"));
    }
    if from == to {
        return Ok(());
    }
    let original = guard.servers.clone();
    let profile = guard.servers.remove(from);
    guard.servers.insert(to, profile);
    if let Err(error) = persist(&guard) {
        guard.servers = original;
        return Err(error);
    }
    Ok(())
}
```

- [x] **Step 4: 运行聚焦测试和配置模块测试**

Run: `cd MobileApp/shared && cargo test config::tests`

Expected: PASS，配置模块全部测试通过。

- [x] **Step 5: 提交 Rust 顺序持久化**

```bash
git add MobileApp/shared/src/config/mod.rs
git commit -m 'feat(core): 持久化服务器排序'
```

### Task 2: 扩展 FFI 与 ArkTS 薄封装

**Files:**
- Modify: `MobileApp/shared/src/ffi/mod.rs`
- Modify: `MobileApp/shared/src/ffi/napi.rs`
- Modify: `MobileApp/shared/ffi/include/termirror_core.h`
- Modify: `MobileApp/harmonyApp/entry/src/main/cpp/types/libtermirror_core/index.d.ts`
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets`

- [x] **Step 1: 新增共用 core 接口**

```rust
pub fn core_config_move(from: u32, to: u32) -> bool {
    crate::config::move_item(from as usize, to as usize).map_err(|e| {
        crate::tm_e!("配置排序保存失败：{e}");
    }).is_ok()
}
```

`core_config_move` 仅透传 Task 1 已经红绿验证的 `move_item`，不重复为薄封装增加全局存储测试。

- [x] **Step 2: 新增 C ABI 与 NAPI `tmConfigMove(from, to): boolean`**

C ABI 返回 `bool`；NAPI 用 `napi_get_boolean` 创建返回值，并把 `tmConfigMove` 加入 `EXPORTS`。运行 `MobileApp/shared/scripts/gen-header.sh` 更新头文件。

- [x] **Step 3: 新增 ArkTS 声明和薄封装**

```typescript
export const tmConfigMove: (from: number, to: number) => boolean;

export function moveConfig(from: number, to: number): boolean {
  if (!isNativeReady()) {
    const item = mockServers.splice(from, 1)[0];
    mockServers.splice(to, 0, item);
    return true;
  }
  return termirrorCore.tmConfigMove(from, to);
}
```

Mock 路径同样校验索引，越界返回 `false`。

- [x] **Step 4: 运行 Rust 全量测试与主机构建**

Run: `cd MobileApp/shared && cargo test && cargo build`

Expected: PASS，无测试失败或编译错误。

- [x] **Step 5: 提交 FFI 与薄封装**

```bash
git add MobileApp/shared/src/ffi MobileApp/shared/ffi/include/termirror_core.h MobileApp/harmonyApp/entry/src/main/cpp/types/libtermirror_core/index.d.ts MobileApp/harmonyApp/entry/src/main/ets/core/TermirrorCore.ets
git commit -m 'feat(ffi): 新增服务器排序接口'
```

### Task 3: ArkUI 拖动排序与验收

**Files:**
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/pages/ServerListPage.ets`
- Modify: `MobileApp/harmonyApp/entry/src/main/ets/pages/Index.ets`
- Modify: `docs/requirements/termirror-mobileapp-progress.md`

- [x] **Step 1: 接入 ArkUI 原生拖动排序**

`ServerListPage` 新增 `onReorder` 回调，在 `ForEach` 上调用 API 12 起支持的单参数 `onMove`，直接使用 ArkUI 原生浮起跟手和落位效果。

- [x] **Step 2: 由 `Index` 更新状态并持久化**

```typescript
private reorderServers(from: number, to: number): void {
  const reordered = this.servers.slice();
  const moved = reordered.splice(from, 1)[0];
  reordered.splice(to, 0, moved);
  this.servers = reordered;
  if (!moveConfig(from, to)) {
    this.reloadServers();
  }
}
```

- [x] **Step 3: 更新进度文档**

在 M3 下记录长按拖动、浮起反馈和 YAML 顺序持久化已完成。

- [x] **Step 4: 构建与人工验收**

Run: `cd MobileApp/shared && bash scripts/build-ohos.sh`

Run: `cd MobileApp/harmonyApp && devecocli build`

Expected: 双 ABI Rust 产物和 signed HAP 构建成功。安装后验证长按浮起、拖动落位、重启保持顺序。

- [x] **Step 5: 提交 ArkUI 功能与进度更新**

```bash
git add MobileApp/harmonyApp/entry/src/main/ets/pages docs/requirements/termirror-mobileapp-progress.md
git commit -m 'feat(harmony): 支持拖动调整服务器顺序'
```
