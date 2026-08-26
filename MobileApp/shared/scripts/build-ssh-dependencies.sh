#!/usr/bin/env bash
# 交叉编译 libssh2 + mbedTLS 静态库（HarmonyOS arm64-v8a / x86_64）。
# 产物输出到 MobileApp/shared/build/ohos-ssh/<abi>/，供 pkgconfig/ 下的 .pc 引用。
set -euo pipefail

SHARED_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_HOME="${HARMONY_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
NATIVE_SDK="$SDK_HOME/default/openharmony/native"
CMAKE="$NATIVE_SDK/build-tools/cmake/bin/cmake"
NINJA="$NATIVE_SDK/build-tools/cmake/bin/ninja"
TOOLCHAIN="$NATIVE_SDK/build/cmake/ohos.toolchain.cmake"
MBEDTLS_CONFIG_FLAGS="-Wno-error=unused-command-line-argument -DMBEDTLS_CONFIG_FILE=\\\"mbedtls-ohos-config.h\\\" -I$SHARED_DIR/scripts"

if [[ ! -x "$CMAKE" || ! -x "$NINJA" || ! -f "$TOOLCHAIN" ]]; then
  echo "未找到 HarmonyOS Native SDK，请设置 HARMONY_SDK_HOME" >&2
  exit 1
fi

for ABI in arm64-v8a x86_64; do
  OUTPUT="$SHARED_DIR/build/ohos-ssh/$ABI"
  MBEDTLS_LIB="$OUTPUT/mbedtls/library/libmbedcrypto.a"

  echo "=== [$ABI] 编译 mbedTLS (mbedcrypto) ==="
  "$CMAKE" -S "$SHARED_DIR/third_party/mbedtls" -B "$OUTPUT/mbedtls" \
    -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DOHOS_ARCH="$ABI" -DOHOS_PLATFORM=OHOS \
    -DCMAKE_BUILD_TYPE=Release "-DCMAKE_C_FLAGS=$MBEDTLS_CONFIG_FLAGS" \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF
  "$CMAKE" --build "$OUTPUT/mbedtls" --target mbedcrypto --parallel 4

  echo "=== [$ABI] 编译 libssh2 ==="
  "$CMAKE" -S "$SHARED_DIR/third_party/libssh2" -B "$OUTPUT/libssh2" \
    -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DOHOS_ARCH="$ABI" -DOHOS_PLATFORM=OHOS \
    -DCMAKE_BUILD_TYPE=Release "-DCMAKE_C_FLAGS=$MBEDTLS_CONFIG_FLAGS" \
    -DCRYPTO_BACKEND=mbedTLS \
    -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF \
    -DMBEDTLS_INCLUDE_DIR="$SHARED_DIR/third_party/mbedtls/include" \
    -DMBEDCRYPTO_LIBRARY="$MBEDTLS_LIB" \
    -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
  "$CMAKE" --build "$OUTPUT/libssh2" --target libssh2_static --parallel 4
done

echo "=== 完成 ==="
ls -la "$SHARED_DIR"/build/ohos-ssh/*/libssh2/src/libssh2.a "$SHARED_DIR"/build/ohos-ssh/*/mbedtls/library/libmbedcrypto.a
