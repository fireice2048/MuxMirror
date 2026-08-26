# 踩坑记忆：deploy-harmony-sim.sh 与 build-ohos.sh 的两处陷阱

## 现象

- `./scripts/deploy-harmony-sim.sh` 在 Rust 核心交叉编译阶段失败：
  - `libssh2/src/libssh2_priv.h:58:10: fatal error: 'stdio.h' file not found`
  - 实际上 libssh2-sys 回退到了 vendored 编译，而 cc-rs 用的是系统 `cc` 而非 OHOS 交叉编译器。
- 修复编译问题后，脚本又报 `DEVICE: 未绑定的变量`，但变量明明已赋值。
- 再往后，脚本执行 `devecocli run` 时报 `Not in a valid project directory`。

## 根因 1：build-ohos.sh 没绑 pkg-config 与交叉编译器

- 本机没有安装系统 `pkg-config`，`libssh2-sys` 找不到预编译 `libssh2.a`，于是走 vendored 源码编译。
- `.cargo/config.toml` 只给 rustc 指定了 `linker` 和 `rustflags`，但 **cc-rs 编译 C 依赖** 看的是 `CC_aarch64-unknown-linux-ohos` / `CC_x86_64-unknown-linux-ohos` 等环境变量；未设置时回退到系统 `cc`，系统 `cc` 不认识 `--target=aarch64-linux-ohos` 的 sysroot，所以找不到标准头文件。
- 仓库里明明写了 `MobileApp/shared/scripts/pkg-config-ohos.sh` 作为 pkg-config 包装脚本，但 `build-ohos.sh` 没有通过 `PKG_CONFIG` 环境变量把它挂上去。

## 正确做法 1

在 `build-ohos.sh` 中：

1. 设置 `PKG_CONFIG="$PWD/scripts/pkg-config-ohos.sh"`，让 libssh2-sys 通过自定义脚本找到预编译库；
2. 按 target 设置 `CC` / `CXX` / `AR` / `RANLIB` 为 OHOS NDK 的 clang 包装脚本：

```sh
NDK="${HARMONY_NATIVE_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
export PKG_CONFIG="$PWD/scripts/pkg-config-ohos.sh"
# ...
export CC="$NDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="$NDK/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR="$NDK/llvm/bin/llvm-ar"
export RANLIB="$NDK/llvm/bin/llvm-ranlib"
```

这样 libssh2-sys 直接链接 `build/ohos-ssh/<abi>/libssh2.a` 与 `libmbedcrypto.a`，不再编译源码。

## 根因 2：bash 3.2 + 中文全角标点后紧跟变量扩展会解析错误

- macOS `/bin/sh` 是 GNU bash 3.2.57。
- `echo "... App（设备：$DEVICE）..."` 这种在中文全角括号、全角冒号后紧跟 `$DEVICE` 的写法，bash 3.2 在 `set -eu` 下会把变量名解析错，报 `DEVICE: unbound variable`。
- 同样字符串在 bash 5.x / zsh 下正常；用半角 ASCII 标点或把变量与全角标点隔开即可规避。

## 正确做法 2

脚本中涉及变量扩展的 echo 行避免全角标点前紧贴 `$变量`：

```sh
echo "==> [4/4] 安装并启动 App (设备: $DEVICE) ..."
```

## 根因 3：devecocli run 要在 harmonyApp 目录下执行

- `devecocli build` 可以通过指定 module 在项目子目录运行，但 `devecocli run` 需要在项目根目录（存在 `build-profile.json5` 的目录）执行。
- 脚本前面用 `(cd "$HARMONY" && devecocli build ...)` 子shell 执行了 build，但最后的 `devecocli run` 漏了 `cd`。

## 正确做法 3

```sh
(cd "$HARMONY" && devecocli run --device "$DEVICE" --skip-build --build-mode debug)
```

## 验证方式

- 执行 `./scripts/deploy-harmony-sim.sh`：
  - Rust 核心 `aarch64` 与 `x86_64` release 构建成功；
  - HAP 打包成功；
  - 模拟器 `Pura 90 Pro` 安装并启动成功，输出 `Application ... start ability successfully.`。
