import UniformTypeIdentifiers

extension UTType {
    /// Declared as an imported type in Info.plist (see project.yml) so .cbz files are selectable.
    static let cbz = UTType(importedAs: "com.mangareader.cbz", conformingTo: .zip)

    static let comicArchives: [UTType] = [.cbz, .zip]
}
