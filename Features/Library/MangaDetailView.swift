import SwiftUI

import SwiftData

import UniformTypeIdentifiers

struct MangaDetailView: View {

    let manga: Manga

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var openChapter: Chapter?

    @State private var showImporter = false

    @State private var errorMessage: String?

    var body: some View {

        List {

            hero
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if AniListAuth.shared.isConnected {
                TrackingSection(manga: manga)
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

                            }.tint(Theme.accent)

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
        .listStyle(.insetGrouped)

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

    private var coverWidth: CGFloat { sizeClass == .regular ? 150 : 110 }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 16) {
            CoverView(data: manga.coverData, title: manga.title)
                .frame(width: coverWidth)
            VStack(alignment: .leading, spacing: 10) {
                Text(manga.title).font(.title2.bold()).lineLimit(4)
                HStack(spacing: 6) {
                    Pill(text: "\(manga.chapters.count) chapters", systemImage: "books.vertical")
                    if manga.unreadCount > 0 { Pill(text: "\(manga.unreadCount) unread") }
                }
                if manga.progress > 0 {
                    ProgressView(value: manga.progress).tint(Theme.accent)
                }
                if let resume = manga.resumeChapter {
                    Button {
                        openChapter = resume
                    } label: {
                        Label(resumeLabel, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("resumeReading")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius + 6, style: .continuous))
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder private var backdrop: some View {
        ZStack {
            if let data = manga.coverData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 30).scaleEffect(1.3)
            } else {
                Theme.accent.opacity(0.3)
            }
            Rectangle().fill(.regularMaterial)
        }
        .clipped()
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
        HStack(spacing: 12) {
            status.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.name).lineLimit(2)
                    .foregroundStyle(chapter.isRead ? .secondary : .primary)
                if chapter.inProgress {
                    Text("Page \(chapter.lastPage + 1) of \(chapter.pageCount)")
                        .font(.caption).foregroundStyle(Theme.accent)
                } else {
                    Text("\(chapter.pageCount) pages").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var status: some View {
        if chapter.isRead {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).font(.title3)
        } else if chapter.inProgress {
            ProgressRing(progress: Double(chapter.lastPage) / Double(max(chapter.pageCount, 1)))
        } else {
            Circle().fill(Theme.accent).frame(width: 9, height: 9)
        }
    }
}
