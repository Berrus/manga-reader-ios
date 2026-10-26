import SwiftUI

import SwiftData

import UniformTypeIdentifiers

struct LibraryView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Manga.addedAt, order: .reverse) private var library: [Manga]

    @State private var showImporter = false

    @State private var errorMessage: String?

    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filtered: [Manga] {

        search.isEmpty ? library : library.filter { $0.title.localizedCaseInsensitiveContains(search) }

    }

    var body: some View {

        NavigationStack {

            Group {

                if library.isEmpty {

                    ContentUnavailableView("Your library is empty", systemImage: "books.vertical",

                        description: Text("Tap + to import a CBZ file."))

                } else {

                    ScrollView {

                        LazyVGrid(columns: columns, spacing: 16) {

                            ForEach(filtered) { manga in

                                NavigationLink(value: manga) { MangaCell(manga: manga) }

                                    .buttonStyle(.plain)

                                    .contextMenu {

                                        Button("Delete", systemImage: "trash", role: .destructive) {

                                            delete(manga)

                                        }

                                    }

                            }

                        }.padding()

                    }

                }

            }

            .navigationTitle("Library")

            .searchable(text: $search)

            .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }

            .toolbar {

                Button("Import", systemImage: "plus") { showImporter = true }

            }

            .fileImporter(isPresented: $showImporter,

                          allowedContentTypes: UTType.comicArchives,

                          allowsMultipleSelection: true) { result in

                handleImport(result)

            }

            .alert("Import failed", isPresented: .constant(errorMessage != nil)) {

                Button("OK") { errorMessage = nil }

            } message: { Text(errorMessage ?? "") }

        }

    }

    private func handleImport(_ result: Result<[URL], Error>) {

        switch result {

        case .failure(let error): errorMessage = error.localizedDescription

        case .success(let urls):

            Task {

                for url in urls {

                    do { try await LibraryImporter.importFile(at: url, into: nil, context: context) }

                    catch { errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)" }

                }

            }

        }

    }

    private func delete(_ manga: Manga) {

        LibraryImporter.deleteFiles(for: manga)

        context.delete(manga)

    }

}

private struct MangaCell: View {

    let manga: Manga

    var body: some View {

        VStack(alignment: .leading, spacing: 6) {

            ZStack(alignment: .topTrailing) {

                Group {

                    if let data = manga.coverData, let image = UIImage(data: data) {

                        Image(uiImage: image).resizable().scaledToFill()

                    } else {

                        Color.gray.opacity(0.3)

                    }

                }

                .frame(height: 160).frame(maxWidth: .infinity).clipped()

                .clipShape(RoundedRectangle(cornerRadius: 8))

                if manga.unreadCount > 0 {

                    Text("\(manga.unreadCount)")

                        .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)

                        .background(.blue, in: Capsule()).foregroundStyle(.white).padding(6)

                }

            }

            Text(manga.title).font(.caption).lineLimit(2)

        }

    }

}

