/*
 * OpenSSL 头文件桩（stub），仅用于 OHOS 交叉编译场景。
 *
 * 背景：libssh2-sys 在 unix 下强制依赖 openssl-sys，而 TermMirror 的 OHOS
 * libssh2 预编译产物使用 mbedTLS 后端，完全不需要 OpenSSL 符号。
 * 这里只提供 openssl-sys 构建脚本版本探测（build/expando.c 宏展开）
 * 所需的最小宏定义；配合构建脚本中 OPENSSL_LIBS=""（不链接任何
 * OpenSSL 库），使 openssl-sys 在 OHOS target 下无害通过。
 */
#ifndef OPENSSL_OPENSSLV_H_STUB
#define OPENSSL_OPENSSLV_H_STUB

/* 宣称 OpenSSL 3.0.0；openssl-sys 据此设置版本相关 cfg，无实际符号引用 */
#define OPENSSL_VERSION_NUMBER 0x30000000L

#endif
