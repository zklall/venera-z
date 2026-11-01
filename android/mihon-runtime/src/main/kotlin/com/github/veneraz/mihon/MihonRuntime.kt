package com.github.veneraz.mihon

import com.android.apksig.ApkVerifier
import android.app.Application
import android.content.Context
import android.content.Intent
import eu.kanade.tachiyomi.source.ConfigurableSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.network.JavaScriptEngine
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.protobuf.ProtoBuf
import okhttp3.Request
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.*
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** An in-process Android host. Extension APKs stay in app-private storage. */
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
class MihonRuntime(private val context: Context) {
    companion object { @Volatile var active: MihonRuntime? = null; private set }
    private val directory = File(context.filesDir, "mihon_extensions").apply { mkdirs() }
    private val sources = ConcurrentHashMap<String, Source>()
    private val packages = ConcurrentHashMap<String, List<Source>>()
    private val pages = object : LinkedHashMap<String, List<Page>>(16, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Page>>?) = size > 20
    }
    private val lock = Mutex()
    private var initialized = false
    @Volatile private var invalidated = false
    fun invalidate() { invalidated = true }
    private val network = NetworkHelper(context)
    val failures = ConcurrentHashMap<String, String>()

    init {
        eu.kanade.tachiyomi.AppInfo.context = context.applicationContext
        Injekt.addSingleton<Context>(context.applicationContext)
        Injekt.addSingleton<Application>(context.applicationContext as Application)
        Injekt.addSingleton(network)
        Injekt.addSingleton(Json { ignoreUnknownKeys = true; explicitNulls = false })
        Injekt.addSingleton<ProtoBuf>(ProtoBuf)
        Injekt.addSingleton(JavaScriptEngine(context))
        active = this
    }

    @Suppress("DEPRECATION")
    private fun info(file: File): PackageInfo = context.packageManager.getPackageArchiveInfo(
        file.absolutePath, PackageManager.GET_META_DATA or PackageManager.GET_CONFIGURATIONS or
            PackageManager.GET_SIGNATURES or if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else 0,
    ) ?: error("Invalid extension APK")

    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    fun inspect(path: String): Map<String, Any?> {
        val file = File(path)
        val verified = ApkVerifier.Builder(file)
            .setMinCheckedPlatformVersion(Build.VERSION.SDK_INT)
            .setMaxCheckedPlatformVersion(Build.VERSION.SDK_INT).build().verify()
        check(verified.isVerified) { "Invalid extension APK signature" }
        val info = info(file)
        check(info.reqFeatures.orEmpty().any { it.name == "tachiyomi.extension" }) { "This APK is not a Mihon extension" }
        check(info.packageName.matches(Regex("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+"))) { "Invalid extension package name" }
        check(certificates(info).isNotEmpty()) { "Unsigned extension APK" }
        check((info.applicationInfo?.minSdkVersion ?: 24) <= Build.VERSION.SDK_INT) { "This extension requires a newer Android version" }
        val app = info.applicationInfo
        app?.sourceDir = path
        app?.publicSourceDir = path
        val label = app?.let { context.packageManager.getApplicationLabel(it).toString() } ?: info.packageName
        return mapOf("name" to label, "package" to info.packageName, "version" to info.versionName, "signatures" to certificates(info).toList())
    }

    private fun load(file: File): Pair<PackageInfo, List<Source>> {
        inspect(file.absolutePath)
        val info = info(file)
        val meta = info.applicationInfo?.metaData ?: error("Extension metadata is missing")
        val version = meta.get("tachiyomix.extensionLib")?.toString()
            ?: info.versionName?.substringBeforeLast('.') ?: ""
        check(version in listOf("1.4", "1.6")) { "Unsupported Mihon extension API: $version" }
        val names = meta.getString("tachiyomi.extension.class") ?: error("Extension entry point is missing")
        val loader = DexClassLoader(file.absolutePath, context.codeCacheDir.absolutePath, null, context.classLoader)
        val loaded = names.split(';').filter { it.isNotBlank() }.flatMap { entry ->
            val name = entry.trim().let { if (it.startsWith('.')) info.packageName + it else it }
            when (val instance = loader.loadClass(name).getDeclaredConstructor().newInstance()) {
                is Source -> listOf(instance)
                is SourceFactory -> instance.createSources()
                else -> error("Unknown Mihon extension entry point")
            }
        }
        check(loaded.isNotEmpty()) { "Extension contains no sources" }
        check(loaded.map { it.id }.toSet().size == loaded.size) { "Duplicate source IDs in extension" }
        for (source in loaded) {
            val existing = sources[source.id.toString()]
            check(existing == null || packages[info.packageName]?.contains(existing) == true) { "Source ID conflicts with another extension" }
        }
        return info to loaded
    }

    suspend fun configure(proxy: String?, dns: Map<String, String>, userAgent: String?) = lock.withLock {
        network.configure(proxy, dns, userAgent)
        sources.clear(); packages.clear(); synchronized(pages) { pages.clear() }; initialized = false
    }

    suspend fun list(): List<Map<String, Any?>> = lock.withLock {
        if (!initialized || invalidated) {
            sources.clear(); packages.clear(); failures.clear(); synchronized(pages) { pages.clear() }
            invalidated = false
            directory.listFiles()?.filter { it.extension == "apk" }?.forEach { file ->
                try {
                    file.setReadOnly()
                    val (info, loaded) = load(file)
                    register(info, loaded)
                } catch (error: Throwable) {
                    if (error is VirtualMachineError) throw error
                    failures[file.nameWithoutExtension] = error.extensionCause().toString()
                }
            }
            initialized = true
        }
        packages.flatMap { (pkg, members) ->
            val info = info(File(directory, "$pkg.apk"))
            members.map { source -> mapOf("id" to source.id.toString(), "name" to source.name,
                "lang" to source.lang, "latest" to source.supportsLatest,
                "configurable" to (source is ConfigurableSource),
                "package" to pkg, "version" to info.versionName,
                "baseUrl" to (source as? HttpSource)?.baseUrl) }
        }
    }

    private fun register(info: PackageInfo, loaded: List<Source>) {
        packages.remove(info.packageName)?.forEach { sources.remove(it.id.toString()) }
        packages[info.packageName] = loaded
        loaded.forEach { sources[it.id.toString()] = it }
        failures.remove(info.packageName)
        synchronized(pages) { pages.clear() }
    }

    suspend fun install(path: String): List<Map<String, Any?>> {
        list()
        lock.withLock {
            val incoming = File(path)
            inspect(path)
            val metadata = info(incoming)
            val target = File(directory, "${metadata.packageName}.apk")
            if (target.exists()) {
                val previous = info(target)
                check(certificates(previous) == certificates(metadata)) { "Extension signature changed" }
                @Suppress("DEPRECATION")
                check((if (Build.VERSION.SDK_INT >= 28) metadata.longVersionCode else metadata.versionCode.toLong()) >= (if (Build.VERSION.SDK_INT >= 28) previous.longVersionCode else previous.versionCode.toLong())) { "Cannot downgrade extension" }
            }
            val staged = File(directory, "${metadata.packageName}.staged")
            try {
                staged.delete()
                staged.outputStream().use { output ->
                    check(staged.setReadOnly()) { "Cannot protect extension file" }
                    incoming.inputStream().use { it.copyTo(output) }
                }
                val (info, loaded) = load(staged)
                check(staged.renameTo(target)) { "Cannot save extension file" }
                register(info, loaded)
            } finally { staged.delete() }
        }
        return list()
    }

    suspend fun uninstall(pkg: String) {
        list()
        lock.withLock {
            check(pkg.matches(Regex("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+"))) { "Invalid package name" }
            val target = File(directory, "$pkg.apk")
            check(!target.exists() || target.delete()) { "Cannot remove extension" }
            packages.remove(pkg)?.forEach { sources.remove(it.id.toString()) }
            failures.remove(pkg)
            synchronized(pages) { pages.clear() }
        }
    }

    suspend fun configurable(id: String): ConfigurableSource = source(id) as? ConfigurableSource
        ?: error("This source has no settings")
    suspend fun openSettings(id: String, launcher: Context = context) {
        configurable(id)
        withContext(Dispatchers.Main) {
            val intent = Intent(launcher, MihonSettingsActivity::class.java).putExtra("source", id)
            if (launcher !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            launcher.startActivity(intent)
        }
    }

    private suspend fun source(id: String): Source { list(); return sources[id] ?: error("Mihon source is not installed") }
    private fun manga(url: String) = SManga.create().apply { this.url = url; title = url }
    private fun chapter(url: String) = SChapter.create().apply { this.url = url; name = url }
    private fun comic(value: SManga) = mapOf("id" to value.url, "title" to value.title,
        "cover" to (value.thumbnail_url ?: ""), "subtitle" to (value.author ?: value.artist ?: ""),
        "description" to (value.description ?: ""), "tags" to value.getGenres().orEmpty())

    suspend fun search(id: String, query: String, page: Int): Map<String, Any> {
        val source = source(id)
        val result = source.getSearchManga(page, query, source.getFilterList())
        return mapOf("comics" to result.mangas.map(::comic), "hasNext" to result.hasNextPage)
    }
    suspend fun popular(id: String, page: Int, latest: Boolean): Map<String, Any> {
        val source = source(id)
        val result = if (latest) source.getLatestUpdates(page) else source.getPopularManga(page)
        return mapOf("comics" to result.mangas.map(::comic), "hasNext" to result.hasNextPage)
    }
    suspend fun details(id: String, url: String): Map<String, Any?> {
        val source = source(id)
        val result = source.getMangaUpdate(manga(url), emptyList(), true, true)
        val value = result.manga
        // Extension chapter lists follow Mihon's newest-first contract.
        val chapters = linkedMapOf<String, String>()
        result.chapters.asReversed().forEach { chapters[it.url] = it.name }
        return comic(value) + mapOf("comicId" to url, "chapters" to chapters,
            "tags" to mapOf("author" to listOfNotNull(value.author), "genre" to value.getGenres().orEmpty()),
            "url" to (source as? HttpSource)?.getMangaUrl(value))
    }
    private suspend fun pageList(id: String, chapter: String): List<Page> {
        val key = "$id:$chapter"
        synchronized(pages) { pages[key]?.let { return it } }
        val result = source(id).getPageList(chapter(chapter))
        synchronized(pages) { pages[key] = result }
        return result
    }
    suspend fun pageCount(id: String, chapter: String) = pageList(id, chapter).size
    suspend fun image(id: String, chapter: String?, index: Int?, cover: String?): ByteArray {
        val source = source(id) as? HttpSource ?: error("This Mihon source does not expose HTTP images")
        try {
        val response = if (cover != null) {
            source.client.newCall(Request.Builder().url(cover).headers(source.headers).build()).execute()
        } else {
            val page = pageList(id, requireNotNull(chapter))[requireNotNull(index)]
            if (page.imageUrl.isNullOrEmpty()) page.imageUrl = source.getImageUrl(page)
            source.getImage(page)
        }
        return response.use {
            check(it.isSuccessful) { "HTTP ${it.code}" }
            it.body.bytes().also { bytes -> check(bytes.isNotEmpty()) { "Empty image response" } }
        }
        } catch (error: Exception) {
            if (chapter != null) synchronized(pages) { pages.remove("$id:$chapter") }
            throw error
        }
    }
}
