import SwiftUI

struct ICloudSyncView: View {
    @Environment(\.modelContext) private var context
    @State private var available: Bool?
    private var sync: ICloudSync { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
                    .disabled(available != true)
                Button(sync.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await sync.syncNow(context: context) }
                }
                .disabled(!sync.enabled || sync.isSyncing || available != true)
                if let last = sync.lastSync {
                    Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = sync.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Syncs categories, reading progress and tracker links between your devices through iCloud Drive. Series are matched by title and chapter name, and progress only moves forward. Comic files, passwords and sign-in tokens never sync, and deleting a series on one device does not delete it on another.")
            }
            if available == false {
                Section {
                    Text("iCloud isn't available in this build. It needs the iCloud Documents capability and a signed-in iCloud account. See docs/ICLOUD_SYNC.md.")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("iCloud sync")
        .task { available = await sync.checkAvailability() }
    }
}
