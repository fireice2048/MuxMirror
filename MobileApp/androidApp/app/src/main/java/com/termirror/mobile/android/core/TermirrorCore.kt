package com.termirror.mobile.android.core

import android.util.Log
import android.util.JsonReader
import android.util.JsonToken
import com.sun.jna.*
import com.sun.jna.ptr.PointerByReference
import java.io.StringReader

/**
 * Rust 核心 C ABI 的 JNA 封装。
 *
 * 三端共享逻辑在 `libtermirror_core.so` 中实现，Android 侧通过 JNA 直接调用
 * 稳定 C ABI（tm_*），不做任何业务逻辑。
 */
object TermirrorCore {
    private const val TAG = "TermirrorCore"

    interface Lib : Library {
        fun tm_init(filesDir: String)
        fun tm_on_event(callback: TmEventCallback)
        fun tm_session_connect(paramsJson: String): Long
        fun tm_session_write(sessionId: Long, data: String)
        fun tm_session_resize(sessionId: Long, cols: Int, rows: Int)
        fun tm_session_exec(paramsJson: String, command: String): Long
        fun tm_session_close(sessionId: Long)
        fun tm_encode_key(key: String, ctrl: Byte, alt: Byte): Pointer
        fun tm_config_list(): Pointer
        fun tm_config_save(json: String)
        fun tm_config_delete(name: String)
        fun tm_config_move(from: Int, to: Int): Byte
        fun tm_tcp_check(host: String, port: Short)
        fun tm_string_free(ptr: Pointer)
        fun termirror_libssh2_check(): Int

        interface TmEventCallback : Callback {
            fun invoke(json: String)
        }
    }

    private val lib: Lib by lazy {
        Native.load("termirror_core", Lib::class.java).also {
            Log.i(TAG, "libtermirror_core.so loaded, libssh2_check=${it.termirror_libssh2_check()}")
        }
    }

    private val listeners = mutableListOf<(TmEvent) -> Unit>()
    private var initialized = false

    // JNA 回调必须被 Java 侧强引用持有：匿名对象若注册后被 GC 回收，
    // 本地函数指针会被释放，Rust 侧事件将静默丢失。
    private val eventCallback = object : Lib.TmEventCallback {
        override fun invoke(json: String) {
            dispatchEvent(parseEvent(json))
        }
    }

    fun initialize(filesDir: String) {
        if (initialized) return
        initialized = true
        lib.tm_init(filesDir)
        lib.tm_on_event(eventCallback)
    }

    fun addEventListener(listener: (TmEvent) -> Unit) {
        listeners.add(listener)
    }

    fun removeEventListener(listener: (TmEvent) -> Unit) {
        listeners.remove(listener)
    }

    private fun dispatchEvent(event: TmEvent) {
        listeners.forEach { listener ->
            try {
                listener(event)
            } catch (e: Exception) {
                Log.e(TAG, "Event dispatch failed: ${e.message}")
            }
        }
    }

    private fun parseEvent(json: String): TmEvent {
        // 使用 Android 内置流式 JSON 解析器，避免对完整 output 快照做正则扫描。
        // output 是完整终端快照，可能达到 256KB；同时解析 styles 时不应复制快照正文。
        return try {
            parseEventJson(json)
        } catch (e: Exception) {
            Log.e(TAG, "Parse event failed: $json", e)
            TmEvent(0L, "error", null, json, null, emptyList(), "none")
        }
    }

    internal fun parseEventJson(json: String): TmEvent {
        var sessionId = 0L
        var type = ""
        var state: String? = null
        var data: String? = null
        var cursor: Int? = null
        var styles = emptyList<TerminalStyleRange>()
        var mouseProtocol = "none"

        JsonReader(StringReader(json)).use { reader ->
            reader.beginObject()
            while (reader.hasNext()) {
                when (reader.nextName()) {
                    "sessionId" -> sessionId = readNullableLong(reader) ?: 0L
                    "type" -> type = readNullableString(reader) ?: ""
                    "state" -> state = readNullableString(reader)
                    "data" -> data = readNullableString(reader)
                    "cursor" -> cursor = readNullableLong(reader)?.toInt()
                    "styles" -> styles = readStyles(reader)
                    "mouseProtocol" -> mouseProtocol = readNullableString(reader) ?: "none"
                    else -> reader.skipValue()
                }
            }
            reader.endObject()
        }

        return TmEvent(sessionId, type, state, data, cursor, styles, mouseProtocol)
    }

