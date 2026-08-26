# Mobile Client Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold Attach Mobile as a KMP + CPF Compose Multiplatform client with shared UI across Android, iOS, and HarmonyOS.

**Architecture:** `remote-control-shared` owns pure common business logic, `composeUI` owns the shared Compose UI and produces platform artifacts, while `androidApp`, `iosApp`, and `harmonyApp` are thin platform entries. HarmonyOS uses CPF-KMP-CMP OHOS targets and DevEco/Hvigor integration.

**Tech Stack:** Kotlin Multiplatform, Compose Multiplatform CPF Beta, Android Gradle Plugin, SwiftUI, DevEco/Hvigor, ArkTS, CMake/NAPI for HarmonyOS bridge.

---

### Task 1: Create shared Gradle workspace

**Files:**
- Create: `MobileClient/settings.gradle.kts`
- Create: `MobileClient/build.gradle.kts`
- Create: `MobileClient/gradle.properties`
- Create: `MobileClient/gradle/libs.versions.toml`

- [x] **Step 1: Add CPF repositories and module includes**

Configure `remote-control-shared`, `composeUI`, and `androidApp` modules under the Mobile Gradle root.

### Task 2: Add remote-control-shared module

**Files:**
- Create: `MobileClient/remote-control-shared/build.gradle.kts`
- Create: `MobileClient/remote-control-shared/src/commonMain/kotlin/com/attach/mobile/remotecontrol/TerminalInput.kt`
- Create: `MobileClient/remote-control-shared/src/commonTest/kotlin/com/attach/mobile/remotecontrol/TerminalInputTest.kt`

- [x] **Step 1: Write newline insertion tests**

Cover empty input, end insertion, middle insertion, and selection replacement.

- [x] **Step 2: Implement minimal input editor**

Add `insertNewline` pure function for shared UI state.

### Task 3: Add shared composeUI module

**Files:**
- Create: `MobileClient/composeUI/build.gradle.kts`
- Create: `MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/App.kt`
- Create: `MobileClient/composeUI/src/androidMain/kotlin/com/attach/mobile/ui/Platform.android.kt`
- Create: `MobileClient/composeUI/src/iosMain/kotlin/com/attach/mobile/ui/MainViewController.kt`
- Create: `MobileClient/composeUI/src/ohosMain/kotlin/com/attach/mobile/ui/MainArkUIViewController.kt`

- [x] **Step 1: Add shared Compose app shell**

Create server list and terminal preview UI, including `↵` newline button behavior.

- [x] **Step 2: Add platform entry exports**

Expose Android composable, iOS `MainViewController`, and HarmonyOS `MainArkUIViewController`.

### Task 4: Add thin app entries

**Files:**
- Create: `MobileClient/androidApp/build.gradle.kts`
- Create: `MobileClient/androidApp/src/main/AndroidManifest.xml`
- Create: `MobileClient/androidApp/src/main/kotlin/com/attach/mobile/android/MainActivity.kt`
- Create: `MobileClient/iosApp/iosApp/ContentView.swift`
- Create: `MobileClient/iosApp/iosApp/iOSApp.swift`
- Create: `MobileClient/harmonyApp/**`

- [x] **Step 1: Add Android entry**

Keep Android app logic to `setContent { AttachApp() }`.

- [x] **Step 2: Add iOS entry**

Keep iOS app logic to `ComposeView().ignoresSafeArea()`.

- [x] **Step 3: Add HarmonyOS entry**

Use CPF sample bridge structure to load shared Compose UI from `composeUI` native output.

### Task 5: Verify builds

**Files:**
- Existing scaffold files

- [x] **Step 1: Run shared tests**

Run: `cd Mobile && gradle :remote-control-shared:testDebugUnitTest`

Expected: newline insertion tests pass.

- [x] **Step 2: Publish Harmony binaries**

Run: `cd Mobile && gradle :composeUI:publishDebugBinariesToHarmonyApp`

Expected: `harmonyApp/entry/libs/*/libkn.so` and headers are copied.

- [x] **Step 3: Build Harmony app**

Run: `cd MobileClient/harmonyApp && devecocli build`

Expected: Hvigor debug build succeeds or reports only signing/device setup blockers.

- [x] **Step 4: Build Android app**

Run: `cd Mobile && gradle :androidApp:assembleDebug`

Expected: Android debug APK compiles.

- [x] **Step 5: Check iOS project generation path**

Run: `cd Mobile && gradle :composeUI:linkDebugFrameworkIosSimulatorArm64`

Expected: iOS simulator framework links.
