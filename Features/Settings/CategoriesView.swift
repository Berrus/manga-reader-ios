import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @State private var newName = ""
    @State private var notice: String?

    private var lock: PrivacyLock { .shared }
    /// Private categories stay out of sight (even their names) until the lock is opened.
    private var visible: [Category] { categories.filter { !$0.isPrivate || lock.isUnlocked } }
    private var hasLockedCategories: Bool { categories.contains { $0.isPrivate } && !lock.isUnlocked }

    var body: some View {
        List {
            Section {
                ForEach(visible) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        if category.isPrivate { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    .swipeActions(edge: .leading) {
                        Button(category.isPrivate ? "Make public" : "Make private",
                               systemImage: category.isPrivate ? "lock.open" : "lock") {
                            Task { await setPrivate(category, !category.isPrivate) }
                        }.tint(.indigo)
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
                if hasLockedCategories {
                    Button("Unlock private categories", systemImage: "lock") { Task { await lock.unlock() } }
                }
            } footer: {
                Text("Group your library with categories. Long-press a series in the library to move it. Swipe a category right to make it private: its series are then hidden from the library, history, updates and suggestions until you unlock with Face ID, Touch ID or your device passcode. This is a privacy setting for you, not a security boundary: private series are still stored on this device and included in backups, and notifications never show their titles.")
            }
            Section {
                HStack {
                    TextField("New category", text: $newName).onSubmit(add)
                    Button("Add", action: add).disabled(trimmed.isEmpty)
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar { EditButton() }
        .alert("Private categories", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmed.isEmpty else { return }
        context.insert(Category(name: trimmed, order: (categories.map(\.order).max() ?? -1) + 1))
        newName = ""
    }

    /// Turning privacy on or off needs the device owner, so someone holding an unlocked phone can't hide or reveal categories.
    private func setPrivate(_ category: Category, _ value: Bool) async {
        guard lock.canProtect else {
            notice = "Set a device passcode in Settings to use private categories."
            return
        }
        guard await lock.unlock(reason: value ? "Make this category private" : "Make this category public") else { return }
        category.isPrivate = value
    }

    private func delete(_ offsets: IndexSet) {
        let removed = offsets.map { visible[$0] }
        let ids = Set(removed.map(\.id))
        if let all = try? context.fetch(FetchDescriptor<Manga>()) {
            for manga in all where manga.categoryID.map(ids.contains) == true { manga.categoryID = nil }
        }
        removed.forEach(context.delete)
    }

    // shortcut: renumbers only the visible rows, so while private categories are hidden their relative order can shift; upgrade if ordering matters.
    private func move(from source: IndexSet, to destination: Int) {
        var items = visible
        items.move(fromOffsets: source, toOffset: destination)
        for (index, category) in items.enumerated() { category.order = index }
    }
}
