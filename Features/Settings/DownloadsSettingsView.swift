import SwiftUI
import SwiftData

struct DownloadsSettingsView: View {
    @AppStorage(DownloadSettings.scopeKey) private var scopeRaw = AutoDownloadScope.off.rawValue
    @AppStorage(DownloadSettings.aheadKey) private var ahead = 3
    @AppStorage(DownloadSettings.wifiOnlyKey) private var wifiOnly = true
    @AppStorage(DownloadSettings.deleteReadKey) private var deleteRead = false
    @Environment(\.modelContext) private var context
    @State private var storageText = "…"
    @State private var resultText: String?
    @State private var confirmDelete = false

    private var manager: DownloadManager { .shared }
    private var updater: LibraryUpdater { .shared }
    private var scope: AutoDownloadScope { AutoDownloadScope(rawValue: scopeRaw) ?? .off }

    var body: some View {
        Form {
            Section {
                Picker("Download", selection: $scopeRaw) {
                    ForEach(AutoDownloadScope.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if scope != .off {
                    Picker("Keep ahead", selection: $ahead) {
                        ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) chapters").tag($0) }
                    }
                }
                Toggle("Wi-Fi only", isOn: $wifiOnly)
                Toggle("Delete after reading", isOn: $deleteRead)
            } header: {
                Text("Automatic downloads")
            } footer: {
                Text(scope.detail + " Only series added from Browse are checked. iOS decides when background checks run, so updates are also checked when you open the app.")
            }

            Section {
                Button(updater.isRunning ? "Checking…" : "Check for updates now", systemImage: "arrow.clockwise") {
                    Task {
                        if let summary = await updater.runIfNeeded(context: context, force: true) {
                            resultText = "Checked \(summary.checked) series, \(summary.newChapters) new chapters, \(summary.queued) queued."
                                + (summary.failed > 0 ? " \(summary.failed) failed." : "")
                        }
                    }
                }
                .disabled(updater.isRunning)
                if let resultText { Text(resultText).font(.footnote).foregroundStyle(.secondary) }
                if let last = DownloadSettings.lastCheck {
                    Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Queue") {
                if manager.jobs.isEmpty {
                    Text("Nothing is downloading.").foregroundStyle(.secondary)
                }
                ForEach(manager.jobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title).lineLimit(1)
                        if let failure = job.failure {
                            Text(failure).font(.caption).foregroundStyle(.orange)
                        } else {
                            ProgressView(value: job.progress).tint(Theme.accent)
                        }
                    }
                    .swipeActions {
                        Button("Cancel", systemImage: "xmark", role: .destructive) { manager.cancel(chapterID: job.chapterID) }
                    }
                }
                if manager.jobs.contains(where: { $0.failure != nil }) {
                    Button("Retry failed") { manager.retryFailed() }
                }
                if !manager.jobs.isEmpty {
                    Button("Clear queue", role: .destructive) { manager.cancelAll() }
                }
                if !NetworkMonitor.shared.canDownload && !manager.jobs.isEmpty {
                    Text(NetworkMonitor.shared.isOnline ? "Paused: waiting for Wi-Fi." : "Paused: you're offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                LabeledContent("Downloaded", value: storageText)
                Button("Delete all downloads", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Downloads")
        .task { await refreshStorage() }
        .onChange(of: wifiOnly) { _, _ in
            if NetworkMonitor.shared.canDownload { manager.resume(context: context) }
            else { manager.pause() }
        }
        .onChange(of: manager.jobs.count) { _, _ in Task { await refreshStorage() } }
        .confirmationDialog("Delete all downloaded chapters?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all downloads", role: .destructive) { deleteAll() }
        } message: {
            Text("Series stay in your library and can be downloaded again. Imported CBZ files are not affected.")
        }
    }

    private func refreshStorage() async {
        let bytes = await Task.detached(priority: .utility) { DownloadStorage.totalBytes() }.value
        storageText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func deleteAll() {
        let all = (try? context.fetch(FetchDescriptor<Manga>())) ?? []
        let chapters = all.flatMap(\.chapters)
        Task {
            await manager.cancelAndWait(Set(chapters.map(\.id)))
            for chapter in chapters where chapter.isDownloaded { chapter.removeFiles() }
            try? context.save()
            await refreshStorage()
        }
    }
}
