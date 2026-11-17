import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let showCategory: Bool
    let onOpen: () -> Void

    @EnvironmentObject private var store: Store

    private var editable: Bool { store.canEdit(task) }
    private var deletable: Bool { store.canDelete(task) }
    private var category: TaskCategory? { store.categories.first { $0.key == task.categoryKey } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleDone(task)
            } label: {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(!editable)
            .accessibilityLabel(task.done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "(untitled)" : task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                if hasMeta {
                    meta
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Button {
                store.toggleStar(task)
            } label: {
                Image(systemName: task.priority ? "star.fill" : "star")
                    .foregroundStyle(task.priority ? Color.orange : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .disabled(!editable)
            .accessibilityLabel(task.priority ? "Remove from top priorities" : "Make a top priority")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if deletable {
                Button(role: .destructive) {
                    store.delete(task)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if editable {
                Button {
                    store.toggleDone(task)
                } label: {
                    Label(task.done ? "Not Done" : "Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            Button(editable ? "Edit…" : "View…", action: onOpen)
            if editable {
                Button(task.done ? "Mark Not Done" : "Mark Done") { store.toggleDone(task) }
                Button(task.priority ? "Remove from Top Priorities" : "Make Top Priority") { store.toggleStar(task) }
            }
            if deletable {
                Divider()
                Button("Delete", role: .destructive) { store.delete(task) }
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 10) {
            if showCategory, let category {
                HStack(spacing: 4) {
                    CategorySwatch(colorIndex: category.color, size: 8)
                    Text(category.name)
                }
            }
            if let owner = task.owner {
                Label(owner == store.me ? "You" : store.name(of: owner), systemImage: owner.isLinked ? "person" : "person.badge.clock")
                    .labelStyle(.titleAndIcon)
            }
            if let due = task.dueDate {
                Text(DueText.label(for: due))
                    .fontWeight(task.isLate ? .semibold : .regular)
                    .foregroundStyle(task.isLate ? Color.red : Color.secondary)
            }
            if !task.shared.isEmpty {
                Text("+ " + (task.shared.count == 1 ? store.name(of: task.shared[0]) : "\(task.shared.count) others"))
            }
            if task.done, let by = task.doneBy, task.owner != .user(by) {
                Text("checked off by " + store.name(of: .user(by)))
            }
            if !task.notes.isEmpty {
                Image(systemName: "note.text")
                    .accessibilityLabel("Has notes")
            }
        }
    }

    private var hasMeta: Bool {
        (showCategory && category != nil) || task.owner != nil || task.dueDate != nil
            || !task.shared.isEmpty || !task.notes.isEmpty || (task.done && task.doneBy != nil)
    }
}
