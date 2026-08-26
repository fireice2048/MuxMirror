#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SHARED_DIR="$REPO_ROOT/MobileApp/shared"
ANDROID_DIR="$REPO_ROOT/MobileApp/androidApp"
IOS_DIR="$REPO_ROOT/MobileApp/iosApp"

usage() {
  printf '用法: %s <ios|android|all> [sim|device]\n' "$(basename "$0")"
  printf '  ios     - 编译并运行 iOS 应用到模拟器\n'
  printf '  android - 编译并运行 Android 应用\n'
  printf '  all     - 编译并运行两端\n'
  exit 1
}

build_rust_android() {
  if [ -f "$SHARED_DIR/target/aarch64-linux-android/release/libtermirror_core.so" ]; then
    printf '==> Rust 核心 (Android) 已存在，跳过构建\n'
    return 0
  fi
  printf '==> 构建 Rust 核心 (Android)\n'
  cd "$SHARED_DIR"
  bash scripts/build-android.sh || true
  [ -f "$SHARED_DIR/target/aarch64-linux-android/release/libtermirror_core.so" ] || {
    printf '错误：Android Rust 核心构建失败\n' >&2
    exit 1
  }
}

build_rust_ios() {
  if [ -d "$SHARED_DIR/build/ios/TermirrorCore.xcframework" ]; then
    printf '==> Rust 核心 (iOS) 已存在，跳过构建\n'
    return 0
  fi
  printf '==> 构建 Rust 核心 (iOS)\n'
  cd "$SHARED_DIR"
  # build-ios.sh 可能因 uniffi binding 生成失败而返回非零，但 XCFramework 可能已生成
  bash scripts/build-ios.sh || true
  [ -d "$SHARED_DIR/build/ios/TermirrorCore.xcframework" ] || {
    printf '错误：iOS XCFramework 构建失败\n' >&2
    exit 1
  }
}

build_android() {
  printf '==> 构建 Android APK\n'
  cd "$ANDROID_DIR"
  ./gradlew :app:assembleDebug
  printf 'APK: %s\n' "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
}

run_android() {
  printf '==> 安装并启动 Android 应用\n'
  adb devices | grep -q "device$" || {
    printf '==> 尝试启动模拟器\n'
    AVD_LIST=$(~/Library/Android/sdk/emulator/emulator -list-avds 2>/dev/null | head -1)
    [ -z "$AVD_LIST" ] && { printf '错误：未找到 Android 模拟器 AVD\n' >&2; exit 1; }
    nohup ~/Library/Android/sdk/emulator/emulator -avd "$AVD_LIST" -gpu swiftshader_indirect -no-window -no-audio > /tmp/emulator.log 2>&1 &
    printf '等待模拟器启动...\n'
    for i in $(seq 1 30); do
      adb devices | grep -q "device$" && break
      sleep 2
    done
  }
  adb devices | grep -q "device$" || {
    printf '错误：未检测到 Android 设备/模拟器\n' >&2
    exit 1
  }
  APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
  adb install -r "$APK"
  adb shell am start -n com.termirror.mobile.android/.MainActivity
  printf 'Android 应用已启动\n'
}

build_ios() {
  printf '==> 构建 iOS 应用\n'
  cd "$IOS_DIR"
  xcodegen generate
  xcodebuild -project Termirror.xcodeproj -scheme Termirror \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
}

run_ios() {
  printf '==> 安装并启动 iOS 应用\n'
  APP="$IOS_DIR/build/Build/Products/Debug-iphonesimulator/Termirror.app"
  # 查找 DerivedData 中的 .cd 产物
  if [ ! -d "$APP" ]; then
    APP=$(find ~/Library/Developer/Xcode/DerivedData/Termirror-*/Build/Products/Debug-iphonesimulator -name "Termirror.app" -type d 2>/dev/null | head -1)
  fi
  [ -d "$APP" ] || { printf '错误：未找到 Termirror.app\n' >&2; exit 1; }

  xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
  xcrun simctl install "iPhone 17 Pro" "$APP"
  xcrun simctl launch "iPhone 17 Pro" com.termirror.mobile.ios
  printf 'iOS 应用已启动 (iPhone 17 Pro)\n'
}

TARGET="${1:-}"
[ -z "$TARGET" ] && usage

case "$TARGET" in
  ios)
    build_rust_ios
    build_ios
    run_ios
    ;;
  android)
    build_rust_android
    build_android
    run_android
    ;;
  all)
    build_rust_android
    build_rust_ios
    build_android
    build_ios
    run_ios
    run_android
    ;;
  *)
    usage
    ;;
esac
