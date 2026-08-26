# Mobile Branding And Server Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply ATTACH branding across HarmonyOS/iOS/Android, improve server-list controls, and persist server edits across app restarts.

**Architecture:** Keep shared list operations in `remote-control-shared`, add serialization helpers that can be tested in common tests, and wire UI state to platform-backed local persistence via Compose Multiplatform expect/actual APIs. Use bundled raster assets for app icon/banner while keeping platform resource conventions.

**Tech Stack:** Kotlin Multiplatform, Compose Multiplatform, HarmonyOS resources, Android resources, iOS asset catalogs, Kotlin common tests.

---

### Task 1: Add persistence serialization tests

**Files:**
- Create: `MobileClient/remote-control-shared/src/commonMain/kotlin/com/attach/mobile/remotecontrol/ServerConfigCodec.kt`
- Create: `MobileClient/remote-control-shared/src/commonTest/kotlin/com/attach/mobile/remotecontrol/ServerConfigCodecTest.kt`

- [x] Add common codec tests that assert server lists encode/decode with passwords, empty lists, and malformed input fallback.
- [x] Run `./gradlew :remote-control-shared:allTests` and confirm the new tests fail before implementation.

### Task 2: Implement server config codec

**Files:**
- Create: `MobileClient/remote-control-shared/src/commonMain/kotlin/com/attach/mobile/remotecontrol/ServerConfigCodec.kt`

- [x] Implement deterministic line-based encoding with percent escaping for string fields and strict numeric parsing for id/port.
- [x] Run `./gradlew :remote-control-shared:testDebugUnitTest` and confirm codec tests pass.

### Task 3: Add platform persistence bridge

**Files:**
- Create: `MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/ServerConfigStore.kt`
- Create: `MobileClient/composeUI/src/androidMain/kotlin/com/attach/mobile/ui/ServerConfigStore.android.kt`
- Create: `MobileClient/composeUI/src/iosMain/kotlin/com/attach/mobile/ui/ServerConfigStore.ios.kt`
- Create: `MobileClient/composeUI/src/ohosMain/kotlin/com/attach/mobile/ui/ServerConfigStore.ohos.kt`
- Modify: `MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/App.kt`

- [x] Add `expect object ServerConfigStore` with `load()` and `save(encoded)`.
- [x] Implement Android with `SharedPreferences`, iOS with `NSUserDefaults`, and HarmonyOS with a small app-local file.
- [x] Update `AttachApp` to load once from store and save after add/edit/copy/delete.

### Task 4: Update UI controls and banner

**Files:**
- Modify: `MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/App.kt`
- Add: `MobileClient/composeUI/src/commonMain/composeResources/drawable/attach_banner.png`

- [x] Import Compose resources and show the banner image instead of the `Attach` title.
- [x] Replace text action buttons with larger classic icons: plus, pencil, copy, trash.
- [x] Adjust the add button size and alignment so `+` is visually centered and the circle is smaller.

### Task 5: Update platform app names and icons

**Files:**
- Modify: `MobileClient/harmonyApp/AppScope/resources/base/element/string.json`
- Modify/Add: HarmonyOS media icon resources under `MobileClient/harmonyApp/AppScope/resources/base/media/` and `MobileClient/harmonyApp/entry/src/main/resources/base/media/`
- Modify: `MobileClient/androidApp/src/androidMain/res/values/strings.xml`
- Add/Modify: Android drawable/mipmap icon resources under `MobileClient/androidApp/src/androidMain/res/`
- Modify/Add: iOS asset catalog entries under `MobileClient/iosApp/iosApp/Assets.xcassets/`

- [x] Set display name strings to `ATTACH`.
- [x] Copy provided icon image into each platform resource location.
- [x] Ensure existing manifests continue to reference valid icon names.

### Task 6: Verify and document

**Files:**
- Create: `docs/memory/features/2026-07-08-mobile-branding-persistence.md`

- [x] Run focused tests/build commands available locally.
- [x] Record implementation decisions and verification evidence in memory docs.