    private fun readStyles(reader: JsonReader): List<TerminalStyleRange> {
        if (reader.peek() == JsonToken.NULL) {
            reader.nextNull()
            return emptyList()
        }

        val styles = mutableListOf<TerminalStyleRange>()
        reader.beginArray()
        while (reader.hasNext()) {
            if (reader.peek() != JsonToken.BEGIN_OBJECT) {
                reader.skipValue()
                continue
            }

            var start: Int? = null
            var end: Int? = null
            var style = "normal"
            var foreground: String? = null
            var background: String? = null

            reader.beginObject()
            while (reader.hasNext()) {
                when (reader.nextName()) {
                    "start" -> start = readNullableLong(reader)?.toInt()
                    "end" -> end = readNullableLong(reader)?.toInt()
                    "style" -> style = readNullableString(reader) ?: "normal"
                    "foreground" -> foreground = readNullableString(reader)
                    "background" -> background = readNullableString(reader)
                    else -> reader.skipValue()
                }
            }
            reader.endObject()

            val validStart = start ?: continue
            val validEnd = end ?: continue
            if (validStart >= 0 && validEnd > validStart) {
                styles += TerminalStyleRange(
                    start = validStart,
                    end = validEnd,
                    style = style,
                    foreground = foreground,
                    background = background
                )
            }
        }
        reader.endArray()
        return styles
    }

    private fun readNullableString(reader: JsonReader): String? {
        if (reader.peek() == JsonToken.NULL) {
            reader.nextNull()
            return null
        }
        return reader.nextString()
    }

    private fun readNullableLong(reader: JsonReader): Long? {
        if (reader.peek() == JsonToken.NULL) {
            reader.nextNull()
            return null
        }
        return reader.nextLong()
    }

    // ---- 会话 API ----

    fun connectSession(config: ServerConfig, cols: Int, rows: Int): Long {
        val json = """
            {"host":"${escapeJson(config.host)}","port":${config.port},"username":"${escapeJson(config.username)}","password":"${escapeJson(config.password)}","cols":$cols,"rows":$rows}
        """.trimIndent()
        return lib.tm_session_connect(json)
    }

    fun writeSession(sessionId: Long, data: String) {
        lib.tm_session_write(sessionId, data)
    }

    fun resizeSession(sessionId: Long, cols: Int, rows: Int) {
        lib.tm_session_resize(sessionId, cols, rows)
    }

    fun execSession(config: ServerConfig, command: String): Long {
        val json = """
            {"host":"${escapeJson(config.host)}","port":${config.port},"username":"${escapeJson(config.username)}","password":"${escapeJson(config.password)}"}
        """.trimIndent()
        return lib.tm_session_exec(json, command)
    }

    fun closeSession(sessionId: Long) {
        lib.tm_session_close(sessionId)
    }

    fun encodeKey(key: String, ctrl: Boolean, alt: Boolean): String {
        val ptr = lib.tm_encode_key(key, if (ctrl) 1 else 0, if (alt) 1 else 0)
        return ptrToString(ptr).also { lib.tm_string_free(ptr) }
    }

    // ---- 配置 API ----

    fun listConfigs(): List<ServerConfig> {
        val ptr = lib.tm_config_list()
        val json = ptrToString(ptr).also { lib.tm_string_free(ptr) }
        return try {
            parseServerConfigList(json)
        } catch (e: Exception) {
            Log.e(TAG, "Parse config list failed: $json", e)
            emptyList()
        }
    }

    fun saveConfig(config: ServerConfig) {
        val json = """
            {"name":"${escapeJson(config.name)}","host":"${escapeJson(config.host)}","port":${config.port},"username":"${escapeJson(config.username)}","password":"${escapeJson(config.password)}"}
        """.trimIndent()
        lib.tm_config_save(json)
    }

    fun deleteConfig(name: String) {
        lib.tm_config_delete(name)
    }

    fun moveConfig(from: Int, to: Int): Boolean {
        return lib.tm_config_move(from, to) != 0.toByte()
    }

    // ---- 诊断 ----

    fun tcpCheck(host: String, port: Int) {
        lib.tm_tcp_check(host, port.toShort())
    }

    // ---- 工具 ----

    private fun ptrToString(ptr: Pointer): String {
        return ptr.getString(0, "UTF-8")
    }

    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\b", "\\b")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    private fun parseServerConfigList(json: String): List<ServerConfig> {
        val list = mutableListOf<ServerConfig>()
        val itemPattern = """\{\s*"name"\s*:\s*"([^"]*)"\s*,\s*"host"\s*:\s*"([^"]*)"\s*,\s*"port"\s*:\s*(\d+)\s*,\s*"username"\s*:\s*"([^"]*)"\s*,\s*"password"\s*:\s*"([^"]*)"\s*\}""".toRegex()
        itemPattern.findAll(json).forEach { match ->
            list.add(
                ServerConfig(
                    name = match.groupValues[1],
                    host = match.groupValues[2],
                    port = match.groupValues[3].toInt(),
                    username = match.groupValues[4],
                    password = match.groupValues[5]
                )
            )
        }
        return list
    }
}
