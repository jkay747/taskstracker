import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Persistence
    @FetchRequest(fetchRequest: TaskCategory.all) private var allCategories: FetchedResults<TaskCategory>
    @FetchRequest(fetchRequest: Board.all) private var boards: FetchedResults<Board>
    @AppStorage("myName") private var myName = ""

    @State private var newName = ""
    @State private var removing: TaskCategory?
    @State private var shareRequest: TaskCategory?

    /// Only your own categories can be renamed, reordered or removed here.
    private var categories: [TaskCategory] { allCategories.filter { store.isMine($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: Binding(
                        get: { boards.first?.listName ?? "" },
                        set: { store.board().listName = String($0.prefix(60)) }
                    ))
                } header: {
                    Text("List name")
                }

                Section {
                    TextField("Your name", text: $myName)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("How you appear as a task's owner, and what the “Mine” filter looks for. Use the same name on each of your devices.")
                }

                Section {
                    ForEach(Array(categories.enumerated()), id: \.element.objectID) { index, category in
                        CategoryRow(
                            category: category,
                            shared: store.isShared(category),
                            canMoveUp: index > 0,
                            canMoveDown: index < categories.count - 1,
                            canRemove: categories.count > 1,
                            moveUp: { move(index, by: -1) },
                            moveDown: { move(index, by: 1) },
                            share: { shareRequest = category },
                            remove: { requestRemove(category) }
                        )
                    }
                    HStack {
                        TextField("New category name", text: $newName)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(!canAdd)
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Tap a color to change it. Tap the person icon to share a category or manage who's on it. A list can have up to \(Persistence.maxCategories) categories.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("List Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                removing.map { "“\($0.name)” has \($0.taskList.count) task(s). Where should they go?" } ?? "",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                ForEach(categories.filter { $0 != removing }) { other in
                    Button("Move to \(other.name)") {
                        if let category = removing { remove(category, movingTasksTo: other) }
                    }
                }
                Button("Cancel", role: .cancel) { removing = nil }
            }
        }
        .categorySharing($shareRequest)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var canAdd: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty && categories.count < Persistence.maxCategories
    }

    private func add() {
        let label = newName.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, categories.count < Persistence.maxCategories else { return }
        let used = Set(categories.map { $0.color })
        let color = (0..<Palette.count).first { !used.contains($0) } ?? categories.count
        let key = Persistence.slug(for: label, taken: Set(categories.compactMap { $0.key }))
        let order = (categories.map { Int($0.sortOrder) }.max() ?? -1) + 1
        store.addCategory(label: label, key: key, color: color, order: order)
        newName = ""
    }

    private func move(_ index: Int, by delta: Int) {
        var list = categories
        let target = index + delta
        guard list.indices.contains(index), list.indices.contains(target) else { return }
        list.swapAt(index, target)
        for (order, category) in list.enumerated() { category.sortOrder = Int64(order) }
    }

    private func requestRemove(_ category: TaskCategory) {
        if category.taskList.isEmpty {
            store.context.delete(category)
        } else {
            removing = category
        }
    }

    private func remove(_ category: TaskCategory, movingTasksTo other: TaskCategory) {
        for task in category.taskList { store.move(task, to: other) }
        removing = nil
        store.context.delete(category)
    }
}

private struct CategoryRow: View {
    @ObservedObject var category: TaskCategory
    let shared: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canRemove: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let share: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if !category.isGone { category.colorIndex = Int64((category.color + 1) % Palette.count) }
            } label: {
                CategorySwatch(colorIndex: category.color, size: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Change color for \(category.name)")

            TextField("Category name", text: textBinding(category, \.label, limit: 40))

            Button(action: share) {
                Image(systemName: shared ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(shared ? "Manage sharing for \(category.name)" : "Share \(category.name)")
            Button(action: moveUp) { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .accessibilityLabel("Move up")
            Button(action: moveDown) { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .accessibilityLabel("Move down")
            Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .accessibilityLabel("Remove \(category.name)")
        }
    }
}
