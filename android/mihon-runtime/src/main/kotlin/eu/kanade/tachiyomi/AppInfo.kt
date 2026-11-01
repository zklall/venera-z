package eu.kanade.tachiyomi

import android.content.Context
import android.os.Build

/** Host version, intentionally not a spoofed Mihon version. */
object AppInfo {
    internal var context: Context? = null
    @Suppress("DEPRECATION")
    fun getVersionCode(): Int {
        val app = context ?: return 0
        val info = app.packageManager.getPackageInfo(app.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else info.versionCode
    }
    fun getVersionName(): String {
        val app = context ?: return ""
        return app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: ""
    }
    fun getApplicationId(): String = context?.packageName ?: ""
}
