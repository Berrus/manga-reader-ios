#if !APP_STORE
import Foundation
import JavaScriptCore

/// One entry of a Paperback 0.9 repository's `versioning.json` (also saved as the installed record).
struct PaperbackExtensionInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var version: String
    var language: String?
    var contentRating: String?
    var repository: String? = nil // base address it was installed from

    /// Extensions rated ADULT are never offered, matching the project rule against adult-content integrations.
    var isAllowed: Bool { contentRating?.uppercased() != "ADULT" }

    static func isValidID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
    }
}

enum PaperbackError: LocalizedError {
    case invalid(String), timedOut, extensionFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .timedOut: return "The extension took too long and was abandoned."
        case .extensionFailed(let message): return "Extension error: \(message)"
        }
    }
}

/// Runs a Paperback 0.9 extension bundle (`index.js`) behind Folio's `Source` interface.
///
/// A fresh JavaScript context is used per call. The extension sees the small `Application` runtime in
/// Sources/PaperbackShim.swift: HTTPS requests to public addresses (cookies and credentials are not stored),
/// per-extension key/value state, and nothing else. Settings forms, discover sections and login are not supported.
final class PaperbackSource: Source, @unchecked Sendable {
    static let timeout: TimeInterval = 60
    static let maxScriptBytes = 3_000_000
    static let maxResponseBytes = 15_000_000
    static let maxItems = 1_000
    static let separator = "\u{1F}"

    let info: PaperbackExtensionInfo
    private let script: String
    var id: String { "pb." + info.id }
    var name: String { info.name }
    var accessPolicy: SourceAccessPolicy { SourceAccessPolicy(hosts: [], anyPublicHTTPS: true) }

    // shortcut: paging only continues from the metadata of the previous page of the same query.
    private let cursors = CursorCache()

    init(info: PaperbackExtensionInfo, script: String) throws {
        guard PaperbackExtensionInfo.isValidID(info.id), info.isAllowed else { throw PaperbackError.invalid("Extension not allowed.") }
        guard script.utf8.count <= Self.maxScriptBytes else { throw TransportError.tooLarge }
        self.info = info
        self.script = script
    }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        var args: [String: Any] = ["query": query]
        if page > 1 {
            guard let cursor = cursors.get(query, page: page - 1) else { return [] }
            args["metadata"] = cursor
        }
        let result: SearchResult = try await call("search", args)
        if let metadata = result.metadataJSON { cursors.set(query, page: page, metadata) }
        return Array(result.items.prefix(Self.maxItems)).compactMap { item in
            guard let id = item.mangaId, !id.isEmpty, let title = item.title, !title.isEmpty else { return nil }
            return MangaSummary(id: id, title: title, coverURL: valid(item.imageUrl))
        }
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let result: PBManga = try await call("details", ["mangaId": manga.id])
        let detail = result.mangaInfo
        return MangaDetails(title: detail?.primaryTitle, coverURL: valid(detail?.thumbnailUrl),
                            author: detail?.author, summary: detail?.synopsis)
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        let rows: [PaperbackChapter] = try await call("chapters", ["mangaId": manga.id, "title": manga.title])
        return rows.prefix(Self.maxItems).compactMap { row in
            guard let chapterID = row.chapterId, !chapterID.isEmpty else { return nil }
            let number = row.chapNum
            let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = title.isEmpty ? (number.map { "Chapter \(Self.format($0))" } ?? "Chapter") : title
            // The extension needs the series id again to open a chapter, so it travels inside the chapter id.
            return ChapterSummary(id: manga.id + Self.separator + chapterID, name: name, number: number)
        }
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        let parts = chapter.id.components(separatedBy: Self.separator)
        guard parts.count >= 2 else { throw PaperbackError.invalid("Unknown chapter id.") }
        let mangaID = parts[0], chapterID = parts.dropFirst().joined(separator: Self.separator)
        let rows: [PaperbackPage] = try await call("pages", ["mangaId": mangaID, "chapterId": chapterID])
        return try rows.prefix(Self.maxItems).map { row in
            guard let url = URL(string: row.url), accessPolicy.allows(url) else { throw TransportError.blocked }
            return PageSource(url: row.url, headers: row.headers?.isEmpty == false ? row.headers : nil)
        }
    }

    private func valid(_ address: String?) -> String? {
        guard let address, let url = URL(string: address), accessPolicy.allows(url) else { return nil }
        return address
    }
    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    // MARK: Execution

    private func call<T: Decodable>(_ method: String, _ args: [String: Any]) async throws -> T {
        let run = Run(id: info.id, method: method, args: args, script: script, policy: accessPolicy)
        let json = try await run.start()
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    struct SearchResult: Decodable {
        var items: [Item]
        var metadataJSON: String?
        struct Item: Decodable { var mangaId: String?; var title: String?; var imageUrl: String? }
        enum CodingKeys: String, CodingKey { case items, metadata }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
            // Opaque to us: handed back to the extension untouched when the next page is requested.
            if let value = try? c.decode(AnyJSON.self, forKey: .metadata),
               let data = try? JSONSerialization.data(withJSONObject: value.raw, options: [.fragmentsAllowed]) {
                metadataJSON = String(decoding: data, as: UTF8.self)
            }
        }
    }
    struct PBManga: Decodable {
        var mangaInfo: Info?
        struct Info: Decodable { var primaryTitle: String?; var thumbnailUrl: String?; var synopsis: String?; var author: String? }
    }
    struct PaperbackChapter: Decodable { var chapterId: String?; var title: String?; var chapNum: Double? }
    struct PaperbackPage: Decodable { var url: String; var headers: [String: String]? }
}

