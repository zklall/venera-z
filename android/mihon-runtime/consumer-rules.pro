# Types extensions implement, extend or construct
-keep class eu.kanade.tachiyomi.source.Source { public protected *; }
-keep class eu.kanade.tachiyomi.source.Source$DefaultImpls { public protected *; }
-keep class eu.kanade.tachiyomi.source.CatalogueSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.CatalogueSource$DefaultImpls { public protected *; }
-keep class eu.kanade.tachiyomi.source.ConfigurableSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.SourceFactory { public protected *; }
-keep class eu.kanade.tachiyomi.source.UnmeteredSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Filter { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Filter$* { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.FilterList { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.MangasPage { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Page { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SChapter { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SChapter$Companion { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SManga { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SManga$Companion { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SMangaUpdate { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.UpdateStrategy { public protected *; }
-keep class eu.kanade.tachiyomi.source.online.HttpSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.online.ParsedHttpSource { public protected *; }

# Final classes and top-level functions extensions only call into
-keep,allowoptimization class eu.kanade.tachiyomi.AppInfo { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.HttpException { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.JavaScriptEngine { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.NetworkHelper { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.OkHttpExtensionsKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.RequestsKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.interceptor.RateLimitInterceptorKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.interceptor.SpecificHostRateLimitInterceptorKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.util.JsoupExtensionsKt { public protected *; }

# Extensions are external dex clients: these APIs must retain their JVM names.
-keep class okhttp3.** { public protected *; }
-keep class okio.** { public protected *; }
-keep class org.jsoup.** { public protected *; }
-keep class rx.** { public protected *; }
-keep class uy.kohesive.injekt.** { *; }
# Inlined Injekt tokens are generated in the host's package, outside the rules
# above. FullTypeReference reads their generic superclass during construction.
-keepattributes Signature,InnerClasses,EnclosingMethod
-keep class * extends uy.kohesive.injekt.api.FullTypeReference { *; }
-keep class kotlinx.serialization.** { public protected *; }
-keep class kotlinx.coroutines.** { public protected *; }
-keep class kotlin.** { public protected *; }
-keep class androidx.preference.** { public protected *; }
# Extensions can directly link to and reflect on the host's copied API,
# including private lazy delegates and top-level helper functions.
-keep class eu.kanade.tachiyomi.** { *; }
-keep class mihon.core.common.** { *; }
-keep class tachiyomi.core.common.** { *; }
# Some extensions call the Zstd/Okio bridge directly, outside the host's code.
-keep class com.squareup.zstd.** { *; }
-keep class eu.kanade.tachiyomi.network.AndroidCookieJar { public protected *; }

# R8 must not place host internals in the default package: extension APKs
# often contain obfuscated classes such as `m`, loaded parent-first.
-repackageclasses 'com.github.veneraz.mihon.host.internal'
