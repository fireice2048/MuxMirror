//! 构建脚本：
//! 1. OHOS target 下把 NDK sysroot 的 NAPI 动态库（libace_napi.z.so）加入链接；
//! 2. OHOS target 下把预编译的 libssh2.a / libmbedcrypto.a 搜索路径透传给链接器
//!    （由 libssh2-sys 经 pkg-config 定位，见 scripts/build-ohos.sh）。

use std::env;

fn main() {
    let target = env::var("TARGET").unwrap_or_default();
    if !target.ends_with("-linux-ohos") {
        return;
    }

    // NDK 根目录可用 HARMONY_NATIVE_SDK 覆盖，便于 CI / 他人机器路径不同
    let ndk = env::var("HARMONY_NATIVE_SDK").unwrap_or_else(|_| {
        "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native".to_string()
    });
    println!("cargo:rerun-if-env-changed=HARMONY_NATIVE_SDK");

    let arch = if target.starts_with("aarch64") {
        "aarch64"
    } else {
        "x86_64"
    };

    // NAPI 动态库（napi_register_module_v1 等符号由它提供）
    println!("cargo:rustc-link-search=native={ndk}/sysroot/usr/lib/{arch}-linux-ohos");
    println!("cargo:rustc-link-lib=dylib=ace_napi.z");
}
