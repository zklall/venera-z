package com.github.wgh136.venera

import android.content.Context
import android.util.Log
import com.github.veneraz.mihon.MihonRuntime
import com.github.veneraz.mihon.extensionCause
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MihonChannel(private val context: Context, messenger: BinaryMessenger) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val runtime by lazy {
        MihonRuntime.active ?: MihonRuntime(context.applicationContext)
    }
    private val channel = MethodChannel(messenger, "venera/mihon")
    init {
        channel.setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    val value: Any? = withContext(Dispatchers.IO) {
                        fun text(key: String) = requireNotNull(call.argument<String>(key))
                        when (call.method) {
                            "configure" -> { runtime.configure(call.argument<String>("proxy"), call.argument<Map<String, String>>("dns") ?: emptyMap(), call.argument<String>("userAgent")); null }
                            "list" -> mapOf("sources" to runtime.list(), "failures" to runtime.failures.toMap())
                            "inspect" -> runtime.inspect(text("path"))
                            "install" -> runtime.install(text("path"))
                            "uninstall" -> { runtime.uninstall(text("package")); null }
                            "settings" -> { runtime.openSettings(text("id"), context); null }
                            "search" -> runtime.search(text("id"), text("query"), call.argument<Int>("page") ?: 1)
                            "popular" -> runtime.popular(text("id"), call.argument<Int>("page") ?: 1, call.argument<Boolean>("latest") == true)
                            "details" -> runtime.details(text("id"), text("url"))
                            "pages" -> runtime.pageCount(text("id"), text("chapter"))
                            "image" -> runtime.image(text("id"), call.argument<String>("chapter"), call.argument<Int>("index"), call.argument<String>("cover"))
                            else -> throw IllegalArgumentException("Unknown Mihon operation")
                        }
                    }
                    result.success(value)
                } catch (error: Throwable) {
                    if (error is CancellationException) throw error
                    if (error is VirtualMachineError) throw error
                    Log.e("Mihon", "${call.method} failed", error)
                    result.error("mihon_error", error.extensionCause().toString(), error.stackTraceToString())
                }
            }
        }
    }
    fun close() { channel.setMethodCallHandler(null); scope.cancel() }
}
