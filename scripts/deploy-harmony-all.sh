#!/usr/bin/env sh
# 一键部署鸿蒙 App 到模拟器和真机
# 等价于：bash scripts/deploy-harmony.sh all
set -eu
cd "$(dirname "$0")/.."
bash scripts/deploy-harmony.sh all "$@"
