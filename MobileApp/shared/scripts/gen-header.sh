#!/usr/bin/env bash
# 生成 C ABI 头文件 ffi/include/termirror_core.h（cbindgen）。
# 供 Android（JNI 桥）/ iOS（Swift 互操作）引用；HarmonyOS 走 NAPI 不需要本头文件。
# 依赖：cargo install cbindgen
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v cbindgen >/dev/null 2>&1; then
  echo "未找到 cbindgen，请先执行：cargo install cbindgen" >&2
  exit 1
fi

mkdir -p ffi/include
cbindgen --config cbindgen.toml --crate termirror_core --output ffi/include/termirror_core.h
echo "已生成 ffi/include/termirror_core.h"
