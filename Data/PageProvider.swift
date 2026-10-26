import Foundation

/// Anything that can hand the reader the raw bytes of a chapter's pages.
protocol PageProvider: Sendable {
    func pageData(at index: Int) async throws -> Data
}

/// Pages of a downloaded chapter: image files in a folder, sorted by name.
struct DirectoryPages: PageProvider {
    let files: [URL]

    init(directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        files = contents
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !files.isEmpty else { throw CBZError.noImages }
    }

    func pageData(at index: Int) async throws -> Data {
        guard files.indices.contains(index) else { throw CBZError.pageOutOfRange }
        return try Data(contentsOf: files[index])
    }
}