private final class CursorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func get(_ query: String, page: Int) -> Any? {
        lock.lock(); defer { lock.unlock() }
        guard let json = values["\(page)|\(query)"] else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }
    func set(_ query: String, page: Int, _ json: String) {
        lock.lock(); defer { lock.unlock() }
        if values.count > 50 { values.removeAll() }
        values["\(page)|\(query)"] = json
    }
}

/// Decodes any JSON value so it can be re-serialised unchanged.
private struct AnyJSON: Decodable {
    let raw: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { raw = NSNull() }
        else if let v = try? c.decode(Bool.self) { raw = v }
        else if let v = try? c.decode(Double.self) { raw = v }
        else if let v = try? c.decode(String.self) { raw = v }
        else if let v = try? c.decode([AnyJSON].self) { raw = v.map(\.raw) }
        else if let v = try? c.decode([String: AnyJSON].self) { raw = v.mapValues(\.raw) }
        else { raw = NSNull() }
    }
}

/// One extension call: builds the context, runs the shim and the bundle, and resolves once the promise settles.
private final class Run: @unchecked Sendable {
    private let id: String, method: String, args: [String: Any], script: String, policy: SourceAccessPolicy
    private let lock = NSLock()
    private var context: JSContext?
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false

    init(id: String, method: String, args: [String: Any], script: String, policy: SourceAccessPolicy) {
        self.id = id; self.method = method; self.args = args; self.script = script; self.policy = policy
    }

    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { self.execute() }
            DispatchQueue.global().asyncAfter(deadline: .now() + PaperbackSource.timeout) {
                self.finish(.failure(PaperbackError.timedOut))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        self.context = nil // breaks the context <-> callback cycle
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func execute() {
        let shim = PaperbackShim.source
        guard let context = JSContext() else {
            finish(.failure(PaperbackError.invalid("The script runtime is missing."))); return
        }
        lock.lock(); self.context = context; lock.unlock()
        context.exceptionHandler = { [weak self] _, exception in
            self?.finish(.failure(PaperbackError.extensionFailed(exception?.toString() ?? "unknown")))
        }
        installNative(in: context)
        context.evaluateScript(shim)
        context.evaluateScript(script)
        let ok: @convention(block) (String) -> Void = { [weak self] json in self?.finish(.success(json)) }
        let fail: @convention(block) (String) -> Void = { [weak self] message in
            self?.finish(.failure(PaperbackError.extensionFailed(message)))
        }
        context.setObject(ok, forKeyedSubscript: "__ok" as NSString)
        context.setObject(fail, forKeyedSubscript: "__fail" as NSString)
        context.setObject(id, forKeyedSubscript: "__id" as NSString)
        context.setObject(method, forKeyedSubscript: "__method" as NSString)
        context.setObject(args, forKeyedSubscript: "__args" as NSString)
        context.evaluateScript("__run(__id, __method, __args).then(__ok, function (e) { __fail(String(e && e.message || e)); });")
    }

    private func installNative(in context: JSContext) {
        let policy = self.policy, stateID = self.id
        let request: @convention(block) (String, JSValue, JSValue) -> Void = { json, ok, fail in
            let callbacks = Callbacks(ok: ok, fail: fail)
            guard let spec = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                  let address = spec["url"] as? String, let url = URL(string: address), policy.allows(url) else {
                callbacks.fail.call(withArguments: ["Blocked address."]); return
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = (spec["method"] as? String)?.uppercased() == "POST" ? "POST" : "GET"
            if let headers = spec["headers"] as? [String: String] {
                for (key, value) in headers.prefix(30) where key.lowercased() != "host" { urlRequest.setValue(value, forHTTPHeaderField: key) }
            }
            if let body = spec["body"] as? String, urlRequest.httpMethod == "POST" { urlRequest.httpBody = Data(body.utf8) }
            let prepared = urlRequest
            Task.detached {
                do {
                    let (data, response) = try await SourceTransport.load(prepared, policy: policy, maxBytes: PaperbackSource.maxResponseBytes)
                    var headers: [String: String] = [:]
                    for (key, value) in response.allHeaderFields { headers["\(key)"] = "\(value)" }
                    let payload: [String: Any] = ["url": response.url?.absoluteString ?? address, "status": response.statusCode,
                                                  "headers": headers, "body": data.base64EncodedString()]
                    let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
                    callbacks.ok.call(withArguments: [text])
                } catch { callbacks.fail.call(withArguments: [error.localizedDescription]) }
            }
        }
        let sleep: @convention(block) (Double, JSValue) -> Void = { ms, done in
            let box = Callbacks(ok: done, fail: done)
            DispatchQueue.global().asyncAfter(deadline: .now() + min(max(ms, 0), 10_000) / 1000) { box.ok.call(withArguments: []) }
        }
        let getState: @convention(block) (String) -> Any = { key in
            UserDefaults.standard.string(forKey: "pbstate.\(stateID).\(key)") ?? NSNull()
        }
        let setState: @convention(block) (String, Any) -> Void = { key, value in
            let name = "pbstate.\(stateID).\(key)"
            if let text = value as? String { UserDefaults.standard.set(text, forKey: name) }
            else { UserDefaults.standard.removeObject(forKey: name) }
        }
        let native = JSValue(newObjectIn: context)
        native?.setObject(request, forKeyedSubscript: "request" as NSString)
        native?.setObject(sleep, forKeyedSubscript: "sleep" as NSString)
        native?.setObject(getState, forKeyedSubscript: "getState" as NSString)
        native?.setObject(setState, forKeyedSubscript: "setState" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }
}

private final class Callbacks: @unchecked Sendable {
    let ok: JSValue, fail: JSValue
    init(ok: JSValue, fail: JSValue) { self.ok = ok; self.fail = fail }
}
#endif
