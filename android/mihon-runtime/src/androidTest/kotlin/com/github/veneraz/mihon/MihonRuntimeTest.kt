package com.github.veneraz.mihon

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class MihonRuntimeTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun asset(name: String): File = File(context.cacheDir, name).apply {
        outputStream().use { out -> instrumentation.context.assets.open(name).use { it.copyTo(out) } }
    }

    @Test fun apkFactorySearchChaptersImagesRestartAndRemoval() = runBlocking {
        val requests = CopyOnWriteArrayList<String>()
        val socket = ServerSocket(0)
        val base = "http://127.0.0.1:${socket.localPort}"
        val png = java.io.ByteArrayOutputStream().use { output ->
            val bitmap = android.graphics.Bitmap.createBitmap(1, 1, android.graphics.Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.BLACK)
            check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output))
            bitmap.recycle()
            output.toByteArray()
        }
        val worker = thread(isDaemon = true) {
            while (!socket.isClosed) {
                val client = try { socket.accept() } catch (_: Exception) { break }
                client.use {
                    val input = it.getInputStream().bufferedReader()
                    val first = input.readLine() ?: return@use
                    val headers = mutableListOf<String>()
                    while (true) { val line = input.readLine() ?: break; if (line.isEmpty()) break; headers.add(line) }
                    val length = headers.firstOrNull { it.startsWith("Content-Length:", true) }?.substringAfter(':')?.trim()?.toIntOrNull() ?: 0
                    if (length > 0) { val body = CharArray(length); var read = 0; while (read < length) { val n = input.read(body, read, length - read); if (n < 0) break; read += n } }
                    requests.add(first + "\n" + headers.joinToString("\n"))
                    val path = first.split(' ')[1]
                    val bytes = when {
                        path.startsWith("/resolve/") -> "$base/image".toByteArray()
                        path == "/image" || path == "/cover" -> png
                        else -> "fixture".toByteArray()
                    }
                    val output = it.getOutputStream()
                    output.write("HTTP/1.1 200 OK\r\nContent-Length: ${bytes.size}\r\nSet-Cookie: fixture=ok; Path=/\r\nConnection: close\r\n\r\n".toByteArray())
                    output.write(bytes); output.flush()
                }
            }
        }
        System.setProperty("venera.fixture.url", base)
        var runtime = MihonRuntime(context)
        assertEquals("ok", eu.kanade.tachiyomi.network.JavaScriptEngine(context).evaluate<String>("'ok'"))
        runtime.uninstall("eu.veneraz.fixture")
        val apk = asset("fixture.apk")
        try {
            assertEquals("eu.veneraz.fixture", runtime.inspect(apk.path)["package"])
            val installed = runtime.install(apk.path)
            assertEquals(2, installed.count { it["package"] == "eu.veneraz.fixture" })
            val page = runtime.search("900001", "hello", 1)
            assertEquals(true, page["hasNext"])
            assertEquals("Fixture book", (page["comics"] as List<Map<String, Any?>>).single()["title"])
            val details = runtime.details("900001", "/book/1")
            assertEquals(listOf("/ep/1", "/ep/2"), (details["chapters"] as Map<*, *>).keys.toList())
            assertEquals(2, runtime.pageCount("900001", "/ep/1"))
            val image = runtime.image("900001", "/ep/1", 0, null)
            assertArrayEquals(png, image)
            assertNotNull(android.graphics.BitmapFactory.decodeByteArray(image, 0, image.size))
            assertArrayEquals(png, runtime.image("900001", null, null, "$base/cover"))
            assertTrue(requests.any { it.startsWith("POST /image ") && it.contains("X-Image-Method: custom-post") && it.contains("X-Fixture: source-header") })
            assertTrue(requests.any { it.startsWith("POST /image ") && it.contains("Cookie: fixture=ok") })
            val tampered = File(context.cacheDir, "tampered.apk")
            java.util.zip.ZipFile(apk).use { source ->
                java.util.zip.ZipOutputStream(tampered.outputStream()).use { output ->
                    val entries = source.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        output.putNextEntry(java.util.zip.ZipEntry(entry.name))
                        val bytes = source.getInputStream(entry).use { it.readBytes() }
                        if (entry.name == "classes.dex") bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
                        output.write(bytes); output.closeEntry()
                    }
                }
            }
            var rejected = false
            try { runtime.install(tampered.path) } catch (_: Exception) { rejected = true }
            tampered.delete()
            assertTrue("Tampered APK must be rejected", rejected)
            assertEquals(2, runtime.list().count { it["package"] == "eu.veneraz.fixture" })
            runtime = MihonRuntime(context)
            assertEquals(2, runtime.list().count { it["package"] == "eu.veneraz.fixture" })
            assertEquals(2, runtime.pageCount("900001", "/ep/2"))
            runtime.uninstall("eu.veneraz.fixture")
            assertFalse(runtime.list().any { it["package"] == "eu.veneraz.fixture" })
        } finally { runtime.uninstall("eu.veneraz.fixture"); apk.delete(); socket.close(); worker.join(1000) }
    }

    @Test fun realPublishedExtensionLoadsWhenProvided() = runBlocking {
        if ("real-extension.apk" !in instrumentation.context.assets.list("").orEmpty()) return@runBlocking
        val apk = asset("real-extension.apk")
        val runtime = MihonRuntime(context)
        val pkg = runtime.inspect(apk.path)["package"] as String
        try {
            val installed = runtime.install(apk.path).filter { it["package"] == pkg }
            assertTrue(installed.isNotEmpty())
            assertTrue(installed.all { (it["name"] as String).isNotEmpty() })
        } finally { runtime.uninstall(pkg); apk.delete() }
    }
}
