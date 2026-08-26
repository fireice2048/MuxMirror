#!/usr/bin/env bash
# TermMirror Rust 核心 → HarmonyOS 交叉编译脚本
#
# 同时构建 arm64（真机）与 x86_64（模拟器）两个 target 的 release cdylib：
#   target/<triple>/release/libtermirror_core.so
#
# SSH 库说明：
#   ssh2 crate 底层 libssh2-sys 通过 pkg-config 定位预编译的
#   libssh2.a + libmbedcrypto.a（产物来自
#   scripts/build-ssh-dependencies.sh，
#   描述文件见 pkgconfig/<abi>/libssh2.pc，按 ABI 分目录）。
#   若产物缺失，请先运行：
#     bash scripts/build-ssh-dependencies.sh
#
# OpenSSL 说明：
#   libssh2-sys 在 unix 下强制依赖 openssl-sys，但 OHOS 预编译 libssh2
#   使用 mbedTLS 后端，不需要任何 OpenSSL 符号。这里用
#   third_party/openssl-stub 的头文件桩让 openssl-sys 版本探测通过，
#   并用 OPENSSL_LIBS="" 禁止它发出 -lssl/-lcrypto 链接指令。
set -euo pipefail
cd "$(dirname "$0")/.."

# HarmonyOS NDK 根目录；可通过环境变量覆盖，便于不同安装路径 / CI
NDK="${HARMONY_NATIVE_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"

# 让 libssh2-sys 走 pkg-config 而不是 vendored（vendored 会拉 OpenSSL，OHOS 下不可行）
export LIBSSH2_SYS_USE_PKG_CONFIG=1
# pkg-config 默认拒绝交叉编译场景，需要显式放行
export PKG_CONFIG_ALLOW_CROSS=1
# 使用本工程自带的 pkg-config 包装脚本，避免依赖系统 pkg-config
export PKG_CONFIG="$PWD/scripts/pkg-config-ohos.sh"
# openssl-sys：只用桩头文件做版本探测，不链接任何 OpenSSL 库
export OPENSSL_LIBS=""
export OPENSSL_INCLUDE_DIR="$PWD/third_party/openssl-stub/include"
export OPENSSL_LIB_DIR="$PWD/third_party/openssl-stub/lib"

for pair in "aarch64-unknown-linux-ohos:arm64-v8a" "x86_64-unknown-linux-ohos:x86_64"; do
  target="${pair%%:*}"
  abi="${pair##*:}"
  export PKG_CONFIG_PATH="$PWD/pkgconfig/$abi"

  # cc-rs 交叉编译 OHOS C 依赖所需工具链
  if [ "$target" = "aarch64-unknown-linux-ohos" ]; then
    export CC="$NDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
    export CXX="$NDK/llvm/bin/aarch64-unknown-linux-ohos-clang++"
  else
    export CC="$NDK/llvm/bin/x86_64-unknown-linux-ohos-clang"
    export CXX="$NDK/llvm/bin/x86_64-unknown-linux-ohos-clang++"
  fi
  export AR="$NDK/llvm/bin/llvm-ar"
  export RANLIB="$NDK/llvm/bin/llvm-ranlib"

  echo "==> 构建 $target ($abi)"
  cargo build --release --target "$target"
done

# 生成 C ABI 头文件（Android/iOS 备用；cbindgen 未安装时跳过，不影响构建）
# 注意两点：
# 1. cbindgen 会对宿主 target 跑 `cargo rustc -Zunpretty=expanded`，必须清掉上面的
#    交叉编译环境变量，否则宿主构建会因 OHOS 工具链污染而失败；
# 2. -Zunpretty 需要 nightly 特性，用 RUSTC_BOOTSTRAP=1 让 stable 接受；
#    该步骤仅为生成备用头文件，失败不阻断 OHOS 部署。
if command -v cbindgen >/dev/null 2>&1; then
  env -u CC -u CXX -u AR -u RANLIB \
      -u PKG_CONFIG -u PKG_CONFIG_PATH -u PKG_CONFIG_ALLOW_CROSS \
      -u LIBSSH2_SYS_USE_PKG_CONFIG \
      -u OPENSSL_LIBS -u OPENSSL_INCLUDE_DIR -u OPENSSL_LIB_DIR \
      RUSTC_BOOTSTRAP=1 \
      cbindgen --config cbindgen.toml --crate termirror_core --output ffi/include/termirror_core.h \
      && echo "==> 已生成 ffi/include/termirror_core.h" \
      || echo "警告：cbindgen 头文件生成失败（不影响 OHOS 构建），继续部署"
fi

echo "==> 构建完成，产物："
find target -name "libtermirror_core.so" -path "*ohos*"
