#!/usr/bin/env bash
# TermMirror Rust 核心 → Android 交叉编译脚本
#
# 同时构建 arm64（真机）、armv7、x86_64 / x86（模拟器）四个 target 的 release 库：
#   target/<triple>/release/libtermirror_core.so
#
# 使用 vendored-openssl 特性静态编译 OpenSSL + libssh2，不依赖 Android 系统 SSL 库。
set -euo pipefail
cd "$(dirname "$0")/.."

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK_DIR="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk}"
# 取最新版本 NDK
NDK_VERSION="${ANDROID_NDK_VERSION:-$(ls -1 "$NDK_DIR" 2>/dev/null | sort -V | tail -1)}"
NDK="$NDK_DIR/$NDK_VERSION"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"

if [[ ! -d "$TOOLCHAIN" ]]; then
  echo "未找到 Android NDK toolchain: $TOOLCHAIN" >&2
  echo "请设置 ANDROID_HOME / ANDROID_NDK_HOME / ANDROID_NDK_VERSION 环境变量" >&2
  exit 1
fi

HOST_TAG="darwin-x86_64"
BIN="$TOOLCHAIN/bin"

# 使用 Bash 3.2 也支持的索引数组（macOS 系统 Bash 不支持关联数组）。
# 每项格式：<target>|<NDK 前缀>
TARGETS=(
  "aarch64-linux-android|aarch64-linux-android"
  "armv7-linux-androideabi|armv7a-linux-androideabi"
  "x86_64-linux-android|x86_64-linux-android"
  "i686-linux-android|i686-linux-android"
)

API="${ANDROID_API:-24}"
FEATURES="vendored-openssl"

for target_config in "${TARGETS[@]}"; do
  target="${target_config%%|*}"
  prefix="${target_config#*|}"
  echo "==> 构建 $target (API $API)"

  export CC="$BIN/${prefix}${API}-clang"
  export CXX="$BIN/${prefix}${API}-clang++"
  export AR="$BIN/llvm-ar"
  export RANLIB="$BIN/llvm-ranlib"
  export LINKER="$CC"
  export CARGO_TARGET_$(echo "$target" | tr '[:lower:]-' '[:upper:]_')_LINKER="$LINKER"

  rustup target add "$target" 2>/dev/null || true
  cargo build --release --target "$target" --features "$FEATURES"
done

# cbindgen 需要在 macOS 宿主环境中解析 crate，不能继承最后一个 Android target 的编译器。
unset CC CXX AR RANLIB LINKER

# 生成 C ABI 头文件（iOS / Android 桥接使用）
if command -v cbindgen >/dev/null 2>&1; then
  RUSTC_BOOTSTRAP=1 \
    cbindgen --config cbindgen.toml --crate termirror_core --output ffi/include/termirror_core.h \
    && echo "==> 已生成 ffi/include/termirror_core.h" \
    || echo "警告：cbindgen 头文件生成失败（不影响 Android 动态库），继续"
fi

echo "==> 构建完成，产物："
find target -name "libtermirror_core.so" \( -path "*android*" -o -path "*linux-android*" \)
