package com.termirror.mobile.android.core

import android.os.Parcel
import android.os.Parcelable

/**
 * Rust → UI 事件，与 libtermirror_core 契约一致。
 */
data class TmEvent(
    val sessionId: Long,
    val type: String,
    val state: String? = null,
    val data: String? = null,
    val cursor: Int? = null,
    val styles: List<TerminalStyleRange> = emptyList(),
    val mouseProtocol: String = "none"
)

/**
 * 终端样式区间，起止位置为 UTF-16 码元偏移。
 */
data class TerminalStyleRange(
    val start: Int,
    val end: Int,
    val style: String, // normal / bold / dim / inverse
    val foreground: String? = null,
    val background: String? = null
)

/**
 * 服务器配置，与 tmConfigList / tmConfigSave 的 JSON 结构一致。
 */
data class ServerConfig(
    val name: String,
    val host: String,
    val port: Int = 22,
    val username: String,
    val password: String
) : Parcelable {
    constructor(parcel: Parcel) : this(
        parcel.readString() ?: "",
        parcel.readString() ?: "",
        parcel.readInt(),
        parcel.readString() ?: "",
        parcel.readString() ?: ""
    )

    override fun writeToParcel(parcel: Parcel, flags: Int) {
        parcel.writeString(name)
        parcel.writeString(host)
        parcel.writeInt(port)
        parcel.writeString(username)
        parcel.writeString(password)
    }

    override fun describeContents(): Int = 0

    companion object CREATOR : Parcelable.Creator<ServerConfig> {
        override fun createFromParcel(parcel: Parcel): ServerConfig = ServerConfig(parcel)
        override fun newArray(size: Int): Array<ServerConfig?> = arrayOfNulls(size)
    }
}
