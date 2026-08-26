#ifndef TERMIRROR_CORE_H
#define TERMIRROR_CORE_H

#pragma once

/* 本文件由 cbindgen 自动生成，请勿手工编辑 */

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * C 侧事件回调签名：参数为事件 JSON（NUL 结尾，仅回调期间有效）。
 */
typedef void (*TmEventCallback)(const char*);

/**
 * 初始化核心库（日志 + 配置）。`files_dir` 为应用文件目录。
 *
 * # 安全性
 * `files_dir` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
void tm_init(const char *files_dir);

/**
 * 注册事件回调（JSON 字符串载荷），覆盖旧回调。
 *
 * # 安全性
 * `callback` 指向的函数必须线程安全，且不得持有传入指针超过调用期。
 */
void tm_on_event(TmEventCallback callback);

/**
 * 建立 SSH 会话，同步返回 sessionId（>0），失败 -1。
 * `params_json` 形如 `{"host":"","port":22,"username":"","password":"","cols":100,"rows":32}`。
 *
 * # 安全性
 * `params_json` 必须是有效的 NUL 结尾 UTF-8 JSON 字符串。
 */
int64_t tm_session_connect(const char *params_json);

/**
 * 向会话写入输入数据。
 *
 * # 安全性
 * `data` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
void tm_session_write(int64_t session_id, const char *data);

/**
 * 调整终端尺寸。
 */
void tm_session_resize(int64_t session_id, uint32_t cols, uint32_t rows);

/**
 * 执行一次性 SSH exec 命令，同步返回 execId（>0），失败 -1。
 * 结果（stdout / 错误信息）经 `execResult` 事件异步上报。
 *
 * # 安全性
 * `params_json` / `command` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
int64_t tm_session_exec(const char *params_json, const char *command);

/**
 * 关闭会话（幂等）。
 */
void tm_session_close(int64_t session_id);

/**
 * 按键编码：返回终端字节序列（C 堆字符串，需 `tm_string_free` 释放）。
 *
 * # 安全性
 * `key` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
char *tm_encode_key(const char *key, bool ctrl, bool alt);

/**
 * 返回配置列表 JSON 数组（C 堆字符串，需 `tm_string_free` 释放）。
 */
char *tm_config_list(void);

/**
 * 保存配置（按 name 新增或覆盖）。
 *
 * # 安全性
 * `json` 必须是有效的 NUL 结尾 UTF-8 JSON 字符串。
 */
void tm_config_save(const char *json);

/**
 * 按名称删除配置。
 *
 * # 安全性
 * `name` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
void tm_config_delete(const char *name);

/**
 * 移动配置并持久化顺序。
 */
bool tm_config_move(uint32_t from, uint32_t to);

/**
 * TCP 连通性诊断（异步），结果经 diag 事件返回。
 *
 * # 安全性
 * `host` 必须是有效的 NUL 结尾 UTF-8 字符串。
 */
void tm_tcp_check(const char *host, uint16_t port);

/**
 * 释放本库分配的 C 字符串。
 *
 * # 安全性
 * `ptr` 必须是本库返回的堆字符串指针，且只能释放一次。
 */
void tm_string_free(char *ptr);

/**
 * C ABI：libssh2 运行时自检。
 *
 * 返回 0 表示 libssh2 可正常初始化；非 0 表示不可用。
 * 除验证静态库真实链入 cdylib 外，也供三端启动时做环境自检。
 */
int termirror_libssh2_check(void);

#endif  /* TERMIRROR_CORE_H */
