import XCTest
import UniformTypeIdentifiers
import ZIPFoundation
@testable import MangaReader

final class EPUBTests: XCTestCase {
    private func zip(_ entries: [(String, String)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, text) in entries {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
            }
        }
        return url
    }

    private let container = """
    <?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
    <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
    """

    func testImageBasedBookIsReadInSpineOrder() async throws {
        // Spine order is p2 then p1, the opposite of file order, and mixes an XHTML <img> with an SVG <image>.
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>
          <item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
          <item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
          <item id="c" href="images/direct.png" media-type="image/png"/>
        </manifest><spine><itemref idref="b"/><itemref idref="a"/><itemref idref="c"/></spine></package>
        """
        let url = try zip([
            ("META-INF/container.xml", container),
            ("OEBPS/content.opf", opf),
            ("OEBPS/text/a.xhtml", #"<html xmlns="http://www.w3.org/1999/xhtml"><body><img src="../images/p1.png"/></body></html>"#),
            ("OEBPS/text/b.xhtml", #"<html xmlns="http://www.w3.org/1999/xhtml"><body><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="../images/p%32.png"/></svg></body></html>"#),
            ("OEBPS/images/p1.png", "ONE"),
            ("OEBPS/images/p2.png", "TWO"),
            ("OEBPS/images/direct.png", "DIRECT")
        ])
        let book = try EPUBArchive(url: url)
        XCTAssertEqual(book.pageCount, 3)
        let pages = try await [book.pageData(at: 0), book.pageData(at: 1), book.pageData(at: 2)]
            .map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(pages, ["TWO", "ONE", "DIRECT"])
        do { _ = try await book.pageData(at: 3); XCTFail("expected pageOutOfRange") } catch {}
    }

    func testReflowableTextBookIsRejected() throws {
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>
          <item id="t" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="t"/></spine></package>
        """
        let url = try zip([("META-INF/container.xml", container), ("OEBPS/content.opf", opf),
                           ("OEBPS/ch1.xhtml", "<html><body><p>Just words.</p></body></html>")])
        XCTAssertThrowsError(try EPUBArchive(url: url)) { error in
            guard case CBZError.noImages = error else { return XCTFail("\(error)") }
        }
    }

    func testNotAnEPUBIsUnreadable() throws {
        let url = try zip([("hello.txt", "hi")])
        XCTAssertThrowsError(try EPUBArchive(url: url)) { error in
            guard case CBZError.unreadable = error else { return XCTFail("\(error)") }
        }
    }

    func testPathResolution() {
        XCTAssertEqual(EPUBArchive.resolve("../images/p1.png", relativeTo: "OEBPS/text/a.xhtml"), "OEBPS/images/p1.png")
        XCTAssertEqual(EPUBArchive.resolve("p.png#frag", relativeTo: "OEBPS/content.opf"), "OEBPS/p.png")
        XCTAssertEqual(EPUBArchive.resolve("my%20page.png?x=1", relativeTo: "a/b.xhtml"), "a/my page.png")
        XCTAssertEqual(EPUBArchive.resolve("/root/p.png", relativeTo: "a/b.xhtml"), "root/p.png")
        XCTAssertEqual(EPUBArchive.resolve("../../../escape.png", relativeTo: "a/b.xhtml"), "escape.png")
        XCTAssertEqual(EPUBArchive.resolve("./x.png", relativeTo: "content.opf"), "x.png")
    }

    func testDataURIImagesAreIgnored() {
        XCTAssertNil(EPUBArchive.imageReference(in: Data(#"<html><body><img src="data:image/png;base64,AAAA"/></body></html>"#.utf8)))
    }

    func testImportedEPUBsKeepTheirExtensionSoTheyOpenAsEPUBs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("book.epub")
        XCTAssertEqual(url.pathExtension.lowercased(), "epub")
        XCTAssertTrue(UTType.comicArchives.contains(.epub))
    }
}
