import Foundation

struct SourceAccessPolicy: Sendable, Equatable {
    var hosts: [String]
    var allowsLocalHTTP = false
    var port: Int? = nil
    /// For sources that declare no domains (Paperback extensions): any public HTTPS address, never local ones.
    var anyPublicHTTPS = false

    func allows(_ url: URL) -> Bool {
        if anyPublicHTTPS {
            guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host else { return false }
            return !Self.isLocal(host)
        }
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased(),
              hosts.contains(where: { host == $0.lowercased() || (port == nil && host.hasSuffix("." + $0.lowercased())) })
        else { return false }
        if let port, (url.port ?? (url.scheme == "https" ? 443 : 80)) != port { return false }
        if url.scheme == "https" { return true }
        return url.scheme == "http" && allowsLocalHTTP && Self.isLocal(host)
    }

    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h == "::1" || h.hasSuffix(".local") { return true }
        if !h.contains(".") && !h.contains(":") { return true }
        if h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe80:") { return h.contains(":") }
        let pieces = h.split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 4, pieces.allSatisfy({ (0...255).contains($0) }) else { return false }
        return pieces[0] == 10 || pieces[0] == 127 ||
            (pieces[0] == 192 && pieces[1] == 168) ||
            (pieces[0] == 172 && (16...31).contains(pieces[1])) ||
            (pieces[0] == 169 && pieces[1] == 254)
    }
}

enum TransportError: LocalizedError {
    case blocked, tooLarge, http(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .blocked: return "The source is not allowed to contact that address."
        case .tooLarge: return "The response exceeds the allowed size."
        case .http(let code): return "The server returned HTTP \(code)."
        case .invalidResponse: return "The server returned an invalid response."
        }
    }
}

/// Every byte is checked before appending. Redirects use the same source policy.
enum SourceTransport {
    static func load(_ request: URLRequest, policy: SourceAccessPolicy, maxBytes: Int,
                     configuration: URLSessionConfiguration? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, policy.allows(url), maxBytes > 0 else { throw TransportError.blocked }
        let operation = BoundedRequest(policy: policy, limit: maxBytes)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.start(request, configuration: configuration, continuation: continuation)
            }
        } onCancel: { operation.cancel() }
    }
}

private final class BoundedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let policy: SourceAccessPolicy
    private let limit: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false
    // URLSession invokes these data/response callbacks on a serial delegate queue.
    private var data = Data()
    private var response: HTTPURLResponse?

    init(policy: SourceAccessPolicy, limit: Int) { self.policy = policy; self.limit = limit }

    func start(_ request: URLRequest, configuration: URLSessionConfiguration?,
               continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let config = configuration ?? .ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(TransportError.invalidResponse)); return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel); finish(.failure(TransportError.http(http.statusCode))); return
        }
        guard http.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(TransportError.tooLarge)); return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        lock.lock(); let ended = finished; lock.unlock()
        guard !ended else { return }
        guard bytes.count <= limit - data.count else { finish(.failure(TransportError.tooLarge)); return }
        data.append(bytes)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((data, response))) }
        else { finish(.failure(TransportError.invalidResponse)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, policy.allows(url) else {
            completionHandler(nil); finish(.failure(TransportError.blocked)); return
        }
        completionHandler(request)
    }
}
