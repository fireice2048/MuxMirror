package com.termirror.mobile.android.core

import android.content.Context
import android.content.SharedPreferences

/**
 * 用户偏好设置存储。
 *
 * 当前只承载「MUX 导航分组方式」：
 * - "window"：按终端窗口分组（默认）
 * - "directory"：按工作目录分组
 */
object SettingsStore {
    private const val PREFS_NAME = "termirror_settings"
    private const val KEY_MUX_GROUPING = "mux_grouping_mode"

    private const val DEFAULT_MODE = "window"

    /** 按目录分组时的命令行开关。 */
    const val GROUPING_DIRECTORY = "directory"
    const val GROUPING_WINDOW = "window"

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getMuxGroupingMode(context: Context): String {
        return prefs(context).getString(KEY_MUX_GROUPING, DEFAULT_MODE) ?: DEFAULT_MODE
    }

    fun setMuxGroupingMode(context: Context, mode: String) {
        prefs(context).edit().putString(KEY_MUX_GROUPING, mode).apply()
    }
}
