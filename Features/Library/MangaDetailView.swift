import SwiftUI

import SwiftData

import UniformTypeIdentifiers

struct MangaDetailView: View {

    let manga: Manga

    @Environment(\.modelContext) private var context

    @State private var openChapter: Chapter?

    @State private var showImporter = false

    @State private var errorMessage: String?

    var body: some View {

        List {

            Section {

                HStack(alignment: .top, spacing: 12) {

                    cover

                    VStack(alignment: .leading, spacing: 8) {

                        Text(manga.title).font(.headline)

                        Text("\(manga.chapters.count) chapters · \(manga.unreadCount) unread")

                            .font(.caption).foregroundStyle(.secondary)

                        if let resume = manga.resumeChapter {

                            Button {

                                openChapter = resume

                            } label: {

                                Label(resumeLabel, systemImage: "play.fill")

                            }

                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("resumeReading")

                        }

                    }

                }

            }

            Section("Chapters") {

                if manga.chapters.isEmpty {

                    Text("No chapters. Tap + to add CBZ files.").foregroundStyle(.secondary)

                }

                ForEach(manga.sortedChapters) { chapter in

                    Button { openChapter = chapter } label: { ChapterRow(chapter: chapter) }

                        .buttonStyle(.plain)

                        .swipeActions(edge: .leading) {

                            Button(chapter.isRead ? "Unread" : "Read",

                                   systemImage: chapter.isRead ? "eye.slash" : "checkmark") {

                                toggleRead(chapter)

                            }.tint(.blue)

                        }

                        .swipeActions(edge: .trailing) {

                            Button("Delete", systemImage: "trash", role: .destructive) {

                                delete(chapter)

                            }

                        }

                }

            }

        }

        .navigationTitle(manga.title)

        .navigationBarTitleDisplayMode(.inline)

        .navigationDestination(item: $openChapter) { ReaderView(chapter: $0) }

        .toolbar {

            Button("Add chapters", systemImage: "plus") { showImporter = true }

        }

        .fileImporter(isPresented: $showImporter,

                      allowedContentTypes: UTType.comicArchives,

                      allowsMultipleSelection: true) { result in

            handleImport(result)

        }

        .alert("Import failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {

            Button("OK") { errorMessage = nil }

        } message: { Text(errorMessage ?? "") }

    }

    private var resumeLabel: String {

        let started = manga.chapters.contains { $0.isRead || $0.lastPage > 0 }

        return started ? "Continue" : "Start reading"

    }

    @ViewBuilder private var cover: some View {

        if let data = manga.coverData, let image = UIImage(data: data) {

            Image(uiImage: image).resizable().scaledToFill()

                .frame(width: 90, height: 130).clipped()

                .clipShape(RoundedRectangle(cornerRadius: 8))

        } else {

            RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.3)).frame(width: 90, height: 130)

        }

    }

    private func toggleRead(_ chapter: Chapter) {

        chapter.isRead.toggle()

        if !chapter.isRead { chapter.lastPage = 0 }

    }

    private func delete(_ chapter: Chapter) {

        try? FileManager.default.removeItem(at: chapter.fileURL)

        context.delete(chapter)

    }

    private func handleImport(_ result: Result<[URL], Error>) {

        switch result {

        case .failure(let error): errorMessage = error.localizedDescription

        case .success(let urls):

            Task {

                for url in urls {

                    do { try await LibraryImporter.importFile(at: url, into: manga, context: context) }

                    catch { errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)" }

                }

            }

        }

    }

}

private struct ChapterRow: View {

    let chapter: Chapter

    var body: some View {

        HStack {

            VStack(alignment: .leading, spacing: 2) {

                Text(chapter.name).lineLimit(2)

                    .foregroundStyle(chapter.isRead ? .secondary : .primary)

                if chapter.inProgress {

                    Text("Page \(chapter.lastPage + 1) of \(chapter.pageCount)")

                        .font(.caption).foregroundStyle(.blue)

                } else {

                    Text("\(chapter.pageCount) pages").font(.caption).foregroundStyle(.secondary)

                }

            }

            Spacer()

            if chapter.isRead {

                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)

            }

        }

        .contentShape(Rectangle())

    }

}

