#ifndef ATTACH_MBEDTLS_OHOS_CONFIG_H
#define ATTACH_MBEDTLS_OHOS_CONFIG_H

#include "mbedtls/mbedtls_config.h"

/*
 * The HarmonyOS/Kotlin Native shared library does not resolve compiler-rt's
 * 128-bit division helper correctly. Avoid that MPI division path and keep
 * the portable C implementation on AArch64.
 */
#if defined(__aarch64__)
#undef MBEDTLS_HAVE_ASM
#define MBEDTLS_NO_UDBL_DIVISION
#endif

#endif
