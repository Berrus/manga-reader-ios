import XCTest
@testable import MangaReader

final class OPDSTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.5:5000/api/opds/KEY")!

    private let feedXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:pse="http://vaemendis.net/opds-pse/ns">
      <title>My Library</title><subtitle>All series</subtitle>
      <link rel="search" type="application/atom+xml" href="/api/opds/KEY/search?query={searchTerms}"/>
      <link rel="next" type="application/atom+xml;profile=opds-catalog" href="/api/opds/KEY/all?page=2"/>
      <entry><title>Series A</title>
        <link rel="subsection" type="application/atom+xml;profile=opds-catalog;kind=acquisition" href="/api/opds/KEY/series/1"/>
        <link rel="http://opds-spec.org/image/thumbnail" type="image/jpeg" href="/api/image/1"/></entry>
      <entry><title>Chapter 1</title>
        <link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" href="/api/opds/KEY/chapter/1/image?page={pageNumber}" pse:count="3"/>
        <link rel="alternate" type="application/atom+xml;type=entry;profile=opds-catalog" href="/api/opds/KEY/chapter/1"/></entry>
    </feed>
    """

    func testFeedParsingFindsSeriesChaptersSearchAndPaging() throws {
        let feed = try OPDSFeed.parse(Data(feedXML.utf8), url: base)
        XCTAssertEqual(feed.title, "My Library")
        XCTAssertEqual(feed.subtitle, "All series")
        XCTAssertEqual(feed.entries.map(\.title), ["Series A", "Chapter 1"])

        let series = feed.entries[0]
        XCTAssertNil(series.streamLink)
        XCTAssertEqual(series.navigationURL?.absoluteString, "http://192.168.1.5:5000/api/opds/KEY/series/1")
        XCTAssertEqual(series.thumbnailURL?.absoluteString, "http://192.168.1.5:5000/api/image/1")

        let chapter = feed.entries[1]
        XCTAssertEqual(chapter.streamLink?.pageCount, 3)
        XCTAssertNil(chapter.navigationURL, "an entry-detail link is not a series")

        XCTAssertEqual(feed.searchTemplate, "/api/opds/KEY/search?query={searchTerms}")
        XCTAssertEqual(feed.nextURL?.absoluteString, "http://192.168.1.5:5000/api/opds/KEY/all?page=2")
    }

    func testNonXMLIsNotAnOPDSCatalog() {
        XCTAssertThrowsError(try OPDSFeed.parse(Data("{\"json\":true}".utf8), url: base))
    }

    func testChapterIdRoundTripsAndRejectsBadValues() throws {
        let id = OPDSSource.chapterID(template: "/img?page={pageNumber}", count: 24)
        let parsed = try XCTUnwrap(OPDSSource.parseChapterID(id))
        XCTAssertEqual(parsed.template, "/img?page={pageNumber}")
        XCTAssertEqual(parsed.count, 24)
        XCTAssertNil(OPDSSource.parseChapterID("0\n/img"))
        XCTAssertNil(OPDSSource.parseChapterID("abc\n/img"))
        XCTAssertNil(OPDSSource.parseChapterID("999999\n/img"))
        XCTAssertNil(OPDSSource.parseChapterID("no newline"))
    }

    func testPageAndSearchURLs() {
        XCTAssertEqual(OPDSSource.pageURL(template: "/api/opds/KEY/chapter/1/image?page={pageNumber}&w={maxWidth}", index: 4, base: base)?.absoluteString,
                       "http://192.168.1.5:5000/api/opds/KEY/chapter/1/image?page=4&w=2400")
        XCTAssertEqual(OPDSSource.searchURL(template: "/s?query={searchTerms}", query: "one piece & co", base: base)?.absoluteString,
                       "http://192.168.1.5:5000/s?query=one%20piece%20&%20co")
    }

    func testSourceSetupIsLocalOnlyForPlainHTTP() {
        func make(_ url: String) -> OPDSSource? {
            OPDSSource(config: ServerConfig(kind: .opds, name: "K", url: url, username: ""), password: "")
        }
        XCTAssertNotNil(make("http://192.168.1.5:5000/api/opds/KEY"))
        XCTAssertNotNil(make("https://kavita.example.com/api/opds/KEY"))
        XCTAssertNil(make("http://kavita.example.com/api/opds/KEY"))
        XCTAssertNil(make("https://user:pw@kavita.example.com/api/opds/KEY"))
        XCTAssertTrue(make("http://192.168.1.5:5000")?.id.hasPrefix("opds.") == true)
    }
}
