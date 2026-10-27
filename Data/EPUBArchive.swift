import Foundation
import ZIPFoundation

/// Reads comic EPUBs: books where every page of the reading order is an image, or a small XHTML/SVG
/// page that wraps one (the usual manga and fixed-layout format). Reflowable text books have no page
/// images and are rejected with `CBZError.noImages`.
actor EPUBArchive: PageProvider {
    private let archive: Archive
    private let entries: [Entry]
    nonisolated let pageCount: Int

    private static let maxXMLBytes: UInt64 = 2_000_000

    init(url: URL) throws {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read, pathEncoding: nil) }
        catch { throw CBZError.unreadable }
        let entries = try Self.pagePaths(in: archive).compactMap { archive[$0] }
        guard !entries.isEmpty else { throw CBZError.noImages }
        self.archive = archive
        self.entries = entries
        self.pageCount = entries.count
    }

    func pageData(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw CBZError.pageOutOfRange }
        guard UInt64(entries[index].uncompressedSize) <= UInt64(CBZArchive.maxPageBytes) else { throw CBZError.pageTooLarge }
        var data = Data()
        _ = try archive.extract(entries[index]) { chunk in
            guard chunk.count <= CBZArchive.maxPageBytes - data.count else { throw CBZError.pageTooLarge }
            data.append(chunk)
        }
        return data
    }

    // MARK: Reading order

    /// Image paths in the book's reading order.
    private static func pagePaths(in archive: Archive) throws -> [String] {
        guard let container = archive["META-INF/container.xml"],
              let opfPath = rootfilePath(in: try text(of: container, in: archive)),
              let opf = archive[opfPath] else { throw CBZError.unreadable }
        var paths: [String] = []
        for item in spineItems(in: try text(of: opf, in: archive), opfPath: opfPath) {
            if item.mediaType.hasPrefix("image/") {
                paths.append(item.path)
            } else if let page = archive[item.path],
                      let reference = imageReference(in: try text(of: page, in: archive)) {
                paths.append(resolve(reference, relativeTo: item.path))
            }
        }
        return paths
    }

    private static func text(of entry: Entry, in archive: Archive) throws -> Data {
        guard UInt64(entry.uncompressedSize) <= maxXMLBytes else { throw CBZError.pageTooLarge }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    // MARK: Parsing (pure, unit tested)

    static func rootfilePath(in container: Data) -> String? {
        var path: String?
        scan(container) { name, attributes in
            if name == "rootfile", path == nil { path = attributes["full-path"] }
        }
        return path
    }

    /// Spine entries (in reading order) as archive paths with their media types.
    static func spineItems(in opf: Data, opfPath: String) -> [(path: String, mediaType: String)] {
        var manifest: [String: (href: String, type: String)] = [:]
        var order: [String] = []
        scan(opf) { name, attributes in
            if name == "item", let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = (href, attributes["media-type"] ?? "")
            } else if name == "itemref", let idref = attributes["idref"] {
                order.append(idref)
            }
        }
        return order.compactMap { id in
            manifest[id].map { (resolve($0.href, relativeTo: opfPath), $0.type) }
        }
    }

    /// The first image a page shows: an `<img src>` or an SVG `<image xlink:href>`.
    static func imageReference(in xhtml: Data) -> String? {
        var reference: String?
        scan(xhtml) { name, attributes in
            guard reference == nil else { return }
            let value = name == "img" ? attributes["src"] : name == "image" ? (attributes["xlink:href"] ?? attributes["href"]) : nil
            if let value, !value.hasPrefix("data:") { reference = value }
        }
        return reference
    }

    /// Resolves `href` against the folder of `file`, collapsing `.` and `..`, dropping `#fragment`/`?query`
    /// and percent-encoding. Zip paths have no leading slash.
    static func resolve(_ href: String, relativeTo file: String) -> String {
        let clean = href.split(whereSeparator: { $0 == "#" || $0 == "?" }).first.map(String.init) ?? href
        let decoded = clean.removingPercentEncoding ?? clean
        var parts = decoded.hasPrefix("/") ? [] : (file as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } } else { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }

    // MARK: XML

    private static func scan(_ data: Data, _ onElement: @escaping (String, [String: String]) -> Void) {
        let parser = XMLParser(data: data)
        let scanner = ElementScanner(onElement)
        parser.delegate = scanner
        parser.shouldResolveExternalEntities = false   // never fetch entities from a book
        parser.parse()
    }

    private final class ElementScanner: NSObject, XMLParserDelegate {
        let onElement: (String, [String: String]) -> Void
        init(_ onElement: @escaping (String, [String: String]) -> Void) { self.onElement = onElement }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            // "svg:image" and "image" are the same element; attribute names keep their prefix.
            onElement(elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName, attributeDict)
        }
    }
}

/// Opens an imported comic file by its type.
enum ComicArchive {
    static func open(url: URL) throws -> (provider: any PageProvider, pageCount: Int) {
        if url.pathExtension.lowercased() == "epub" {
            let book = try EPUBArchive(url: url)
            return (book, book.pageCount)
        }
        let archive = try CBZArchive(url: url)
        return (archive, archive.pageCount)
    }
}
