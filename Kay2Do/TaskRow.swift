import SwiftUI
import CoreData

struct TaskRow: View {
    @ObservedObject var task: TaskItem
    let showCategory: Bool
    let editable: Bool
    let myName: String
    let onOpen: () -> Void

    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleDone()
            } label: {
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(!editable)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.titleText.isEmpty ? "(untitled)" : task.titleText)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                if hasMeta {
                    HStack(spacing: 10) {
                        if showCategory, let category = task.category {
                            HStack(spacing: 4) {
                                CategorySwatch(colorIndex: category.color, size: 8)
                                Text(category.name)
                            }
                        }
                        if !task.ownerName.isEmpty {
                            Label(People.same(task.ownerName, myName) ? "You" : task.ownerName, systemImage: "person")
                                .labelStyle(.titleAndIcon)
                        }
                        if let due = task.dueDate {
                            Text(DueText.label(for: due))
                                .fontWeight(task.isLate ? .semibold : .regular)
                                .foregroundStyle(task.isLate ? Color.red : Color.secondary)
                        }
                        if !task.sharedNames.isEmpty {
                            Text("+ " + (task.sharedNames.count == 1 ? task.sharedNames[0] : "\(task.sharedNames.count) involved"))
                        }
                        if !task.notesText.isEmpty {
                            Image(systemName: "note.text")
                                .accessibilityLabel("Has notes")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Button {
                task.priority.toggle()
            } label: {
                Image(systemName: task.isStarred ? "star.fill" : "star")
                    .foregroundStyle(task.isStarred ? Color.orange : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .disabled(!editable)
            .accessibilityLabel(task.isStarred ? "Remove from top priorities" : "Make a top priority")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if editable {
                Button(role: .destructive) {
                    context.delete(task)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if editable {
                Button {
                    toggleDone()
                } label: {
                    Label(task.isDone ? "Not Done" : "Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            Button(editable ? "Edit…" : "View…", action: onOpen)
            if editable {
                Button(task.isDone ? "Mark Not Done" : "Mark Done") { toggleDone() }
                Button(task.isStarred ? "Remove from Top Priorities" : "Make Top Priority") { task.priority.toggle() }
                Divider()
                Button("Delete", role: .destructive) { context.delete(task) }
            }
        }
    }

    private func toggleDone() {
        guard !task.isGone else { return }
        task.setDone(!task.done, by: myName)
    }

    private var hasMeta: Bool {
        (showCategory && task.category != nil) || !task.ownerName.isEmpty || task.dueDate != nil
            || !task.sharedNames.isEmpty || !task.notesText.isEmpty
    }
}
