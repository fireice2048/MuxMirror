# Mobile Client Server List Terminal Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine Attach Mobile into a server-list-first flow with add/edit/copy/delete dialogs, terminal page navigation, keyboard-safe terminal input, and renamed top-level directories.

**Architecture:** Keep server configuration and list mutations in `remote-control-shared` as pure state logic with tests. Keep Compose UI in `composeUI`, with the platform apps still only hosting the shared UI. Rename `Mobile` to `MobileClient` and `PC` to `PCServer`, updating workspace and documentation references together.

**Tech Stack:** Kotlin Multiplatform, Compose Multiplatform CPF Beta, Material3, DevEco/Hvigor, Cargo workspace.

---

### Task 1: Shared server state

**Files:**
- Create: `MobileClient/remote-control-shared/src/commonMain/kotlin/com/attach/mobile/remotecontrol/ServerConfig.kt`
- Create: `MobileClient/remote-control-shared/src/commonTest/kotlin/com/attach/mobile/remotecontrol/ServerConfigTest.kt`

- [x] **Step 1: Write server state tests**

Cover creating a server, updating by id, copying with a new id/name suffix, deleting by id, and preserving list order.

- [x] **Step 2: Implement server state helpers**

Add pure functions used by Compose UI dialogs and list actions.

- [x] **Step 3: Run focused tests**

Run: `cd Mobile && gradle --no-configuration-cache :remote-control-shared:testDebugUnitTest`

Expected: terminal input tests and server state tests pass.

### Task 2: Compose list and terminal flow

**Files:**
- Modify: `MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/App.kt`

- [x] **Step 1: Replace grouped home layout**

Remove `默认分组` and terminal preview from the home page.

- [x] **Step 2: Add add/edit dialog**

Use a shared dialog for address, port, username, and password. `+` opens an empty form; edit opens a populated form.

- [x] **Step 3: Add item copy/delete actions**

Copy creates a new item from the selected server with a new id and copy suffix. Delete shows a confirmation dialog before removal.

- [x] **Step 4: Add terminal page navigation**

Clicking a list item simulates a successful connection and animates to a terminal page. Terminal page hosts the work area, shortcut row, prompt input, and `↵` button.

- [x] **Step 5: Fix button visuals and keyboard padding**

Keep button containers compact while centering larger glyphs. Apply IME padding to the terminal input area.

### Task 3: Rename directories

**Files:**
- Rename: `MobileClient/` -> `MobileClient/`
- Rename: `PCServer/` -> `PCServer/`
- Modify: `Cargo.toml`
- Modify: `README.md`, `AGENTS.md`, docs under `docs/`

- [ ] **Step 1: Move directories**

Deferred until the server-list terminal flow is stable, because the rename creates broad path churn across Rust, Gradle, Harmony, and docs.

Use `mv Mobile MobileClient` and `mv PC PCServer`, preserving ignored build outputs as ignored.

- [ ] **Step 2: Update code and doc references**

Replace path references and build commands from `Mobile`/`PC` to `MobileClient`/`PCServer`.

### Task 4: Verify builds and run

**Files:**
- Existing project files

- [ ] **Step 1: Run PC tests**

Run: `cargo test`

Expected: PC server tests pass under renamed workspace path.

- [x] **Step 2: Run mobile shared tests**

Run: `cd MobileClient && gradle --no-configuration-cache :remote-control-shared:testDebugUnitTest`

Expected: shared tests pass.

- [x] **Step 3: Build Android and iOS artifacts**

Run Android debug and iOS simulator framework link.

Expected: both compile.

- [ ] **Step 4: Publish Harmony binaries and run**

Run Harmony publish, then `devecocli run` on the connected Pura 70 with local signing binding.

Expected: app installs, launches, and logs show Compose controller created.

Status: `ohosArm64` shared library and unsigned Harmony HAP build pass. Real-device install is blocked by missing `signingConfigs` for `com.attach.mobile.harmony`; temporary local signing material was not kept in the repo.
