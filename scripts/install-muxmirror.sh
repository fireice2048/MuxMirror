#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROFILE="${MUXMIRROR_BUILD_PROFILE:-release}"

if [ -n "${MUXMIRROR_INSTALL_ROOT:-}" ]; then
  BIN_DIR="${MUXMIRROR_BIN_DIR:-$MUXMIRROR_INSTALL_ROOT/bin}"
  LIBEXEC_DIR="${MUXMIRROR_LIBEXEC_DIR:-$MUXMIRROR_INSTALL_ROOT/libexec/muxmirror}"
else
  BIN_DIR="${MUXMIRROR_BIN_DIR:-$HOME/.termimirror/bin}"
  LIBEXEC_DIR="${MUXMIRROR_LIBEXEC_DIR:-$HOME/.termimirror/libexec/muxmirror}"
fi

if [ "$(uname -s)" != "Darwin" ]; then
  printf '错误：当前安装程序仅支持 macOS。\n' >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  printf '错误：未找到 cargo，无法构建 muxmirror。\n' >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  printf '错误：未找到 swiftc，请先安装 Xcode Command Line Tools。\n' >&2
  exit 1
fi

if [ "$PROFILE" = "release" ]; then
  cargo build --manifest-path "$REPO_ROOT/MirrorServer/Cargo.toml" --release
  MUXMIRROR_SOURCE="$REPO_ROOT/target/release/muxmirror"
else
  cargo build --manifest-path "$REPO_ROOT/MirrorServer/Cargo.toml"
  MUXMIRROR_SOURCE="$REPO_ROOT/target/debug/muxmirror"
fi

mkdir -p "$BIN_DIR" "$LIBEXEC_DIR"
install -m 0755 "$MUXMIRROR_SOURCE" "$BIN_DIR/muxmirror"

HELPER_PATH="$LIBEXEC_DIR/muxmirror-ax-helper"
swiftc \
  -O \
  -framework Cocoa \
  -framework ApplicationServices \
  "$REPO_ROOT/MirrorServer/macos/MuxMirrorAXHelper.swift" \
  -o "$HELPER_PATH"
chmod 0755 "$HELPER_PATH"

printf 'muxmirror 已安装：%s\n' "$BIN_DIR/muxmirror"
printf '辅助程序已安装：%s\n' "$HELPER_PATH"

if [ "${MUXMIRROR_SKIP_PERMISSION_PROMPT:-0}" = "1" ]; then
  printf '已跳过权限引导；请稍后运行：\n'
  printf '  MUXMIRROR_AX_HELPER="%s" "%s" setup\n' "$HELPER_PATH" "$BIN_DIR/muxmirror"
  exit 0
fi

printf '\n接下来检查 macOS 辅助功能权限。\n'
MUXMIRROR_AX_HELPER="$HELPER_PATH" "$BIN_DIR/muxmirror" setup
