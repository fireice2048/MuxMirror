#!/usr/bin/env bash
# TermMirror Rust 核心 → iOS 交叉编译脚本
#
# 构建真机（arm64）与模拟器（arm64-sim / x86_64）的 release 静态库，
# 可选合并为 universal static library 到 build/ios/universal/libtermirror_core.a。
#
# 使用 vendored-openssl 特性静态编译 OpenSSL + libssh2，不依赖 iOS 系统 libssh2。
set -euo pipefail
cd "$(dirname "$0")/.."

FEATURES="vendored-openssl"

# iOS 16 为 SwiftUI 最低目标；提高部署目标可规避 __chkstk_darwin 等低版本 linker 符号缺失。
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

declare -a TARGETS=(
  "aarch64-apple-ios"
  "aarch64-apple-ios-sim"
  "x86_64-apple-ios"
)

for target in "${TARGETS[@]}"; do
  echo "==> 构建 $target"
  rustup target add "$target" 2>/dev/null || true
  cargo build --release --target "$target" --features "$FEATURES"
done

# 合并真机 + 模拟器为 XCFramework。
# M1 模拟器（arm64-sim）与 x86_64 模拟器属于同一平台不同架构，先 lipo 合并；
# 真机 arm64 单独一库，最终组成 XCFramework。
OUTPUT="build/ios"
mkdir -p "$OUTPUT"

DEVICE_A="target/aarch64-apple-ios/release/libtermirror_core.a"
SIM_ARM_A="target/aarch64-apple-ios-sim/release/libtermirror_core.a"
SIM_X86_A="target/x86_64-apple-ios/release/libtermirror_core.a"
SIM_FAT_A="$OUTPUT/libtermirror_core_sim.a"
XCFRAMEWORK="$OUTPUT/TermirrorCore.xcframework"

if [[ -f "$SIM_ARM_A" && -f "$SIM_X86_A" ]]; then
  echo "==> 合并模拟器 fat 库 $SIM_FAT_A"
  lipo -create "$SIM_ARM_A" "$SIM_X86_A" -output "$SIM_FAT_A"
fi

if [[ -f "$DEVICE_A" && -f "$SIM_FAT_A" ]]; then
  rm -rf "$XCFRAMEWORK"
  echo "==> 创建 XCFramework $XCFRAMEWORK"
  xcodebuild -create-xcframework \
    -library "$DEVICE_A" -headers ffi/include \
    -library "$SIM_FAT_A" -headers ffi/include \
    -output "$XCFRAMEWORK"
fi

if command -v cbindgen >/dev/null 2>&1; then
  RUSTC_BOOTSTRAP=1 \
    cbindgen --config cbindgen.toml --crate termirror_core --output ffi/include/termirror_core.h \
    && echo "==> 已生成 ffi/include/termirror_core.h" \
    || echo "警告：cbindgen 头文件生成失败（不影响 iOS 静态库与 XCFramework），继续"
fi

echo "==> 构建完成，产物："
find target -name "libtermirror_core.a" -path "*apple-ios*"
[[ -d "$XCFRAMEWORK" ]] && echo "$XCFRAMEWORK"
