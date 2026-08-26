# iOS Rust 核心交叉编译：__chkstk_darwin 未定义符号

日期：2026-07-26
类型：踩坑 / 构建
影响：iOS 真机 target 构建失败

## 现象

在 `MobileApp/shared` 中执行：

```sh
cargo build --release --target aarch64-apple-ios --features vendored-openssl
```

链接阶段报错：

```
Undefined symbols for architecture arm64:
  "___chkstk_darwin", referenced from:
      ...
ld: symbol(s) not found for architecture arm64
```

## 根因

`openssl-sys` vendored 构建的 OpenSSL 对象文件在 macOS 上默认以较高的 iOS 版本目标编译，而链接器默认使用 iOS 10.0 部署目标。低版本 iOS 真机链接器不会提供 `___chkstk_darwin` 符号（这是 macOS 特有的栈检查符号），导致链接失败。

## 解决方案

设置较高的 iOS 部署目标，使 clang 在链接阶段使用匹配的 iOS 版本：

```sh
export IPHONEOS_DEPLOYMENT_TARGET=16.0
```

脚本 `scripts/build-ios.sh` 已内置该环境变量默认值。

## 验证

```sh
cd MobileApp/shared
bash scripts/build-ios.sh
# 成功生成 build/ios/TermirrorCore.xcframework
```

## 预防措施

- iOS 构建脚本必须显式设置 `IPHONEOS_DEPLOYMENT_TARGET`，避免依赖 Xcode 默认的 10.0。
- 后续 CI 环境若出现同样错误，优先检查该环境变量。

## 关联文件

- `MobileApp/shared/scripts/build-ios.sh`
- `MobileApp/shared/Cargo.toml`
