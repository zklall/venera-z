package eu.kanade.tachiyomi.network

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.brotli.BrotliInterceptor
import java.util.concurrent.TimeUnit
import java.net.Proxy
import java.net.InetSocketAddress
import java.net.URI
import java.net.InetAddress
import java.net.URLDecoder
import okhttp3.Credentials
import okhttp3.Dns

/** Standalone host implementation of the extension networking API. */
class NetworkHelper(context: Context) {
    val cookieJar = AndroidCookieJar()
    private var userAgent = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
    private fun builder() = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES)
        .addInterceptor(BrotliInterceptor)
        .addInterceptor { chain ->
            val response = chain.proceed(chain.request())
            if (response.code == 403 && response.header("cf-mitigated") == "challenge") {
                response.close()
                throw java.io.IOException("CloudflareException: ${chain.request().url}")
            }
            response
        }
    @Volatile var client: OkHttpClient = builder().build()
        private set
    fun configure(proxy: String?, dns: Map<String, String>, userAgent: String?) {
        if (!userAgent.isNullOrBlank()) this.userAgent = userAgent
        val builder = builder()
        val uri = proxy?.let(::URI)
        if (uri == null) builder.proxy(Proxy.NO_PROXY)
        else {
            require(uri.scheme == "http") { "This extension runtime requires an HTTP proxy" }
            builder.proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress(uri.host, if (uri.port < 0) 80 else uri.port)))
            val auth = uri.rawUserInfo?.split(':', limit = 2)
            if (auth != null) {
                fun decode(value: String) = URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
                val credential = Credentials.basic(decode(auth[0]), decode(auth.getOrElse(1) { "" }))
                builder.proxyAuthenticator { _, response ->
                    if (response.request.header("Proxy-Authorization") != null) null
                    else response.request.newBuilder().header("Proxy-Authorization", credential).build()
                }
            }
        }
        builder.dns { hostname -> dns[hostname]?.let { listOf(InetAddress.getByName(it)) } ?: Dns.SYSTEM.lookup(hostname) }
        client = builder.build()
    }
    val cloudflareClient: OkHttpClient get() = client
    fun defaultUserAgentProvider() = userAgent
}
