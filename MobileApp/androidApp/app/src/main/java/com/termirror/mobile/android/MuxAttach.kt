package com.termirror.mobile.android

import android.os.Parcel
import android.os.Parcelable

data class MuxAttach(val mux: String, val session: String) : Parcelable {
    constructor(parcel: Parcel) : this(
        parcel.readString() ?: "",
        parcel.readString() ?: ""
    )

    override fun writeToParcel(parcel: Parcel, flags: Int) {
        parcel.writeString(mux)
        parcel.writeString(session)
    }

    override fun describeContents(): Int = 0

    companion object CREATOR : Parcelable.Creator<MuxAttach> {
        override fun createFromParcel(parcel: Parcel): MuxAttach = MuxAttach(parcel)
        override fun newArray(size: Int): Array<MuxAttach?> = arrayOfNulls(size)
    }
}
