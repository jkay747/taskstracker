import SwiftUI

/// Edits a copy of a task; Save sends it, Cancel drops it.
struct TaskEditor: View {
    let original: TaskItem
    let isNew: Bool
    let onClose: () -> Void

    @EnvironmentObject private var store: Store
    @State private var draft: TaskItem
    @State private var typedOwner = ""
    @State private var typedPerson = ""
    @State private var confirmDelete = false
    @State private var snoozeDays: Int

    init(original: TaskItem, isNew: Bool, onClose: @escaping () -> Void) {
        self.original = original
        self.isNew = isNew
        self.onClose = onClose
        _draft = State(initialValue: original)
        _snoozeDays = State(initialValue: original.isSnoozed ? original.snoozeDaysLeft : TaskItem.defaultSnoozeDays)
    }

    private var editable: Bool { isNew || store.canEdit(original) }
    private var canSave: Bool { editable && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !editable {
                    Section {
                        Text("Only this task's owner, the people on it, or the list's editors can change it.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Task", text: $draft.title, axis: .vertical)
                        .lineLimit(1...4)
                }
                detailsSection
                snoozeSection
                PeopleSection(draft: $draft, typedOwner: $typedOwner, typedPerson: $typedPerson)
                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 110)
                }
                Section {
                    if !isNew && store.canDelete(original) {
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
            .navigationTitle(isNew ? "New Task" : (editable ? "Edit Task" : "Task"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editable ? "Cancel" : "Close", action: onClose)
                }
                if editable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(original)
                    onClose()
                }
                Button("Keep", role: .cancel) { }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private var detailsSection: some View {
        Section {
            Picker("Category", selection: Binding(
                get: { draft.categoryKey ?? "" },
                set: { draft.categoryKey = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(store.categories) { category in
                    Text(category.name).tag(category.key)
                }
                if !store.categories.contains(where: { $0.key == draft.categoryKey }) {
                    Text("Uncategorized").tag(draft.categoryKey ?? "")
                }
            }
            Toggle("Due date", isOn: Binding(
                get: { draft.due != nil },
                set: { draft.due = $0 ? DayString.string(Date()) : nil }
            ))
            if draft.due != nil {
                DatePicker("Due", selection: Binding(
                    get: { draft.dueDate ?? Date() },
                    set: { draft.due = DayString.string($0) }
                ), displayedComponents: .date)
            }
            Toggle("Top priority", isOn: $draft.priority)
            Toggle("Completed", isOn: Binding(
                get: { draft.done },
                set: { draft.setDone($0, by: store.myID) }
            ))
        }
    }

    private var snoozeSection: some View {
        Section {
            Toggle("Snooze", isOn: Binding(
                get: { draft.isSnoozed },
                set: { on in
                    if on { draft.snooze(days: snoozeDays, by: store.myID); SnoozeAlerts.requestPermission() } else { draft.wake() }
                }
            ))
            .disabled(draft.done)
            if draft.isSnoozed {
                Stepper(value: Binding(
                    get: { snoozeDays },
                    set: { snoozeDays = $0; draft.snooze(days: $0, by: store.myID) }
                ), in: 1...365) {
                    Text("For \(SnoozeText.days(snoozeDays))")
                }
            }
        } footer: {
            if draft.isSnoozed, let end = draft.snoozeEnd {
                Text("Greyed out until \(SnoozeText.until(end)), then you'll get a reminder.")
            } else if !draft.done {
                Text("Greys the task out for a few days and reminds you when it's over.")
            }
        }
    }

    private func save() {
        if let person = Person.typed(typedOwner), draft.owner == nil { draft.owner = person }
        if let person = Person.typed(typedPerson), !draft.involves(person) { draft.shared.append(person) }
        if draft.done == original.done {
            draft.doneAt = original.doneAt
            draft.doneBy = original.doneBy
        }
        if draft.done { draft.wake() }
        if isNew { store.add(draft) } else { store.save(draft) }
        onClose()
    }

    private var footnote: String {
        if isNew { return "" }
        var text = "Added " + original.created.formatted(date: .abbreviated, time: .omitted)
        if let by = original.createdBy { text += " by " + store.name(of: .user(by)) }
        if original.done, let at = original.completed {
            text += ", completed " + at.formatted(date: .abbreviated, time: .omitted)
            if let by = original.doneBy { text += " by " + store.name(of: .user(by)) }
        }
        return text
    }
}

/// Owner and the other people on a task: list members to pick from, or a
/// typed name or email for someone who hasn't joined yet.
private struct PeopleSection: View {
    @Binding var draft: TaskItem
    @Binding var typedOwner: String
    @Binding var typedPerson: String
    @EnvironmentObject private var store: Store

    private var choices: [Person] {
        var seen = Set<String>()
        return (store.memberPeople + store.unlinkedPeople).filter { seen.insert($0.key).inserted }
    }

    private func label(_ person: Person) -> String {
        let name = person == store.me ? "Me" : store.name(of: person)
        return person.isLinked ? name : name + " (not joined)"
    }

    var body: some View {
        Section {
            Picker("Owner", selection: Binding(
                get: { draft.owner?.key ?? "" },
                set: { key in
                    draft.owner = choices.first { $0.key == key } ?? draft.owner.flatMap { $0.key == key ? $0 : nil }
                    if let owner = draft.owner { draft.shared.removeAll { $0.key == owner.key } }
                }
            )) {
                Text("Nobody").tag("")
                ForEach(choices, id: \.key) { person in
                    Text(label(person)).tag(person.key)
                }
                if let owner = draft.owner, !choices.contains(owner) {
                    Text(label(owner)).tag(owner.key)
                }
            }
            if draft.owner == nil {
                TextField("Or type a name or email", text: $typedOwner)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let person = Person.typed(typedOwner) { draft.owner = person; typedOwner = "" }
                    }
            }

            ForEach(draft.shared, id: \.key) { person in
                HStack {
                    Label(label(person), systemImage: person.isLinked ? "person" : "person.badge.clock")
                    Spacer()
                    Button {
                        draft.shared.removeAll { $0.key == person.key }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(label(person))")
                }
            }
            let addable = choices.filter { !draft.involves($0) }
            if !addable.isEmpty {
                Menu("Add someone on this list") {
                    ForEach(addable, id: \.key) { person in
                        Button(label(person)) { draft.shared.append(person) }
                    }
                }
            }
            TextField("Add a name or email", text: $typedPerson)
                .autocorrectionDisabled()
                .onSubmit {
                    if let person = Person.typed(typedPerson), !draft.involves(person) { draft.shared.append(person) }
                    typedPerson = ""
                }
        } header: {
            Text("People")
        } footer: {
            Text("The owner and the people on a task can check it off. To give someone access to the list, invite their email under List Settings → People; anything assigned to that email links to them when they sign in.")
        }
    }
}
