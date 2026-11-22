import SwiftUI

enum OwnerFilter: Hashable {
    case everyone
    case mine
    case unassigned
    /// A person, by Person.key.
    case person(String)
}

/// One boxed heading on the sheet: a category, or the tasks that have none.
private struct Bucket: Identifiable {
    let id: String
    let category: TaskCategory?
    let label: String
    let colorIndex: Int?
}

/// The task being edited in the sheet.
struct EditTarget: Identifiable {
    let id = UUID()
    let task: TaskItem
    let isNew: Bool
}

struct TaskListView: View {
    let filter: SidebarItem

    @EnvironmentObject private var store: Store
    @State private var confirmingClear = false
    @State private var search = ""
    @State private var ownerFilter = OwnerFilter.everyone
    @State private var editing: EditTarget?

    private var selectedCategory: TaskCategory? {
        if case .category(let key) = filter { return store.categories.first { $0.key == key } }
        return nil
    }

    var body: some View {
        content
            .navigationTitle(title)
            .searchable(text: $search, prompt: "Search tasks")
            .refreshable { try? await store.reload() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTask()
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.categories.isEmpty)
                }
                ToolbarItem {
                    Menu {
                        Picker("Owner", selection: $ownerFilter) {
                            Text("Everyone").tag(OwnerFilter.everyone)
                            Text("Mine (owned or on)").tag(OwnerFilter.mine)
                            Text("Unassigned").tag(OwnerFilter.unassigned)
                            ForEach(filterPeople, id: \.key) { person in
                                Text(store.name(of: person)).tag(OwnerFilter.person(person.key))
                            }
                        }
                        if store.isManager {
                            Divider()
                            Button(role: .destructive) {
                                confirmingClear = true
                            } label: {
                                Label("Remove Completed (\(store.completedCount))", systemImage: "checkmark.circle.badge.xmark")
                            }
                            .disabled(store.completedCount == 0)
                        }
                    } label: {
                        Label("Filter", systemImage: ownerFilter == .everyone
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .confirmationDialog("Remove \(store.completedCount) completed task\(store.completedCount == 1 ? "" : "s") for everyone on the list?",
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Remove Completed", role: .destructive) { store.removeCompleted() }
                Button("Keep", role: .cancel) {}
            }
            .sheet(item: $editing) { target in
                TaskEditor(original: target.task, isNew: target.isNew) {
                    editing = nil
                }
                .environmentObject(store)
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.categories.isEmpty && store.tasks.isEmpty {
            ContentUnavailableView("No categories yet", systemImage: "checklist",
                                   description: Text(store.isManager ? "Add categories under List Settings." : "Whoever manages this list hasn't added categories yet."))
        } else if buckets.isEmpty && filter != .priorities {
            ContentUnavailableView("This category is no longer here", systemImage: "folder.badge.minus",
                                   description: Text("Pick another one from the sidebar."))
        } else {
            List {
                if filter == .all {
                    WeekSection()
                    prioritySection(limit: 3)
                }
                if filter == .priorities {
                    prioritySection(limit: nil)
                } else {
                    ForEach(buckets) { bucket in
                        bucketSection(bucket)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            .scrollContentBackground(store.background == .none ? .automatic : .hidden)
            .background { ListBackdrop() }
            #endif
        }
    }

    // MARK: Sections

    private func bucketSection(_ bucket: Bucket) -> some View {
        let all = allTasks(in: bucket)
        return Section {
            // Checked-off tasks stay where they are, crossed out, until they're removed.
            ForEach(tasks(in: bucket)) { task in
                row(task, showCategory: false)
            }
            if let category = bucket.category {
                AddTaskField(category: category, owner: defaultOwner)
            }
        } header: {
            BucketHeader(label: bucket.label, colorIndex: bucket.colorIndex,
                         open: all.filter { !$0.done }.count,
                         done: all.filter { $0.done }.count)
        }
    }

    @ViewBuilder
    private func prioritySection(limit: Int?) -> some View {
        Section {
            if starred.isEmpty {
                Text("Star a task to make it a top priority.")
                    .foregroundStyle(.secondary)
            }
            ForEach(limit.map { Array(starred.prefix($0)) } ?? starred) { task in
                row(task, showCategory: true)
            }
            if let limit, starred.count > limit {
                Text("+\(starred.count - limit) more starred in the lists below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Top priorities")
        }
    }

    private func row(_ task: TaskItem, showCategory: Bool) -> some View {
        TaskRow(task: task, showCategory: showCategory) {
            editing = EditTarget(task: task, isNew: false)
        }
    }

    // MARK: Data

    private var title: String {
        switch filter {
        case .all: return "All Tasks"
        case .priorities: return "Top Priorities"
        case .category: return selectedCategory?.name ?? "Tasks"
        }
    }

    private var buckets: [Bucket] {
        if case .category = filter {
            return selectedCategory.map { [bucket(for: $0)] } ?? []
        }
        var list = store.categories.map(bucket(for:))
        let keys = Set(store.categories.map(\.key))
        if store.tasks.contains(where: { !keys.contains($0.categoryKey ?? "") }) {
            list.append(Bucket(id: "__none", category: nil, label: "Uncategorized", colorIndex: nil))
        }
        return list
    }

    private func bucket(for category: TaskCategory) -> Bucket {
        Bucket(id: category.id, category: category, label: category.name, colorIndex: category.color)
    }

    private func allTasks(in bucket: Bucket) -> [TaskItem] {
        if let category = bucket.category {
            return store.tasks.filter { $0.categoryKey == category.key }
        }
        let keys = Set(store.categories.map(\.key))
        return store.tasks.filter { !keys.contains($0.categoryKey ?? "") }
    }

    private func tasks(in bucket: Bucket) -> [TaskItem] {
        allTasks(in: bucket).filter(matches).sorted(by: TaskItem.order)
    }

    private var starred: [TaskItem] {
        store.tasks.filter { $0.priority && matches($0) }.sorted(by: TaskItem.order)
    }

    /// Everyone on the list or named on a task, other than you, for the filter menu.
    private var filterPeople: [Person] {
        var seen = Set<String>([store.me.key])
        var out: [Person] = []
        for person in store.memberPeople + store.tasks.flatMap(\.people) where seen.insert(person.key).inserted {
            out.append(person)
        }
        return out.sorted { store.name(of: $0).localizedCaseInsensitiveCompare(store.name(of: $1)) == .orderedAscending }
    }

    private var defaultOwner: Person? {
        switch ownerFilter {
        case .person(let key): return filterPeople.first { $0.key == key }
        case .mine: return store.me
        case .everyone, .unassigned: return store.isManager ? nil : store.me
        }
    }

    private func matches(_ task: TaskItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty, !task.title.lowercased().contains(query), !task.notes.lowercased().contains(query) {
            return false
        }
        switch ownerFilter {
        case .everyone: return true
        case .mine: return task.involves(store.me)
        case .unassigned: return task.owner == nil
        case .person(let key): return task.people.contains { $0.key == key }
        }
    }

    private func newTask() {
        var task = store.newTask(in: selectedCategory?.key)
        task.owner = defaultOwner
        if filter == .priorities { task.priority = true }
        editing = EditTarget(task: task, isNew: true)
    }
}

/// "This week will be… because…", saved shortly after you stop typing.
private struct WeekSection: View {
    @EnvironmentObject private var store: Store
    @State private var theme = ""
    @State private var because = ""
    @State private var loadedFor: String?
    @State private var editingQuote = false

    var body: some View {
        Section {
            if let quote = store.weeklyQuote {
                QuoteRow(quote: quote)
                    .padding(.vertical, 4)
                if store.isManager {
                    Button("Change Quote…") { editingQuote = true }
                        .font(.callout)
                }
            }
            if store.isManager {
                DatePicker("Week of", selection: Binding(
                    get: { DayString.date(store.list?.weekOf) ?? Date() },
                    set: { store.setWeek(weekOf: .some($0)) }
                ), displayedComponents: .date)
                TextField("This week will be…", text: $theme)
                    .onChange(of: theme) { _, value in store.setWeek(theme: value) }
                TextField("because…", text: $because)
                    .onChange(of: because) { _, value in store.setWeek(because: value) }
            } else {
                if let week = DayString.date(store.list?.weekOf) {
                    LabeledContent("Week of", value: week.formatted(date: .abbreviated, time: .omitted))
                }
                Text(store.list?.theme.isEmpty == false ? "This week will be \(store.list?.theme ?? "")" : "No theme set for this week")
                    .foregroundStyle(store.list?.theme.isEmpty == false ? .primary : .secondary)
                if let why = store.list?.because, !why.isEmpty {
                    Text("because \(why)")
                }
            }
        } header: {
            Text("This week")
        }
        .font(.system(.body, design: .serif))
        .sheet(isPresented: $editingQuote) {
            QuoteEditor().environmentObject(store)
        }
        .onAppear(perform: sync)
        .onChange(of: store.list) { _, _ in sync() }
    }

    /// Takes the saved text unless you're partway through typing over it.
    private func sync() {
        guard let list = store.list else { return }
        if loadedFor != list.id || (theme == list.theme || theme.isEmpty) { theme = list.theme }
        if loadedFor != list.id || (because == list.because || because.isEmpty) { because = list.because }
        loadedFor = list.id
    }
}

private struct BucketHeader: View {
    let label: String
    let colorIndex: Int?
    let open: Int
    let done: Int

    var body: some View {
        HStack(spacing: 8) {
            CategorySwatch(colorIndex: colorIndex)
            Text(label)
                .fontWeight(.bold)
            Spacer()
            Text(done > 0 ? "\(open) open · \(done) done" : "\(open) open")
                .monospacedDigit()
        }
    }
}

private struct AddTaskField: View {
    let category: TaskCategory
    let owner: Person?

    @EnvironmentObject private var store: Store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed")
                .foregroundStyle(.tertiary)
            TextField("Add to \(category.name)…", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)
        }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var task = store.newTask(title: title, in: category.key)
        task.owner = owner
        store.add(task)
        text = ""
        focused = true
    }
}
