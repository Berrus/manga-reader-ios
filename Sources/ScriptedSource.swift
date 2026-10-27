#if !APP_STORE
import Foundation
import CryptoKit
import JavaScriptCore

/// Catalog entry for a JavaScript source. The script is fetched from `entry` and must match `sha256`.
struct ScriptedSourceManifest: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var version: String
    var hosts: [String]
    var entry: String
    var sha256: String
}

enum ScriptedSourceError: LocalizedError {
    case invalid(String), hashMismatch, timedOut, disabled, script(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return "Invalid script source: \(message)"
        case .hashMismatch: return "The script does not match the checksum in its listing."
        case .timedOut: return "The script took too long and was abandoned."
        case .disabled: return "Scripted sources are turned off after repeated timeouts. Restart the app."
        case .script(let message): return "Script error: \(message)"
        }
    }
}

/// Runs a hash-verified JavaScript package against the `Source` contract.
///
/// The script sees only `http.get(url, headers)` (limited to its declared HTTPS hosts) and `log(text)`.
/// Contract: global functions `search(query, page)`, `details(id)`, `chapters(id)`, `pages(id)` that
/// return plain objects shaped like MangaSummary / MangaDetails / ChapterSummary / PageSource.
/// Calls are synchronous from the script's point of view; `http.get` blocks its worker thread.
final class ScriptedSource: Source, @unchecked Sendable {
    static let maxScriptBytes = 256_000
    static let maxResultBytes = 5_000_000
    static let maxItems = 1_000
    static let maxHTTPCalls = 30
    static let timeout: TimeInterval = 20

    // shortcut: JavaScriptCore has no public way to interrupt a running script, so a timed-out
    // script keeps its thread until it ends; after 3 such runs we stop running scripts until relaunch.
    private static let stuck = StuckCounter()

    let manifest: ScriptedSourceManifest
    private let script: String
    var id: String { "js." + manifest.id }
    var name: String { manifest.name }
    var accessPolicy: SourceAccessPolicy { SourceAccessPolicy(hosts: manifest.hosts) }

    init(manifest: ScriptedSourceManifest, script: String) throws {
        try Self.validate(manifest)
        guard script.utf8.count <= Self.maxScriptBytes else { throw TransportError.tooLarge }
        guard Self.sha256(script) == manifest.sha256.lowercased() else { throw ScriptedSourceError.hashMismatch }
        self.manifest = manifest
        self.script = script
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ manifest: ScriptedSourceManifest) throws {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        guard matches(manifest.id, #"^[a-z0-9][a-z0-9._-]{0,63}$"#),
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, manifest.name.count <= 200,
              manifest.version.count <= 40
        else { throw ScriptedSourceError.invalid("Invalid id, name or version.") }
        guard !manifest.hosts.isEmpty, manifest.hosts.count <= 20,
              manifest.hosts.allSatisfy({ matches($0.lowercased(), #"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$"#) })
        else { throw ScriptedSourceError.invalid("Declare the domains this source uses.") }
        guard matches(manifest.sha256.lowercased(), #"^[0-9a-f]{64}$"#) else {
            throw ScriptedSourceError.invalid("Missing SHA-256 checksum.")
        }
        guard manifest.entry.count <= 2048, let url = URL(string: manifest.entry), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil
        else { throw ScriptedSourceError.invalid("The script address must be HTTPS.") }
    }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        let rows = try await call("search", [query, page], as: [MangaSummary].self)
        return try checked(rows) { row in
            if let cover = row.coverURL { try allow(cover) }
        }
    }
    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let details = try await call("details", [manga.id], as: MangaDetails.self)
        if let cover = details.coverURL { try allow(cover) }
        return details
    }
    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        try checked(try await call("chapters", [manga.id], as: [ChapterSummary].self)) { _ in }
    }
    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        try checked(try await call("pages", [chapter.id], as: [PageSource].self)) { try allow($0.url) }
    }

    private func allow(_ address: String) throws {
        guard let url = URL(string: address), accessPolicy.allows(url) else { throw TransportError.blocked }
    }
    private func checked<T>(_ rows: [T], _ each: (T) throws -> Void) throws -> [T] {
        guard rows.count <= Self.maxItems else { throw TransportError.tooLarge }
        try rows.forEach(each)
        return rows
    }

