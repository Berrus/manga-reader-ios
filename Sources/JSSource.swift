import Foundation
import JavaScriptCore

struct JSSourceManifest: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var version: String
    /// Hosts the script may fetch from (exact host or parent domain). Everything else is blocked.
    var hosts: [String]
    var script: String
}

enum JSSourceError: LocalizedError {
    case invalidManifest(String)
    case scriptFailed(String)
    case hostBlocked(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let m): return "Invalid source: \(m)"
        case .scriptFailed(let m): return "Source error: \(m)"
        case .hostBlocked(let u): return "Blocked request to \(u)"
        case .timedOut: return "The source took too long to respond."
        }
    }
}

/// Runs a source script in JavaScriptCore. The script gets no file or system access: only
/// `fetch` (HTTPS, declared hosts only, rate limited, size capped) and pure JavaScript.
final class JSSource: Source, @unchecked Sendable {
    let manifest: JSSourceManifest
    var id: String { manifest.id }
    var name: String { manifest.name }

    private let queue: DispatchQueue
    private let context: JSContext
    private let session: URLSession
    private let redirectGuard: RedirectGuard
    private let limiter = RateLimiter(interval: 0.4)
    private let hosts: [String]

    static let maxResponseBytes = 10_000_000
    static let callTimeout: TimeInterval = 60

    private static let shim = """
    var console = { log: function() {} };
    var fetch = function(url, opts) {
      return new Promise(function(resolve, reject) {
        __nativeFetch(String(url), JSON.stringify(opts || {}),
          function(r) {
            var o = JSON.parse(r);
            o.json = function() { return JSON.parse(o.text); };
            resolve(o);
          },
          function(e) { reject(new Error(e)); });
      });
    };
    function __call(name, args, ok, err) {
      Promise.resolve().then(function() {
        if (typeof source === 'undefined' || typeof source[name] !== 'function') {
          throw new Error('Source does not implement ' + name);
        }
        return source[name].apply(source, JSON.parse(args));
      }).then(
        function(r) { ok(JSON.stringify(r === undefined ? null : r)); },
        function(e) { err(String((e && e.message) || e)); });
    }
    """

    init(manifest: JSSourceManifest) throws {
        guard let context = JSContext() else { throw JSSourceError.invalidManifest("No JavaScript engine") }
        self.manifest = manifest
        self.context = context
        self.queue = DispatchQueue(label: "source.\(manifest.id)")
        let hosts = manifest.hosts.map { $0.lowercased() }
        self.hosts = hosts
        let guardObject = RedirectGuard(hosts: hosts)
        self.redirectGuard = guardObject
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config, delegate: guardObject, delegateQueue: nil)

        var loadError: String?
        queue.sync {
            context.exceptionHandler = { _, exception in loadError = exception?.toString() }

            let fetchBlock: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] url, options, resolve, reject in
                guard let self else { return }
                self.performFetch(url, options) { result in
                    self.queue.async {
                        switch result {
                        case .success(let json): resolve.call(withArguments: [json])
                        case .failure(let error): reject.call(withArguments: [error.localizedDescription])
                        }
                    }
                }
            }
            context.setObject(fetchBlock, forKeyedSubscript: "__nativeFetch" as NSString)
            context.evaluateScript(Self.shim)
            context.evaluateScript(manifest.script)
        }
        if let loadError { throw JSSourceError.scriptFailed(loadError) }
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        try await call("search", [query, page])
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        try await call("details", [manga.id])
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        try await call("chapters", [manga.id])
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        try await call("pages", [chapter.id])
    }

    // MARK: Bridge

    private func call<T: Decodable>(_ name: String, _ args: [Any]) async throws -> T {
        let argsData = try JSONSerialization.data(withJSONObject: args)
        let argsJSON = String(decoding: argsData, as: UTF8.self)

        let json: String = try await withCheckedThrowingContinuation { continuation in
            let once = OneShot()
            let ok: @convention(block) (String) -> Void = { result in
                if once.claim() { continuation.resume(returning: result) }
            }
            let err: @convention(block) (String) -> Void = { message in
                if once.claim() { continuation.resume(throwing: JSSourceError.scriptFailed(message)) }
            }
            // Timeout runs off the JS queue so a runaway script can't block it.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.callTimeout) {
                if once.claim() { continuation.resume(throwing: JSSourceError.timedOut) }
            }
            queue.async {
                guard let function = self.context.objectForKeyedSubscript("__call") else {
                    if once.claim() { continuation.resume(throwing: JSSourceError.scriptFailed("Engine not ready")) }
                    return
                }
                function.call(withArguments: [
                    name, argsJSON,
                    unsafeBitCast(ok as @convention(block) (String) -> Void, to: AnyObject.self),
                    unsafeBitCast(err as @convention(block) (String) -> Void, to: AnyObject.self)
                ])
            }
        }

        do { return try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        catch { throw JSSourceError.scriptFailed("Unexpected data from \(name): \(error.localizedDescription)") }
    }

    // MARK: Network

    static func isAllowed(host: String, in hosts: [String]) -> Bool {
        let host = host.lowercased()
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func performFetch(_ urlString: String, _ optionsJSON: String,
                              completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: urlString), url.scheme == "https",
              let host = url.host, Self.isAllowed(host: host, in: hosts) else {
            completion(.failure(JSSourceError.hostBlocked(urlString)))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        if let data = optionsJSON.data(using: .utf8),
           let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let method = (options["method"] as? String)?.uppercased() ?? "GET"
            request.httpMethod = ["GET", "POST"].contains(method) ? method : "GET"
            if let headers = options["headers"] as? [String: Any] {
                for (key, value) in headers where key.lowercased() != "host" {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
            if request.httpMethod == "POST", let body = options["body"] as? String {
                request.httpBody = Data(body.utf8)
            }
        }

        let delay = limiter.reserve()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [session] in
            session.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                guard let http = response as? HTTPURLResponse, let data else {
                    completion(.failure(JSSourceError.scriptFailed("No response")))
                    return
                }
                guard data.count <= Self.maxResponseBytes else {
                    completion(.failure(JSSourceError.scriptFailed("Response too large")))
                    return
                }
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
                let object: [String: Any] = [
                    "status": http.statusCode,
                    "headers": headers,
                    "text": String(decoding: data, as: UTF8.self)
                ]
                do {
                    let json = try JSONSerialization.data(withJSONObject: object)
                    completion(.success(String(decoding: json, as: UTF8.self)))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }
}

// MARK: - Helpers

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    let hosts: [String]
    init(hosts: [String]) { self.hosts = hosts }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, url.scheme == "https", let host = url.host,
           JSSource.isAllowed(host: host, in: hosts) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

private final class RateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var next = Date.distantPast
    private let interval: TimeInterval
    init(interval: TimeInterval) { self.interval = interval }

    /// Seconds to wait before the next request may go out.
    func reserve() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let slot = max(now, next)
        next = slot.addingTimeInterval(interval)
        return slot.timeIntervalSince(now)
    }
}

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
