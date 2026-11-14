import SwiftUI
import CoreData

enum OwnerFilter: Hashable {
    case everyone
    case mine
    case unassigned
    case person(String)
}

/// One boxed heading on the sheet: a category, or the tasks that have none.
private struct Bucket: Identifiable {
    let id: String
    let category: TaskCategory?
    let label: String
    let colorIndex: Int?
}

struct TaskListView: View {
    let filter: SidebarItem

    @EnvironmentObject private var store: Persistence
    @FetchRequest(fetchRequest: TaskCategory.all) private var categories: FetchedResults<TaskCategory>
    @FetchRequest(fetchRequest: TaskItem.all) private var tasks: FetchedResults<TaskItem>
    @FetchRequest(fetchRequest: Board.all) private var boards: FetchedResults<Board>

    @AppStorage("showDone") private var showDone = false
    @AppStorage("myName") private var myName = ""
    @State private var search = ""
    @State private var ownerFilter = OwnerFilter.everyone
    @State private var editing: TaskItem?
    @State private var lastEdited: TaskItem?
    @State private var deleteRequested = false
    @State private var shareRequest: TaskCategory?

    private var board: Board? { boards.first }

    private var selectedCategory: TaskCategory? {
        if case .category(let uid) = filter { return categories.first { $0.uid == uid } }
        return nil
    }

