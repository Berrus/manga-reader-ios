import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Text(category.name)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            } footer: {
                Text("Group your library with categories. Long-press a series in the library to move it.")
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
    }

    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmed.isEmpty else { return }
        context.insert(Category(name: trimmed, order: (categories.map(\.order).max() ?? -1) + 1))
        newName = ""
    }

    private func delete(_ offsets: IndexSet) {
        let removed = offsets.map { categories[$0] }
        let ids = Set(removed.map(\.id))
        if let all = try? context.fetch(FetchDescriptor<Manga>()) {
            for manga in all where manga.categoryID.map(ids.contains) == true { manga.categoryID = nil }
        }
        removed.forEach(context.delete)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = categories
        items.move(fromOffsets: source, toOffset: destination)
        for (index, category) in items.enumerated() { category.order = index }
    }
}
