package com.termirror.mobile.android

import android.app.Application
import android.util.Log
import com.termirror.mobile.android.core.TermirrorCore

class TermirrorApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val filesDir = applicationContext.filesDir.absolutePath
        Log.i(TAG, "Initializing TermirrorCore at $filesDir")
        TermirrorCore.initialize(filesDir)
    }

    companion object {
        private const val TAG = "TermirrorApp"
    }
}