    var body: some View {
        content
            .navigationTitle(title)
            .searchable(text: $search, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTask()
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(categories.isEmpty)
                }
                ToolbarItem {
                    Menu {
                        Picker("Owner", selection: $ownerFilter) {
                            Text("Everyone").tag(OwnerFilter.everyone)
                            if !myName.isEmpty {
                                Text("Mine (owned or involved)").tag(OwnerFilter.mine)
                            }
                            Text("Unassigned").tag(OwnerFilter.unassigned)
                            ForEach(people, id: \.self) { name in
                                Text(name).tag(OwnerFilter.person(name))
                            }
                        }
                        Toggle("Show Completed", isOn: $showDone)
                    } label: {
                        Label("Filter", systemImage: ownerFilter == .everyone
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem {
                    if let category = selectedCategory {
                        Button {
                            shareRequest = category
                        } label: {
                            Label(store.isShared(category) ? "Manage Sharing" : "Share Category",
                                  systemImage: store.isShared(category) ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                        }
                    }
                }
            }
            .sheet(item: $editing, onDismiss: finishEditing) { task in
                TaskEditor(task: task, onDelete: {
                    deleteRequested = true
                    editing = nil
                }, onClose: {
                    editing = nil
                })
                .environment(\.managedObjectContext, store.context)
                .environmentObject(store)
            }
            .categorySharing($shareRequest)
    }

    @ViewBuilder
    private var content: some View {
        if categories.isEmpty && tasks.isEmpty {
            ContentUnavailableView {
                Label("No categories yet", systemImage: "checklist")
            } description: {
                Text("Start with Home, Work, Estate Planning and Long Term. If you already use Kay2-Do on another device, give iCloud a moment to bring your list here instead.")
            } actions: {
                Button("Add Starter Categories") {
                    store.addStarterCategories()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if buckets.isEmpty && filter != .priorities {
            ContentUnavailableView("This category is no longer here", systemImage: "folder.badge.minus",
                                   description: Text("Pick another one from the sidebar."))
        } else {
            List {
                if filter == .all {
                    weekSection
                    prioritySection(limit: 3)
                }
                if filter == .priorities {
                    prioritySection(limit: nil)
                } else {
                    ForEach(buckets) { bucket in
                        Section {
                            ForEach(openTasks(in: bucket)) { task in
                                row(task, showCategory: false)
                            }
                            if let category = bucket.category, store.canEdit(category) {
                                AddTaskField(category: category, owner: defaultOwner, author: myName)
                            }
                            if showDone {
                                ForEach(doneTasks(in: bucket)) { task in
                                    row(task, showCategory: false)
                                }
                            }
                        } header: {
                            BucketHeader(label: bucket.label, colorIndex: bucket.colorIndex,
                                         people: store.participants(of: bucket.category),
                                         open: allTasks(in: bucket).filter { !$0.isDone }.count,
                                         done: allTasks(in: bucket).filter { $0.isDone }.count)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }

    // MARK: Sections

    private var weekSection: some View {
        Section {
            DatePicker("Week of", selection: Binding(
                get: { board?.weekOf ?? Date() },
                set: { store.board().weekOf = $0 }
            ), displayedComponents: .date)
            TextField("This week will be…", text: Binding(
                get: { board?.theme ?? "" },
                set: { store.board().theme = String($0.prefix(140)) }
            ))
            TextField("because…", text: Binding(
                get: { board?.because ?? "" },
                set: { store.board().because = String($0.prefix(140)) }
            ))
        } header: {
            Text("This week")
        }
        .font(.system(.body, design: .serif))
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
            if let limit = limit, starred.count > limit {
                Text("+\(starred.count - limit) more starred in the lists below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Top priorities")
        }
    }

    private func row(_ task: TaskItem, showCategory: Bool) -> some View {
        TaskRow(task: task, showCategory: showCategory, editable: store.canEdit(task), myName: myName) {
            open(task)
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
        let mine = categories.filter { store.isMine($0) }
        let others = categories.filter { !store.isMine($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var list = (mine + others).map(bucket(for:))
        if tasks.contains(where: { $0.category == nil }) {
            list.append(Bucket(id: "__none", category: nil, label: "Uncategorized", colorIndex: nil))
        }
        return list
    }

    private func bucket(for category: TaskCategory) -> Bucket {
        Bucket(id: category.uid ?? category.objectID.uriRepresentation().absoluteString,
               category: category, label: category.name, colorIndex: category.color)
    }

    private func allTasks(in bucket: Bucket) -> [TaskItem] {
        tasks.filter { $0.category == bucket.category }
    }

    private func openTasks(in bucket: Bucket) -> [TaskItem] {
        allTasks(in: bucket).filter { !$0.isDone && matches($0) }.sorted(by: TaskItem.order)
    }

    private func doneTasks(in bucket: Bucket) -> [TaskItem] {
        allTasks(in: bucket).filter { $0.isDone && matches($0) }.sorted(by: TaskItem.order)
    }

    private var starred: [TaskItem] {
        tasks.filter { !$0.isDone && $0.isStarred && matches($0) }.sorted(by: TaskItem.order)
    }

    /// Everyone named as an owner or as involved, other than you, for the filter menu.
    private var people: [String] {
        var names: [String] = []
        for task in tasks { names.append(contentsOf: [task.ownerName] + task.sharedNames) }
        return People.unique(names)
            .filter { !People.same($0, myName) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var defaultOwner: String {
        switch ownerFilter {
        case .person(let name): return name
        case .mine: return myName
        case .everyone, .unassigned: return ""
        }
    }

    private func matches(_ task: TaskItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty,
           !task.titleText.lowercased().contains(query),
           !task.notesText.lowercased().contains(query) {
            return false
        }
        switch ownerFilter {
        case .everyone: return true
        case .mine: return task.involves(myName)
        case .unassigned: return task.ownerName.isEmpty
        case .person(let name): return task.involves(name)
        }
    }

    // MARK: Editing

    private func open(_ task: TaskItem) {
        deleteRequested = false
        lastEdited = task
        editing = task
    }

    private func newTask() {
        let category = selectedCategory ?? categories.first { store.isMine($0) } ?? categories.first
        let task = store.addTask(title: "", in: category, createdBy: myName)
        task.owner = defaultOwner
        if filter == .priorities { task.priority = true }
        open(task)
    }

    /// Runs once the editor has closed, so nothing is still showing the task
    /// when it is removed. A task left without a title is discarded.
    private func finishEditing() {
        defer {
            lastEdited = nil
            deleteRequested = false
            store.save()
        }
        guard let task = lastEdited, !task.isGone else { return }
        let untitled = task.titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if deleteRequested || untitled {
            store.context.delete(task)
        }
    }
}

private struct BucketHeader: View {
    let label: String
    let colorIndex: Int?
    let people: [String]
    let open: Int
    let done: Int

    var body: some View {
        HStack(spacing: 8) {
            CategorySwatch(colorIndex: colorIndex)
            Text(label)
                .fontWeight(.bold)
            if !people.isEmpty {
                Label(people.count == 1 ? people[0] : "\(people.count) people", systemImage: "person.2.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Text(done > 0 ? "\(open) open · \(done) done" : "\(open) open")
                .monospacedDigit()
        }
    }
}

private struct AddTaskField: View {
    let category: TaskCategory
    let owner: String
    let author: String

    @EnvironmentObject private var store: Persistence
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
        guard !title.isEmpty, !category.isGone else { return }
        let task = store.addTask(title: title, in: category, createdBy: author)
        task.owner = owner
        text = ""
        focused = true
    }
}
