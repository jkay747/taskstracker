import SwiftUI

enum SidebarItem: Hashable {
    case all
    case priorities
    /// A category, by its key.
    case category(String)
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: SidebarItem? = .all
    @State private var showSettings = false
    @State private var newListName = ""
    @State private var askNewList = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    SidebarRow(title: "All Tasks", systemImage: "tray.full", colorIndex: nil,
                               count: store.tasks.filter { !$0.done }.count,
                               late: store.tasks.filter { $0.isLate }.count)
                        .tag(SidebarItem.all)
                    SidebarRow(title: "Top Priorities", systemImage: "star", colorIndex: nil,
                               count: store.tasks.filter { !$0.done && $0.priority }.count,
                               late: 0)
                        .tag(SidebarItem.priorities)
                }
                if !store.categories.isEmpty {
                    Section("Categories") {
                        ForEach(store.categories) { category in
                            SidebarRow(title: category.name, systemImage: nil, colorIndex: category.color,
                                       count: store.tasks.filter { !$0.done && $0.categoryKey == category.key }.count,
                                       late: store.tasks.filter { $0.isLate && $0.categoryKey == category.key }.count)
                                .tag(SidebarItem.category(category.key))
                        }
                    }
                }
                if store.people.filter({ !$0.pending }).count > 1 {
                    Section("Shared with") {
                        ForEach(store.people.filter { !$0.pending && $0.userID != store.myID }) { member in
                            Label(member.name, systemImage: "person")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle(store.listName)
            .toolbar {
                ToolbarItem {
                    Menu {
                        if store.lists.count > 1 {
                            Picker("List", selection: Binding(
                                get: { store.listID ?? "" },
                                set: { store.switchList(to: $0) }
                            )) {
                                ForEach(store.lists) { list in
                                    Text(list.name).tag(list.id)
                                }
                            }
                            Divider()
                        }
                        Button("New List…") { newListName = ""; askNewList = true }
                        Button("Refresh") { store.refreshNow() }
                        Button("List Settings…") { showSettings = true }
                        Divider()
                        Button("Sign Out") { Task { await store.signOut() } }
                    } label: {
                        Label("List", systemImage: "slider.horizontal.3")
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            #endif
        } detail: {
            NavigationStack {
                TaskListView(filter: selection ?? .all)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .alert("New list", isPresented: $askNewList) {
            TextField("List name", text: $newListName)
            Button("Create") {
                let name = newListName
                Task {
                    do { try await store.createList(named: name) } catch { store.handle(error, doing: "create the list") }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: store.categories) { _, categories in
            if case .category(let key) = selection, !categories.contains(where: { $0.key == key }) {
                selection = .all
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String?
    let colorIndex: Int?
    let count: Int
    let late: Int

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            } else {
                CategorySwatch(colorIndex: colorIndex)
                    .frame(width: 18)
            }
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if late > 0 {
                Text("\(late) overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.red)
            }
            Text("\(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
