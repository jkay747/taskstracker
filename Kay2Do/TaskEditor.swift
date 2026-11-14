import SwiftUI
import CoreData

/// Edits a task in place; changes save as you type.
struct TaskEditor: View {
    @ObservedObject var task: TaskItem
    /// The list deletes the task after this sheet has closed.
    let onDelete: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var store: Persistence
    @FetchRequest(fetchRequest: TaskCategory.all) private var categories: FetchedResults<TaskCategory>
    @FetchRequest(fetchRequest: TaskItem.all) private var allTasks: FetchedResults<TaskItem>
    @AppStorage("myName") private var myName = ""
    @State private var confirmDelete = false
    @State private var shareRequest: TaskCategory?

    private var editable: Bool { store.canEdit(task) }

    var body: some View {
        NavigationStack {
            Form {
                if !editable {
                    Section {
                        Text("You've been invited to view this category, so you can't change its tasks.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Task", text: textBinding(task, \.title, limit: 300), axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Picker("Category", selection: Binding(
                        get: { task.isGone ? nil : task.category },
                        set: { changeCategory(to: $0) }
                    )) {
                        ForEach(categories) { category in
                            Text(category.name + (store.isShared(category) ? " (shared)" : ""))
                                .tag(category as TaskCategory?)
                        }
                        if task.isGone || task.category == nil {
                            Text("Uncategorized").tag(nil as TaskCategory?)
                        }
                    }
                    Toggle("Due date", isOn: Binding(
                        get: { task.dueDate != nil },
                        set: { task.due = $0 ? Calendar.current.startOfDay(for: Date()) : nil }
                    ))
                    if task.dueDate != nil {
                        DatePicker("Due", selection: Binding(
                            get: { task.dueDate ?? Date() },
                            set: { task.due = Calendar.current.startOfDay(for: $0) }
                        ), displayedComponents: .date)
                    }
                    Toggle("Top priority", isOn: Binding(
                        get: { task.isStarred },
                        set: { task.priority = $0 }
                    ))
                    Toggle("Completed", isOn: Binding(
                        get: { task.isDone },
                        set: { task.setDone($0, by: myName) }
                    ))
                }

                Section {
                    TextField("Owner", text: textBinding(task, \.owner, limit: 120))
                    if !ownerSuggestions.isEmpty {
                        chips(ownerSuggestions) { name in task.owner = name }
                    }
                    TextField("Also involved (separate names with commas)", text: textBinding(task, \.sharedWith, limit: 600))
                    if !involvedSuggestions.isEmpty {
                        chips(involvedSuggestions) { name in
                            task.sharedWith = (task.sharedNames + [name]).joined(separator: ", ")
                        }
                    }
                    if let category = task.isGone ? nil : task.category, store.isMine(category) {
                        Button {
                            shareRequest = category
                        } label: {
                            Label(store.isShared(category) ? "Invite someone else…" : "Invite someone to this task…",
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text(peopleFootnote)
                }

                Section("Notes") {
                    TextEditor(text: textBinding(task, \.notes))
                        .frame(minHeight: 110)
                }

                Section {
                    if editable {
                        Button("Delete Task", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                } footer: {
                    Text(footnote)
                }
            }
            .formStyle(.grouped)
            .disabled(!editable)
            .navigationTitle(task.titleText.isEmpty ? "New Task" : (editable ? "Edit Task" : "Task"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Keep", role: .cancel) { }
            }
        }
        .categorySharing($shareRequest)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private func chips(_ names: [String], pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Button(People.same(name, myName) ? "Me" : name) { pick(name) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    /// Moving across a sharing boundary re-creates the task at the destination,
    /// so the editor closes rather than keep showing the old copy.
    private func changeCategory(to destination: TaskCategory?) {
        guard !task.isGone, let destination = destination else { return }
        if store.move(task, to: destination) {
            onClose()
        }
    }

    /// You, the people on this category's share, then names used elsewhere.
    private var knownPeople: [String] {
        let category = task.isGone ? nil : task.category
        var names = [myName] + store.participants(of: category)
        for other in allTasks { names.append(contentsOf: [other.ownerName] + other.sharedNames) }
        return People.unique(names)
    }

    private var ownerSuggestions: [String] {
        Array(knownPeople.filter { !People.same($0, task.ownerName) }.prefix(8))
    }

    private var involvedSuggestions: [String] {
        let taken = [task.ownerName] + task.sharedNames
        return Array(knownPeople.filter { name in !taken.contains { People.same($0, name) } }.prefix(8))
    }

    private var peopleFootnote: String {
        guard !task.isGone, let category = task.category else { return "" }
        if !store.isMine(category) {
            return "This category was shared with you. Everyone on it sees its tasks."
        }
        if store.isShared(category) {
            let people = store.participants(of: category)
            let who = people.isEmpty ? "the people you invited" : people.joined(separator: ", ")
            return "“\(category.name)” is shared with \(who). They see every task in it and can check off their own."
        }
        return "Inviting someone shares the whole “\(category.name)” category with them by iCloud. Your other categories stay private."
    }

    private var footnote: String {
        if task.isGone { return "" }
        var text = "Added " + task.created.formatted(date: .abbreviated, time: .omitted)
        if let by = task.createdBy, !by.isEmpty { text += " by " + by }
        if task.done, let doneAt = task.doneAt {
            text += ", completed " + doneAt.formatted(date: .abbreviated, time: .omitted)
            if let by = task.doneBy, !by.isEmpty { text += " by " + by }
        }
        return text
    }
}
