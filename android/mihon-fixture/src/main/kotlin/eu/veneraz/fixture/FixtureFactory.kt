package eu.veneraz.fixture

import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.source.model.*
import eu.kanade.tachiyomi.network.GET
import okhttp3.Headers
import okhttp3.Request
import okhttp3.Response
import okhttp3.RequestBody.Companion.toRequestBody
import rx.Observable

class FixtureFactory : SourceFactory {
    override fun createSources(): List<Source> = listOf(FixtureSource(900001), FixtureSource(900002))
}

/** Uses legacy Rx overrides to verify old extensions on the modern host API. */
class FixtureSource(override val id: Long) : HttpSource() {
    override val name = "Local fixture $id"
    override val lang = "zh"
    override val supportsLatest = true
    override val baseUrl = System.getProperty("venera.fixture.url") ?: "http://127.0.0.1:1"
    override fun headersBuilder() = Headers.Builder().add("X-Fixture", "source-header")
    private fun book() = SManga.create().apply {
        url = "/book/1"; title = "Fixture book"; thumbnail_url = "$baseUrl/cover"; author = "Fixture author"
    }
    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> = Observable.fromCallable {
        client.newCall(GET("$baseUrl/search?page=$page", headers)).execute().use {
            check(it.isSuccessful)
            check(it.body.string() == "fixture")
        }
        MangasPage(listOf(book()), page == 1)
    }
    override fun fetchPopularManga(page: Int) = fetchSearchManga(page, "", FilterList())
    override fun fetchLatestUpdates(page: Int) = fetchPopularManga(page)
    override fun fetchMangaDetails(manga: SManga): Observable<SManga> = Observable.just(book())
    override fun fetchChapterList(manga: SManga): Observable<List<SChapter>> = Observable.just(listOf(
        SChapter.create().apply { url = "/ep/2"; name = "Chapter 2" },
        SChapter.create().apply { url = "/ep/1"; name = "Chapter 1" },
    ))
    override fun fetchPageList(chapter: SChapter): Observable<List<Page>> = Observable.just(listOf(
        Page(0, "$baseUrl/resolve/0"), Page(1, "$baseUrl/resolve/1"),
    ))
    override fun imageUrlParse(response: Response) = response.body.string()
    override fun imageRequest(page: Page): Request = Request.Builder()
        .url(page.imageUrl!!).headers(headers).post("fixture".toRequestBody())
        .addHeader("X-Image-Method", "custom-post").build()
}
