#!/usr/bin/env sh
# 一键构建并部署鸿蒙 App 到模拟器或真机（Rust 核心 + ArkTS 架构）
#
# 用法:
#   bash scripts/deploy-harmony.sh sim    # 仅模拟器
#   bash scripts/deploy-harmony.sh device # 仅真机
#   bash scripts/deploy-harmony.sh all    # 模拟器 + 真机（默认）
#
# 流程：交叉编译 Rust .so（双 ABI）→ 拷贝到 entry/libs → 构建 HAP → 安装 → 启动
# 默认模拟器：Pura 90 Pro
# 真机：自动检测 devecocli device list 中 Kind=device 的第一个设备
# 详见根目录 AGENTS.md「鸿蒙 Rust 核心库构建与部署」。
set -eu

TARGET="${1:-all}"
case "$TARGET" in
  sim|device|all) ;;
  *)
    echo "usage: $0 [sim|device|all]" >&2
    exit 1
    ;;
esac

# ---- 路径配置 ----
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="$ROOT/MobileApp/shared"
HARMONY="$ROOT/MobileApp/harmonyApp"
SIM_DEVICE="Pura 90 Pro"

# ---- 1. 交叉编译 Rust 核心（双 ABI）----
echo "==> [1/4] 交叉编译 Rust 核心 .so..."
(cd "$SHARED" && bash scripts/build-ohos.sh)

# ---- 2. 拷贝 .so 到鸿蒙工程 ----
echo "==> [2/4] 拷贝 .so 到 entry/libs..."
cp "$SHARED/target/aarch64-unknown-linux-ohos/release/libtermirror_core.so" "$HARMONY/entry/libs/arm64-v8a/"
cp "$SHARED/target/x86_64-unknown-linux-ohos/release/libtermirror_core.so" "$HARMONY/entry/libs/x86_64/"

# ---- 3. 构建 HAP ----
echo "==> [3/4] 构建 HAP..."
(cd "$HARMONY" && devecocli build clean && devecocli build --build-mode debug)

HAP="$HARMONY/entry/build/default/outputs/default/entry-default-signed.hap"
if [ ! -f "$HAP" ]; then
  UNSIGNED="$HARMONY/entry/build/default/outputs/default/entry-default-unsigned.hap"
  if [ -f "$UNSIGNED" ]; then
    echo "error: 当前工程未配置签名，仅产出未签名 HAP，无法安装到设备/模拟器。" >&2
    echo "请在 DevEco Studio「File → Project Structure → Signing Configs」勾选自动签名后重试（签名材料为本机私有，勿提交）。" >&2
  else
    echo "error: 未找到 HAP: $HAP" >&2
  fi
  exit 1
fi

# ---- 4. 部署 ----
echo "==> [4/4] 部署 App..."

# 真机设备自动检测（取 Kind=device 的第一个 Name）
# devecocli device list 输出为固定宽度表格，按列截取
find_real_device() {
  devecocli device list 2>/dev/null \
    | awk 'NR>2 {
        name = substr($0, 1, 16)
        gsub(/[[:space:]]+$/, "", name)
        kind = substr($0, 35, 10)
        gsub(/[[:space:]]+/, "", kind)
        if (kind == "device" && name != "") {
          print name
          exit
        }
      }'
}

deploy_to() {
  local device="$1"
  echo "--> 部署到: $device"
  (cd "$HARMONY" && devecocli run --device "$device" --skip-build --build-mode debug)
}

case "$TARGET" in
  sim)
    deploy_to "$SIM_DEVICE"
    ;;
  device)
    REAL_DEVICE="$(find_real_device)"
    if [ -z "$REAL_DEVICE" ]; then
      echo "error: 未检测到连接的真机设备" >&2
      exit 1
    fi
    deploy_to "$REAL_DEVICE"
    ;;
  all)
    deploy_to "$SIM_DEVICE"
    REAL_DEVICE="$(find_real_device)"
    if [ -n "$REAL_DEVICE" ]; then
      deploy_to "$REAL_DEVICE"
    else
      echo "warn: 未检测到真机，仅部署到模拟器" >&2
    fi
    ;;
esac

echo "done."
