import SwiftUI
import UniformTypeIdentifiers

struct CoverImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct FullCoverView: View {
    let title: String
    let data: Data?
    @State private var image: UIImage?
    @State private var jpeg: Data?
    @State private var export = false
    @State private var message: String?
    @State private var zoom = false

    var body: some View {
        GeometryReader { geometry in
        ScrollView([.horizontal, .vertical]) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: zoom ? max(600, image.size.width) : max(1, min(600, geometry.size.width - 32)))
                        .accessibilityLabel("Full cover for \(title)")
                } else {
                    ContentUnavailableView("Cover unavailable", systemImage: "photo",
                        description: Text("This entry has no readable cover image."))
                }
            }.padding()
        }
        }
        .navigationTitle("Cover")
        .toolbar {
            Button(zoom ? "Fit cover" : "Enlarge cover", systemImage: "plus.magnifyingglass") { zoom.toggle() }
                .disabled(image == nil)
            if let jpeg, let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview(title, image: Image(uiImage: image))) {
                    Label("Share cover", systemImage: "square.and.arrow.up")
                }
                Button("Save cover", systemImage: "square.and.arrow.down") { export = true }
                    .fileExporter(isPresented: $export, document: CoverImageDocument(data: jpeg),
                                  contentType: .jpeg, defaultFilename: "Folio-cover") { result in
                        if case .failure(let error) = result { message = error.localizedDescription }
                    }
            }
        }
        .task {
            guard let data, data.count <= 30_000_000 else { return }
            let decoded = await Task.detached(priority: .utility) {
                ImageDownsampler.image(from: data, maxPixel: 4096)
            }.value
            guard !Task.isCancelled else { return }
            image = decoded; jpeg = decoded?.jpegData(compressionQuality: 0.9)
        }
        .alert("Cover export", isPresented: Binding(get: { message != nil },
            set: { if !$0 { message = nil } })) { Button("OK") { message = nil } }
            message: { Text(message ?? "") }
    }
}