    // MARK: Execution

    private func call<T: Decodable>(_ function: String, _ arguments: [Any], as type: T.Type) async throws -> T {
        if Self.stuck.value >= 3 { throw ScriptedSourceError.disabled }
        let data = try await runWithTimeout(function, arguments)
        guard data.count <= Self.maxResultBytes else { throw TransportError.tooLarge }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func runWithTimeout(_ function: String, _ arguments: [Any]) async throws -> Data {
        let box = ArgumentsBox(arguments)
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try self.execute(function, box.values) }
                if once.claim() { continuation.resume(with: result) }
                else { Self.stuck.add(-1) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
                if once.claim() {
                    Self.stuck.add(1)
                    continuation.resume(throwing: ScriptedSourceError.timedOut)
                }
            }
        }
    }

    /// Runs on a worker thread in a fresh context that is discarded afterwards.
    private func execute(_ function: String, _ arguments: [Any]) throws -> Data {
        guard let context = JSContext() else { throw ScriptedSourceError.script("No script engine.") }
        let failed = FailureBox()
        context.exceptionHandler = { _, exception in failed.message = exception?.toString() }
        installHost(in: context)
        context.evaluateScript(script)
        if let failure = failed.message { throw ScriptedSourceError.script(failure) }
        guard let entry = context.objectForKeyedSubscript(function), entry.isObject,
              let result = entry.call(withArguments: arguments) else {
            throw ScriptedSourceError.script("The script does not define \(function)().")
        }
        if let failure = failed.message { throw ScriptedSourceError.script(failure) }
        guard !result.isUndefined,
              let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [result]),
              json.isString, let text = json.toString() else {
            throw ScriptedSourceError.script("\(function)() returned nothing usable.")
        }
        return Data(text.utf8)
    }

    private func installHost(in context: JSContext) {
        let policy = accessPolicy
        let counter = CallCounter()
        let get: @convention(block) (String, JSValue?) -> Any = { address, headers in
            func fail(_ message: String) -> Any {
                JSContext.current()?.exception = JSValue(newErrorFromMessage: message, in: JSContext.current())
                return NSNull()
            }
            guard counter.next() <= Self.maxHTTPCalls else { return fail("Too many requests.") }
            guard let url = URL(string: address), policy.allows(url) else { return fail("Blocked address.") }
            var request = URLRequest(url: url)
            if let object = headers?.toDictionary() as? [String: Any] {
                for (key, value) in object.prefix(20) {
                    // Cookies and credentials are never available to scripts.
                    guard !["cookie", "authorization", "host"].contains(key.lowercased()),
                          let text = value as? String else { continue }
                    request.setValue(text, forHTTPHeaderField: key)
                }
            }
            let outcome = Outcome()
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let (data, response) = try await SourceTransport.load(request, policy: policy, maxBytes: 10_000_000)
                    outcome.value = .success((response.statusCode, String(decoding: data, as: UTF8.self)))
                } catch { outcome.value = .failure(error) }
                semaphore.signal()
            }
            semaphore.wait()
            switch outcome.value {
            case .success(let pair)?: return ["status": pair.0, "body": pair.1]
            case .failure(let error)?: return fail(error.localizedDescription)
            case nil: return fail("No response.")
            }
        }
        let http = JSValue(newObjectIn: context)
        http?.setObject(get, forKeyedSubscript: "get" as NSString)
        context.setObject(http, forKeyedSubscript: "http" as NSString)
        let log: @convention(block) (String) -> Void = { _ in } // accepted and discarded; scripts never write anywhere
        context.setObject(log, forKeyedSubscript: "log" as NSString)
    }
}

private final class ArgumentsBox: @unchecked Sendable {
    let values: [Any]
    init(_ values: [Any]) { self.values = values }
}
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if claimed { return false }; claimed = true; return true }
}
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
private final class StuckCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func add(_ delta: Int) { lock.lock(); count += delta; lock.unlock() }
}
private final class FailureBox: @unchecked Sendable {
    var message: String?
}
private final class Outcome: @unchecked Sendable {
    var value: Result<(Int, String), Error>?
}
#endif
